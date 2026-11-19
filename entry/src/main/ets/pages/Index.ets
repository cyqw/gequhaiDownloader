import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileShare } from '@kit.CoreFileKit';
import { promptAction, router } from '@kit.ArkUI';
import { GequhaiApi } from '../model/GequhaiApi';
import { SongItem } from '../model/SongItem';
import { PreferencesUtil, DOWNLOAD_TYPE_MP3, DOWNLOAD_TYPE_FLAC } from '../utils/PreferencesUtil';
import { DownloadManager, DownloadItem, DownloadState } from '../utils/DownloadManager';
import { PlaybackManager } from '../utils/PlaybackManager';
import { NetworkKind } from '../utils/NetworkUtil';
import { formatDownloadPath } from '../utils/PathUtil';

@Component
struct DownloadRow {
  @ObjectLink item: DownloadItem;
  @Prop isPlaying: boolean = false;
  onAction: (item: DownloadItem) => void = () => {};
  onDelete: (item: DownloadItem) => void = () => {};

  statusText(): string {
    switch (this.item.state) {
      case DownloadState.WAITING:
        return '等待 WLAN 连接';
      case DownloadState.RESOLVING:
        return '正在解析下载链接...';
      case DownloadState.CONFIRMING:
        return '等待确认是否覆盖';
      case DownloadState.DOWNLOADING: {
        const pct = this.item.totalSize > 0 ? Math.floor(this.item.receivedSize * 100 / this.item.totalSize) : 0;
        return `${pct}%  ${this.formatSize(this.item.receivedSize)} / ${this.formatSize(this.item.totalSize)}`;
      }
      case DownloadState.PAUSED:
        return '已暂停';
      case DownloadState.COMPLETED:
        return '已完成';
      case DownloadState.FAILED:
        return this.item.errorMsg.length > 0 ? `失败：${this.item.errorMsg}` : '失败';
      default:
        return '';
    }
  }

  statusColor(): string {
    switch (this.item.state) {
      case DownloadState.COMPLETED:
        return '#2E7D32';
      case DownloadState.FAILED:
        return '#C62828';
      case DownloadState.PAUSED:
      case DownloadState.WAITING:
      case DownloadState.CONFIRMING:
        return '#E65100';
      default:
        return '#666666';
    }
  }

  actionLabel(): string {
    switch (this.item.state) {
      case DownloadState.DOWNLOADING:
      case DownloadState.RESOLVING:
      case DownloadState.CONFIRMING:
        return '暂停';
      case DownloadState.PAUSED:
      case DownloadState.WAITING:
        return '继续';
      case DownloadState.FAILED:
        return '重试';
      case DownloadState.COMPLETED:
        // 已完成条目由独立的 ✕ 删除按钮处理（带“是否删除本地文件”提示），此处不再显示重复按钮。
        return '';
      default:
        return '';
    }
  }

  formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const kb = bytes / 1024;
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`;
    }
    const mb = kb / 1024;
    if (mb < 1024) {
      return `${mb.toFixed(1)} MB`;
    }
    return `${(mb / 1024).toFixed(2)} GB`;
  }

  formatCreatedAt(ts: number): string {
    if (!ts || ts <= 0) {
      return '';
    }
    const d = new Date(ts);
    const mm = d.getMonth() + 1;
    const dd = d.getDate();
    const hh = d.getHours();
    const mi = d.getMinutes();
    const p2 = (n: number): string => (n < 10 ? '0' + n : '' + n);
    return `${mm}-${dd} ${p2(hh)}:${p2(mi)}`;
  }

  build() {
    Row() {
      Column() {
        Text(this.item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(this.item.singer.length > 0 ? this.item.singer : '未知歌手')
            .fontSize(12)
            .fontColor('#888888')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.formatCreatedAt(this.item.createdAt).length > 0) {
            Text(this.formatCreatedAt(this.item.createdAt))
              .fontSize(11)
              .fontColor('#AAAAAA')
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .margin({ top: 2 })
        Text(this.statusText())
          .fontSize(12)
          .fontColor(this.statusColor())
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.item.state === DownloadState.DOWNLOADING || this.item.state === DownloadState.PAUSED) {
          Progress({
            value: this.item.receivedSize,
            total: this.item.totalSize > 0 ? this.item.totalSize : 1,
            type: ProgressType.Linear
          })
            .width('100%')
            .margin({ top: 6 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.item.state === DownloadState.COMPLETED) {
        Text(this.isPlaying ? '⏸' : '▶')
          .fontSize(22)
          .fontColor(this.isPlaying ? '#31C27C' : '#666666')
          .margin({ left: 4, right: 8 })
          .onClick(() => {
            PlaybackManager.getInstance().toggle(this.item);
          })
      }

      Text(this.actionLabel())
        .fontSize(14)
        .fontColor('#007DFF')
        .margin({ left: 12 })
        .onClick(() => {
          this.onAction(this.item);
        })

      Text('✕')
        .fontSize(18)
        .fontColor('#C62828')
        .margin({ left: 12, right: 4 })
        .onClick(() => {
          this.onDelete(this.item);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State keyword: string = '';
  @State songs: SongItem[] = [];
  @State searching: boolean = false;
  @State downloadPath: string = '';
  @State quarkCookie: string = '';
  @State downloadType: string = DOWNLOAD_TYPE_MP3;
  @State downloadItems: DownloadItem[] = [];
  @State networkKind: NetworkKind = 'unknown';
  @State playingKey: string = '';
  @State downloadFilter: string = 'all';

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  filterLabel(filter: string): string {
    if (filter === 'completed') {
      return '已完成';
    }
    if (filter === 'active') {
      return '进行中';
    }
    if (filter === 'failed') {
      return '失败';
    }
    return '全部';
  }

  /** 按当前过滤条件返回下载项。 */
  filteredDownloadItems(): DownloadItem[] {
    const all = this.downloadItems;
    if (this.downloadFilter === 'all') {
      return all;
    }
    const result: DownloadItem[] = [];
    for (let i = 0; i < all.length; i++) {
      const it = all[i];
      if (this.downloadFilter === 'completed' && it.state === DownloadState.COMPLETED) {
        result.push(it);
      } else if (this.downloadFilter === 'active' && it.state !== DownloadState.COMPLETED &&
        it.state !== DownloadState.FAILED) {
        result.push(it);
      } else if (this.downloadFilter === 'failed' && it.state === DownloadState.FAILED) {
        result.push(it);
      }
    }
    return result;
  }

  aboutToAppear(): void {
    this.initSettings();
  }

  onPageShow(): void {
    this.reloadQuarkCookie();
  }

  async reloadQuarkCookie(): Promise<void> {
    try {
      if (!this.quarkCookie) {
        await PreferencesUtil.init(this.context);
      }
      this.quarkCookie = await PreferencesUtil.getQuarkCookie();
      if (this.downloadPath) {
        DownloadManager.getInstance().updateSettings(this.downloadPath, this.downloadType, this.quarkCookie);
      }
    } catch (e) {
      console.error('reload quark cookie failed: ' + JSON.stringify(e));
    }
  }

  async initSettings(): Promise<void> {
    await PreferencesUtil.init(this.context);
    const defaultPath = `${this.context.filesDir}/downloads`;
    const saved = await PreferencesUtil.getDownloadPath(defaultPath);
    this.downloadPath = saved;
    this.quarkCookie = await PreferencesUtil.getQuarkCookie();
    this.downloadType = await PreferencesUtil.getDownloadType();
    await this.activateDownloadPermission();
    try {
      if (!this.downloadPath.startsWith('file://') && !fs.accessSync(this.downloadPath)) {
        fs.mkdirSync(this.downloadPath, true);
      }
    } catch (e) {
      console.error('Failed to ensure download dir: ' + JSON.stringify(e));
    }

    const manager = DownloadManager.getInstance();
    manager.setItemsListener(() => {
      this.downloadItems = manager.getItems().slice();
    });
    manager.setNetworkListener((kind: NetworkKind) => {
      this.networkKind = kind;
    });
    PlaybackManager.getInstance().setListener((key: string) => {
      this.playingKey = key;
    });
    manager.setOverwriteConfirm(async (fileName: string): Promise<boolean> => {
      const res = await promptAction.showDialog({
        title: '文件已存在',
        message: `同名文件“${fileName}”已存在，是否覆盖？`,
        buttons: [
          { text: '覆盖', color: '#007DFF' },
          { text: '取消', color: '#666666' }
        ]
      });
      return res.index === 0;
    });
    await manager.init(this.context, this.downloadPath, this.downloadType, this.quarkCookie);
    this.networkKind = manager.getCurrentNetwork();
    this.downloadItems = manager.getItems().slice();
  }

  /**
   * 重新激活用户此前通过选择目录授权过的 URI 权限。
   * 选择目录时授予的是临时权限，应用重启后需要用 activatePermission 恢复，
   * 否则向该目录写入文件会失败。
   */
  async activateDownloadPermission(): Promise<void> {
    if (!this.downloadPath.startsWith('file://')) {
      return;
    }
    try {
      await fileShare.activatePermission([{
        uri: this.downloadPath,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      }]);
      console.info('activate download permission ok: ' + this.downloadPath);
    } catch (e) {
      console.warn('activate download permission failed: ' + JSON.stringify(e));
    }
  }

  async doSearch(): Promise<void> {
    const kw = this.keyword.trim();
    if (!kw) {
      promptAction.showToast({ message: '请输入歌曲名' });
      return;
    }
    this.searching = true;
    this.songs = [];
    try {
      const results = await GequhaiApi.search(kw, 1);
      this.songs = results;
      if (results.length === 0) {
        promptAction.showToast({ message: '未找到结果' });
      }
    } catch (e) {
      promptAction.showToast({ message: '搜索失败' });
    } finally {
      this.searching = false;
    }
  }

  networkText(): string {
    switch (this.networkKind) {
      case 'wlan':
        return 'WLAN';
      case 'mobile':
        return '移动网络';
      case 'none':
        return '无网络';
      default:
        return '网络未知';
    }
  }

  networkColor(): string {
    switch (this.networkKind) {
      case 'wlan':
        return '#2E7D32';
      case 'mobile':
        return '#E65100';
      case 'none':
        return '#C62828';
      default:
        return '#888888';
    }
  }

  /** 点击搜索结果：进入歌曲详情页。 */
  openDetail(song: SongItem): void {
    router.pushUrl({
      url: 'pages/SongDetail',
      params: { song: JSON.stringify(song) }
    }).catch((e: Error) => {
      console.error('open detail failed: ' + e.message);
      promptAction.showToast({ message: '打开详情页失败' });
    });
  }

  /**
   * 下载列表中条目的操作按钮：
   * - 下载中/解析中 -> 暂停
   * - 已完成 -> 删除
   * - 等待/暂停/失败 -> 继续（移动网络下先确认是否使用移动数据）
   */
  async onItemAction(item: DownloadItem): Promise<void> {
    const manager = DownloadManager.getInstance();
    if (item.state === DownloadState.DOWNLOADING || item.state === DownloadState.RESOLVING ||
      item.state === DownloadState.CONFIRMING) {
      await manager.pauseItem(item);
      return;
    }
    const kind = manager.getNetworkKind();
    if (kind === 'mobile' && !item.allowMobile) {
      const res = await promptAction.showDialog({
        title: '移动网络提示',
        message: '当前正在使用移动网络，是否使用移动网络下载？',
        buttons: [
          { text: '使用移动网络下载', color: '#007DFF' },
          { text: '取消', color: '#666666' }
        ]
      });
      if (res.index === 0) {
        await manager.resumeWithMobile(item);
      }
      return;
    }
    if (item.state === DownloadState.FAILED) {
      await manager.retryItem(item);
    } else {
      await manager.resumeItem(item);
    }
  }

  /** 删除任务：先询问是否同时删除本地文件。 */
  async onDeleteItem(item: DownloadItem): Promise<void> {
    const res = await promptAction.showDialog({
      title: '删除下载任务',
      message: '是否同时删除已下载的本地文件？',
      buttons: [
        { text: '删除文件并移除', color: '#C62828' },
        { text: '仅移除记录', color: '#666666' },
        { text: '取消', color: '#007DFF' }
      ]
    });
    if (res.index === 2) {
      return;
    }
    DownloadManager.getInstance().removeItem(item, res.index === 0);
  }

  async savePath(): Promise<void> {
    const path = this.downloadPath.trim();
    if (!path) {
      promptAction.showToast({ message: '路径不能为空' });
      return;
    }
    try {
      if (!path.startsWith('file://') && !fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      }
    } catch (e) {
      // 对于URI或无权限路径，可能无法直接校验/创建，仍允许保存
      console.warn('ensure download dir failed: ' + JSON.stringify(e));
    }
    this.downloadPath = path;
    await PreferencesUtil.setDownloadPath(path);
    DownloadManager.getInstance().updateSettings(this.downloadPath, this.downloadType, this.quarkCookie);
    promptAction.showToast({ message: '保存成功' });
  }

  async selectDownloadType(type: string): Promise<void> {
    this.downloadType = type;
    await PreferencesUtil.setDownloadType(type);
    DownloadManager.getInstance().updateSettings(this.downloadPath, this.downloadType, this.quarkCookie);
    promptAction.showToast({ message: `下载类型已设为 ${type.toUpperCase()}` });
  }

  async pickDownloadDirectory(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const result = await documentPicker.select({ selectMode: picker.DocumentSelectMode.FOLDER });
      if (result && result.length > 0) {
        this.downloadPath = result[0];
        await PreferencesUtil.setDownloadPath(this.downloadPath);
        try {
          await fileShare.persistPermission([{
            uri: this.downloadPath,
            operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
          }]);
          console.info('persist download permission ok: ' + this.downloadPath);
        } catch (e) {
          console.warn('persist download permission failed: ' + JSON.stringify(e));
        }
        DownloadManager.getInstance().updateSettings(this.downloadPath, this.downloadType, this.quarkCookie);
        promptAction.showToast({ message: '已选择下载目录' });
      }
    } catch (e) {
      console.error('pick directory error: ' + JSON.stringify(e));
      promptAction.showToast({ message: '选择目录失败' });
    }
  }

  async openQuarkAuth(): Promise<void> {
    try {
      await router.pushUrl({ url: 'pages/QuarkAuth' });
    } catch (e) {
      console.error('open quark auth failed: ' + JSON.stringify(e));
      promptAction.showToast({ message: '打开夸克登录页面失败' });
    }
  }

  @Builder
  SearchTab() {
    Column() {
      Row() {
        TextInput({ placeholder: '输入歌曲名搜索', text: this.keyword })
          .layoutWeight(1)
          .height(40)
          .onChange((value: string) => {
            this.keyword = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })
        Button(this.searching ? '搜索中' : '搜索')
          .height(40)
          .margin({ left: 8 })
          .enabled(!this.searching)
          .onClick(() => {
            this.doSearch();
          })
      }
      .width('100%')
      .padding(12)

      if (this.searching) {
        LoadingProgress().width(40).height(40).margin({ top: 20 })
      }

      if (!this.searching && this.songs.length === 0) {
        Text('在上方输入歌曲名进行搜索，点击列表项下载')
          .fontSize(14)
          .fontColor('#888888')
          .margin({ top: 24 })
      }

      List() {
        ForEach(this.songs, (item: SongItem) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.singer || '未知歌手')
                  .fontSize(13)
                  .fontColor('#666666')
                  .margin({ top: 4 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          }
          .onClick(() => {
            this.openDetail(item);
          })
        }, (item: SongItem) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 0.5, color: '#E5E5E5', startMargin: 12, endMargin: 12 })
      // 内容不足一屏时也允许上滑/下滑回弹，满足滑动到边界时的反馈动效要求。
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DownloadTab() {
    Column() {
      Row() {
        Text('下载列表')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text(this.networkText())
          .fontSize(13)
          .fontColor(this.networkColor())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      Row() {
        ForEach(['all', 'completed', 'active', 'failed'], (filter: string) => {
          Text(this.filterLabel(filter))
            .fontSize(13)
            .fontColor(this.downloadFilter === filter ? '#FFFFFF' : '#555555')
            .backgroundColor(this.downloadFilter === filter ? '#31C27C' : '#EEEEEE')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .margin({ right: 8 })
            .onClick(() => {
              this.downloadFilter = filter;
            })
        }, (filter: string) => filter)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.filteredDownloadItems().length === 0) {
        Text(this.downloadItems.length === 0
          ? '暂无下载任务，在“搜索”页点击歌曲即可加入下载列表'
          : '该分类下暂无任务')
          .fontSize(14)
          .fontColor('#888888')
          .margin({ top: 40, left: 16, right: 16 })
          .textAlign(TextAlign.Center)
          .width('100%')
      } else {
        List() {
          ForEach(this.filteredDownloadItems(), (item: DownloadItem) => {
            ListItem() {
              DownloadRow({
                item: item,
                isPlaying: this.playingKey === item.key,
                onAction: (it: DownloadItem) => {
                  this.onItemAction(it);
                },
                onDelete: (it: DownloadItem) => {
                  this.onDeleteItem(it);
                }
              })
            }
          }, (item: DownloadItem) => item.key)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: '#E5E5E5', startMargin: 12, endMargin: 12 })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MyTab() {
    Scroll() {
      Column() {
        Text('下载设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20, bottom: 16, left: 16 })
          .width('100%')

        Text('下载保存路径')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ left: 16, bottom: 8 })
          .width('100%')

        Text(formatDownloadPath(this.downloadPath))
          .fontSize(13)
          .fontColor('#333333')
          .margin({ left: 16, right: 16, bottom: 12 })
          .width('100%')

        Button('选择目录')
          .margin({ left: 16, right: 16, top: 4 })
          .width('90%')
          .onClick(() => {
            this.pickDownloadDirectory();
          })

        Text('下载文件类型')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ left: 16, right: 16, top: 20, bottom: 8 })
          .width('100%')

        Row() {
          Select([{ value: DOWNLOAD_TYPE_MP3 }, { value: DOWNLOAD_TYPE_FLAC }])
            .selected(this.downloadType === DOWNLOAD_TYPE_FLAC ? 1 : 0)
            .value(this.downloadType)
            .font({ size: 16 })
            .width(160)
            .onSelect((index: number, value: string) => {
              const type = value === DOWNLOAD_TYPE_FLAC ? DOWNLOAD_TYPE_FLAC : DOWNLOAD_TYPE_MP3;
              this.selectDownloadType(type);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Text('默认下载 mp3；若所选类型无可用音源，将自动下载另一种可用类型。')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ left: 16, right: 16, top: 8 })
          .width('100%')

        Text('夸克网盘登录（大文件下载需要）')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ left: 16, right: 16, top: 20, bottom: 8 })
          .width('100%')

        Text(this.quarkCookie ? '已登录夸克网盘，可下载超过 50MB 的大文件' : '未登录夸克网盘，超过 50MB 的大文件需先登录')
          .fontSize(13)
          .fontColor(this.quarkCookie ? '#2E7D32' : '#888888')
          .margin({ left: 16, right: 16, bottom: 12 })
          .width('100%')

        Button('登录夸克网盘')
          .margin({ left: 16, right: 16, top: 4 })
          .width('90%')
          .onClick(() => {
            this.openQuarkAuth();
          })

        Text('说明：在搜索页输入歌曲名搜索，点击列表中的条目即可进入详情，选择下载或试听。超过 50MB 的大文件需先登录夸克网盘。默认路径为应用沙箱下载目录。')
          .fontSize(13)
          .fontColor('#888888')
          .margin({ left: 16, right: 16, top: 20 })
          .width('100%')

        Text('数据来源：https://www.gequhai.com/')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ left: 16, right: 16, top: 12 })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      TabContent() {
        this.SearchTab()
      }
      .tabBar('搜索')

      TabContent() {
        this.DownloadTab()
      }
      .tabBar('下载')

      TabContent() {
        this.MyTab()
      }
      .tabBar('我的')
    }
    .onChange((index: number) => {
      this.currentIndex = index;
    })
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
  }
}
