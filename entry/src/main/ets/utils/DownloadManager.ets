import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileShare, fileUri } from '@kit.CoreFileKit';
import { request } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { GequhaiApi } from '../model/GequhaiApi';
import { DownloadInfo, SongItem } from '../model/SongItem';
import { PreferencesUtil } from './PreferencesUtil';
import { serializeItems, deserializeItems } from './DownloadStorage';
import { PlaybackManager } from './PlaybackManager';
import {
  NetworkKind,
  StartDecision,
  TransitionAction,
  networkKindFromBearerTypes,
  decideStart,
  networkTransitionAction
} from './NetworkUtil';

/** 下载任务状态。 */
export enum DownloadState {
  /** 等待 WLAN 连接后自动开始。 */
  WAITING = 'waiting',
  /** 正在解析下载直链。 */
  RESOLVING = 'resolving',
  /** 等待用户确认是否覆盖已存在的同名文件。 */
  CONFIRMING = 'confirming',
  /** 正在下载。 */
  DOWNLOADING = 'downloading',
  /** 已暂停（用户手动暂停或切换到移动网络自动暂停）。 */
  PAUSED = 'paused',
  /** 已完成。 */
  COMPLETED = 'completed',
  /** 失败。 */
  FAILED = 'failed'
}

/**
 * 单个下载任务。使用 @Observed，配合列表项的 @ObjectLink 实现进度/状态的局部刷新。
 */
@Observed
export class DownloadItem {
  /** 列表唯一键。 */
  key: string;
  /** 歌曲 id，用于调用歌曲海下载接口。 */
  songId: string;
  title: string;
  singer: string;
  playUrl: string;
  state: DownloadState = DownloadState.WAITING;
  fileName: string = '';
  receivedSize: number = 0;
  totalSize: number = 0;
  errorMsg: string = '';
  /** 用户是否已确认允许使用移动数据下载。 */
  allowMobile: boolean = false;
  /** 是否因 WLAN->移动网络切换而被自动暂停（用于回到 WLAN 时自动恢复）。 */
  pausedByNetwork: boolean = false;
  /** 下载完成后的本地文件路径（沙箱路径或 file:// URI），用于播放。 */
  filePath: string = '';
  /** 是否正在播放该文件（运行时状态，不持久化）。 */
  isPlaying: boolean = false;
  /** 创建任务的时间戳（毫秒），用于列表显示。 */
  createdAt: number = 0;

  constructor(key: string, songId: string, title: string, singer: string, playUrl: string) {
    this.key = key;
    this.songId = songId;
    this.title = title;
    this.singer = singer;
    this.playUrl = playUrl;
  }
}

const POLL_INTERVAL_MS: number = 3000;

/**
 * 下载列表 + 网络感知下载管理器（进程内单例）。
 *
 * 负责：
 * - 维护下载列表（新增/暂停/继续/重试/删除）
 * - 解析直链并创建 request.downloadFile 任务
 * - 监听网络变化：WLAN->移动网络暂停、移动网络->WLAN 自动继续
 */
export class DownloadManager {
  private static instance: DownloadManager | null = null;

  private items: DownloadItem[] = [];
  private tasks: Map<string, request.DownloadTask> = new Map<string, request.DownloadTask>();
  private context: common.UIAbilityContext | null = null;
  private downloadPath: string = '';
  private downloadType: string = 'mp3';
  private quarkCookie: string = '';

  private itemsListener: (() => void) | null = null;
  private networkListener: ((kind: NetworkKind) => void) | null = null;
  /** 目标文件已存在时，询问用户是否覆盖；返回 false 表示取消下载。 */
  private overwriteConfirm: ((fileName: string) => Promise<boolean>) | null = null;

  private currentNetwork: NetworkKind = 'unknown';
  private networkStarted: boolean = false;
  private netConnection: connection.NetConnection | null = null;
  private pollTimer: number = -1;
  private seq: number = 0;

  static getInstance(): DownloadManager {
    if (DownloadManager.instance === null) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  /** 应用启动时初始化上下文与设置，恢复已保存的下载列表，并开始监听网络。 */
  async init(context: common.UIAbilityContext, downloadPath: string, downloadType: string, quarkCookie: string): Promise<void> {
    this.context = context;
    this.downloadPath = downloadPath;
    this.downloadType = downloadType;
    this.quarkCookie = quarkCookie;
    await this.restoreItems();
    this.startNetworkWatch();
  }

  /** 从持久化存储恢复下载列表。 */
  private async restoreItems(): Promise<void> {
    try {
      const json = await PreferencesUtil.getDownloadItems();
      const restored = deserializeItems(json);
      if (restored.length > 0) {
        this.items = restored;
        for (let i = 0; i < this.items.length; i++) {
          if (this.seq < Number(this.items[i].key.split('_').pop())) {
            this.seq = Number(this.items[i].key.split('_').pop());
          }
        }
        console.info('restored download items: ' + this.items.length);
      }
    } catch (e) {
      console.warn('restore download items failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
  }

  /** 将下载列表持久化到存储。 */
  private persistItems(): void {
    PreferencesUtil.setDownloadItems(serializeItems(this.items)).catch((e: Error) => {
      console.warn('persist download items failed: ' + e.message);
    });
  }

  /** 设置（路径/类型/Cookie）变化时同步更新。 */
  updateSettings(downloadPath: string, downloadType: string, quarkCookie: string): void {
    this.downloadPath = downloadPath;
    this.downloadType = downloadType;
    this.quarkCookie = quarkCookie;
  }

  /** 列表结构变化（新增/删除）时回调，UI 重新绑定数组。 */
  setItemsListener(listener: () => void): void {
    this.itemsListener = listener;
  }

  /** 网络类型变化时回调。 */
  setNetworkListener(listener: (kind: NetworkKind) => void): void {
    this.networkListener = listener;
  }

  setOverwriteConfirm(callback: (fileName: string) => Promise<boolean>): void {
    this.overwriteConfirm = callback;
  }

  getItems(): DownloadItem[] {
    return this.items;
  }

  /** 是否已有该歌曲的未结束下载任务。 */
  hasActive(songId: string): boolean {
    for (let i = 0; i < this.items.length; i++) {
      const it = this.items[i];
      if (it.songId === songId && it.state !== DownloadState.COMPLETED && it.state !== DownloadState.FAILED) {
        return true;
      }
    }
    return false;
  }

  /** 是否已有该歌曲的任意下载任务（含已完成/失败），用于详情页去重，避免重复点击创建多个任务。 */
  hasAny(songId: string): boolean {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].songId === songId) {
        return true;
      }
    }
    return false;
  }

  /**
   * @ObjectLink 传给子组件的是 @Observed 代理对象，其引用与 items 中保存的原始对象不同。
   * 所有会修改任务状态的方法都必须先把传入对象归一化为 items 中的原始对象，
   * 否则修改落在代理上，列表界面（绑定原始对象）不会刷新。
   */
  private canonical(item: DownloadItem): DownloadItem {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key === item.key) {
        return this.items[i];
      }
    }
    return item;
  }

  getCurrentNetwork(): NetworkKind {
    return this.currentNetwork;
  }

  /** 实时读取当前网络类型。 */
  getNetworkKind(): NetworkKind {
    try {
      const handle = connection.getDefaultNetSync();
      if (!handle || handle.netId === 0) {
        return 'none';
      }
      const caps = connection.getNetCapabilitiesSync(handle);
      const types: number[] = [];
      const bearer = caps.bearerTypes;
      if (bearer) {
        for (let i = 0; i < bearer.length; i++) {
          types.push(bearer[i] as number);
        }
      }
      return networkKindFromBearerTypes(types);
    } catch (e) {
      console.warn('getNetworkKind failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      return 'unknown';
    }
  }

  private startNetworkWatch(): void {
    if (this.networkStarted) {
      return;
    }
    this.networkStarted = true;
    this.currentNetwork = this.getNetworkKind();
    try {
      this.netConnection = connection.createNetConnection();
      this.netConnection.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
        this.onNetCapabilityChange(info);
      });
      this.netConnection.register(() => {
        console.info('net connection registered');
      });
    } catch (e) {
      console.warn('register net listener failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    try {
      this.pollTimer = setInterval(() => {
        this.evaluateNetwork();
      }, POLL_INTERVAL_MS);
    } catch (e) {
      console.warn('start network poll failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
  }

  private onNetCapabilityChange(info: connection.NetCapabilityInfo): void {
    console.info('net capability changed, netId=' + info.netHandle.netId);
    this.evaluateNetwork();
  }

  /** 重新判定网络类型并处理切换动作。forced 仅用于测试/调试时注入网络类型。 */
  evaluateNetwork(forced?: NetworkKind): void {
    const next = forced !== undefined ? forced : this.getNetworkKind();
    if (next === this.currentNetwork) {
      return;
    }
    const prev = this.currentNetwork;
    this.currentNetwork = next;
    console.info('network changed: ' + prev + ' -> ' + next);
    if (this.networkListener) {
      this.networkListener(next);
    }
    const action: TransitionAction = networkTransitionAction(prev, next);
    if (action === 'pause') {
      this.pauseActiveForNetwork();
    }
    // 只要回到 WLAN，就恢复被网络暂停的任务，并开始等待中的任务。
    if (next === 'wlan') {
      this.resumePausedForNetwork();
      this.startWaitingItems();
    }
  }

  private pauseActiveForNetwork(): void {
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      const active = item.state === DownloadState.DOWNLOADING || item.state === DownloadState.RESOLVING;
      if (active && !item.allowMobile) {
        item.pausedByNetwork = true;
        this.pauseItem(item);
      }
    }
  }

  private resumePausedForNetwork(): void {
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.state === DownloadState.PAUSED && item.pausedByNetwork) {
        item.pausedByNetwork = false;
        this.resumeItem(item);
      }
    }
  }

  private startWaitingItems(): void {
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      if (item.state === DownloadState.WAITING) {
        this.startItem(item);
      }
    }
  }

  /**
   * 新增下载任务。
   * @param allowMobile 用户是否已确认允许使用移动数据
   */
  async enqueue(song: SongItem, allowMobile: boolean): Promise<DownloadItem> {
    this.seq++;
    const item = new DownloadItem(`dl_${Date.now()}_${this.seq}`, song.id, song.title, song.singer, song.playUrl);
    item.createdAt = Date.now();
    item.allowMobile = allowMobile;
    this.items.unshift(item);
    this.notifyItems();

    const decision: StartDecision = decideStart(this.getNetworkKind(), allowMobile);
    if (decision === 'start') {
      await this.startItem(item);
    } else {
      item.state = DownloadState.WAITING;
      this.notifyItems();
    }
    return item;
  }

  /** 解析直链并创建下载任务。 */
  async startItem(item: DownloadItem): Promise<void> {
    item = this.canonical(item);
    // 先把状态同步切到 RESOLVING，保证界面立即响应；Cookie 刷新放到状态更新之后。
    item.state = DownloadState.RESOLVING;
    item.errorMsg = '';
    item.receivedSize = 0;
    item.totalSize = 0;
    item.pausedByNetwork = false;
    this.notifyItems();

    // 重新读取最新 Cookie：用户可能在任务失败后到“我的”重新登录夸克，
    // 必须让“重试”使用刚保存的新 Cookie，而不是内存里的旧值。
    try {
      const latestCookie = await PreferencesUtil.getQuarkCookie();
      if (latestCookie) {
        this.quarkCookie = latestCookie;
      }
    } catch (e) {
      console.warn('reload cookie for download failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    const ctx = this.context;
    if (ctx === null || !this.downloadPath) {
      item.state = DownloadState.FAILED;
      item.errorMsg = '未配置下载路径';
      this.notifyItems();
      return;
    }

    let info: DownloadInfo | null = null;
    try {
      info = await GequhaiApi.getDownloadInfo(item.playUrl, item.songId, this.quarkCookie, this.downloadType);
    } catch (e) {
      console.warn('getDownloadInfo failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    // 解析期间用户可能已暂停/取消。
    if (item.state !== DownloadState.RESOLVING) {
      return;
    }
    if (info === null || !info.url) {
      item.state = DownloadState.FAILED;
      if (info !== null && info.errorHint && info.errorHint.length > 0) {
        item.errorMsg = info.errorHint;
      } else if (info !== null && info.isQuarkShare) {
        item.errorMsg = '夸克链接解析失败';
      } else {
        item.errorMsg = '获取下载链接失败';
      }
      this.notifyItems();
      return;
    }

    const url = info.url;
    let fileName = '';
    if (info.fileNameHint && info.fileNameHint.length > 0) {
      fileName = this.sanitizeFileName(info.fileNameHint);
    }
    if (!fileName) {
      let ext = 'mp3';
      const urlPath = url.split('?')[0];
      const dot = urlPath.lastIndexOf('.');
      if (dot > 0 && dot >= urlPath.length - 6) {
        ext = urlPath.substring(dot + 1);
      }
      fileName = `${this.sanitizeFileName(item.title)} - ${this.sanitizeFileName(item.singer || 'unknown')}.${ext}`;
    }
    item.fileName = fileName;

    const isUriTarget = this.downloadPath.startsWith('file://');
    const sep = this.downloadPath.endsWith('/') ? '' : '/';
    const targetPath = `${this.downloadPath}${sep}${fileName}`;

    // 目标目录已有同名文件时先询问是否覆盖，避免用户不知情地覆盖旧文件。
    if (this.fileExists(targetPath, fileName)) {
      item.state = DownloadState.CONFIRMING;
      this.notifyItems();
      let overwrite = false;
      if (this.overwriteConfirm !== null) {
        try {
          overwrite = await this.overwriteConfirm(fileName);
        } catch (e) {
          console.warn('overwrite confirm failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
          overwrite = false;
        }
      } else {
        // 没有 UI 回调时保持原有行为（直接覆盖）。
        overwrite = true;
      }
      if (!overwrite) {
        item.state = DownloadState.FAILED;
        item.errorMsg = '已取消：文件已存在';
        this.notifyItems();
        return;
      }
    }

    const sandboxDir = `${ctx.filesDir}/downloads`;
    try {
      if (!fs.accessSync(sandboxDir)) {
        fs.mkdirSync(sandboxDir, true);
      }
    } catch (e) {
      console.warn('mkdir sandbox dir failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }

    // request.downloadFile 要求目标文件不存在，否则报 13400002。
    // 保存到所选目录时先下载到沙箱唯一子目录，再拷贝过去。
    let downloadFilePath = targetPath;
    let stagingDir = '';
    if (isUriTarget) {
      stagingDir = `${sandboxDir}/${Date.now()}_${this.seq}`;
      try {
        fs.mkdirSync(stagingDir, true);
      } catch (e) {
        console.warn('mkdir staging dir failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      }
      downloadFilePath = `${stagingDir}/${fileName}`;
    }
    try {
      if (fs.accessSync(downloadFilePath)) {
        fs.unlinkSync(downloadFilePath);
      }
    } catch (e) {
      // 文件不存在时忽略
    }

    const config: request.DownloadConfig = {
      url: url,
      filePath: downloadFilePath,
      enableMetered: true,
      enableRoaming: true
    };
    if (info.downloadHeaders) {
      config.header = info.downloadHeaders;
    }

    try {
      const task = await request.downloadFile(ctx, config);
      this.tasks.set(item.key, task);
      item.state = DownloadState.DOWNLOADING;
      this.notifyItems();
      this.bindTask(item, task, downloadFilePath, stagingDir, isUriTarget, targetPath);
    } catch (e) {
      item.state = DownloadState.FAILED;
      item.errorMsg = '创建下载任务失败';
      this.notifyItems();
      console.error('create download task failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
  }

  private bindTask(item: DownloadItem, task: request.DownloadTask, downloadFilePath: string,
    stagingDir: string, isUriTarget: boolean, targetPath: string): void {
    task.on('progress', (received: number, total: number) => {
      item.receivedSize = received;
      item.totalSize = total;
    });
    task.on('complete', () => {
      this.tasks.delete(item.key);
      this.handleComplete(item, downloadFilePath, stagingDir, isUriTarget, targetPath);
    });
    task.on('fail', (err: number) => {
      this.tasks.delete(item.key);
      item.state = DownloadState.FAILED;
      item.errorMsg = `下载失败(${err})`;
      this.notifyItems();
      console.error('download fail: ' + err + ', item=' + item.title);
    });
    task.on('pause', () => {
      if (item.state === DownloadState.DOWNLOADING) {
        item.state = DownloadState.PAUSED;
      }
    });
  }

  private async handleComplete(item: DownloadItem, downloadFilePath: string, stagingDir: string,
    isUriTarget: boolean, targetPath: string): Promise<void> {
    if (isUriTarget) {
      const ok = await this.copyToSelectedDir(downloadFilePath, this.downloadPath, targetPath);
      try {
        fs.unlinkSync(downloadFilePath);
      } catch (e) {
        // ignore
      }
      if (stagingDir) {
        try {
          fs.rmdirSync(stagingDir);
        } catch (e) {
          // ignore
        }
      }
      if (!ok) {
        item.state = DownloadState.FAILED;
        item.errorMsg = '保存到所选目录失败';
        this.notifyItems();
        return;
      }
    }
    item.state = DownloadState.COMPLETED;
    if (item.totalSize > 0) {
      item.receivedSize = item.totalSize;
    }
    item.filePath = targetPath;
    this.notifyItems();
  }

  /** 暂停任务（未开始的任务直接标记为暂停）。 */
  async pauseItem(item: DownloadItem): Promise<void> {
    item = this.canonical(item);
    if (item.state === DownloadState.COMPLETED || item.state === DownloadState.FAILED) {
      return;
    }
    const task = this.tasks.get(item.key);
    if (task === undefined) {
      item.state = DownloadState.PAUSED;
      this.notifyItems();
      return;
    }
    try {
      await task.suspend();
    } catch (e) {
      console.warn('suspend failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    item.state = DownloadState.PAUSED;
    this.notifyItems();
  }

  /** 继续任务（已暂停的恢复，未开始的重新开始）。 */
  async resumeItem(item: DownloadItem): Promise<void> {
    item = this.canonical(item);
    if (item.state === DownloadState.DOWNLOADING || item.state === DownloadState.RESOLVING) {
      return;
    }
    const task = this.tasks.get(item.key);
    if (task !== undefined) {
      try {
        const ok = await task.restore();
        if (ok) {
          item.state = DownloadState.DOWNLOADING;
        }
      } catch (e) {
        console.warn('restore failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      }
      this.notifyItems();
      return;
    }
    await this.startItem(item);
  }

  /** 用户确认使用移动网络后继续/开始下载。 */
  async resumeWithMobile(item: DownloadItem): Promise<void> {
    item = this.canonical(item);
    item.allowMobile = true;
    item.pausedByNetwork = false;
    await this.resumeItem(item);
  }

  /** 失败后重试。 */
  async retryItem(item: DownloadItem): Promise<void> {
    item = this.canonical(item);
    const task = this.tasks.get(item.key);
    if (task !== undefined) {
      try {
        await task.delete();
      } catch (e) {
        // ignore
      }
      this.tasks.delete(item.key);
    }
    await this.startItem(item);
  }

  /** 从列表移除（下载中的任务会先删除）。deleteFile=true 时同时删除本地文件。 */
  removeItem(item: DownloadItem, deleteFile: boolean = false): void {
    item = this.canonical(item);
    // 若正在播放该文件，先停止播放器。
    if (item.isPlaying) {
      PlaybackManager.getInstance().stop();
    }
    if (deleteFile && item.filePath) {
      this.deleteLocalFile(item.filePath);
    }
    const task = this.tasks.get(item.key);
    if (task !== undefined) {
      task.delete().then(() => {
        console.info('task deleted: ' + item.title);
      }).catch((e: Error) => {
        console.warn('delete task failed: ' + e.message);
      });
      this.tasks.delete(item.key);
    }
    // 注意：@ObjectLink 交给子组件的是 @Observed 代理对象，与列表中的原始对象
    // 引用不同，不能用 indexOf(item) 比较。这里统一按 key 定位。
    let idx = -1;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key === item.key) {
        idx = i;
        break;
      }
    }
    if (idx >= 0) {
      this.items.splice(idx, 1);
    }
    this.notifyItems();
  }

  private notifyItems(): void {
    this.persistItems();
    if (this.itemsListener) {
      this.itemsListener();
    }
  }

  /** 删除本地文件：兼容沙箱路径与 file:// URI。 */
  private deleteLocalFile(filePath: string): void {
    let path = filePath;
    if (path.startsWith('file://')) {
      try {
        path = new fileUri.FileUri(path).path;
      } catch (e) {
        console.warn('resolve file uri for delete failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
        return;
      }
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
        console.info('deleted local file: ' + path);
      }
    } catch (e) {
      console.warn('delete local file failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
  }

  /**
   * 判断目标文件是否已存在。
   * 兼容应用沙箱路径与用户通过“选择目录”获得的 file:// URI。
   */
  private fileExists(target: string, fileName: string): boolean {
    try {
      if (fs.accessSync(target)) {
        return true;
      }
    } catch (e) {
      // 继续尝试其它方式
    }
    if (target.startsWith('file://')) {
      try {
        const realPath = new fileUri.FileUri(target).path;
        if (realPath && realPath !== target && fs.accessSync(realPath)) {
          return true;
        }
      } catch (e) {
        console.warn('resolve file uri path failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      }
      // 兜底：列出目标目录，按文件名比对
      try {
        const dirPath = new fileUri.FileUri(this.downloadPath).path;
        const names: string[] = fs.listFileSync(dirPath);
        for (let i = 0; i < names.length; i++) {
          if (names[i] === fileName) {
            return true;
          }
        }
      } catch (e) {
        console.warn('list target dir failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      }
    }
    return false;
  }

  sanitizeFileName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_').trim();
  }

  /**
   * 把沙箱中的文件复制到用户通过“选择目录”选定的 URI。
   * 不同设备/系统版本对文件 URI 的写入方式支持不同，这里依次尝试多种方式。
   */
  async copyToSelectedDir(srcPath: string, dirUri: string, fileUriStr: string): Promise<boolean> {
    let srcUri = srcPath;
    try {
      srcUri = fileUri.getUriFromPath(srcPath);
    } catch (e) {
      console.warn('getUriFromPath failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    try {
      await fs.copy(srcUri, fileUriStr);
      console.info('copy to file uri ok: ' + fileUriStr);
      return true;
    } catch (e) {
      console.warn('copy to file uri failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    try {
      await fs.copy(srcUri, dirUri);
      console.info('copy to dir uri ok: ' + dirUri);
      return true;
    } catch (e) {
      console.warn('copy to dir uri failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    try {
      const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(fileUriStr, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
      console.info('copy via fd ok: ' + fileUriStr);
      return true;
    } catch (e) {
      console.error('copy via fd failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    return false;
  }
}
