import { media } from '@kit.MediaKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { DownloadItem } from './DownloadManager';

/**
 * 下载列表条目的本地文件播放器（进程内单例）。
 * 同一时刻只播放一个文件：播放新文件时会停止并释放上一个。
 */
export class PlaybackManager {
  private static instance: PlaybackManager | null = null;

  private player: media.AVPlayer | null = null;
  private currentItem: DownloadItem | null = null;
  private openedFile: fs.File | null = null;
  private listener: ((key: string) => void) | null = null;
  /** 切后台时正在播放的条目与位置，用于回到前台自动续播。 */
  private resumeItem: DownloadItem | null = null;
  private resumePosition: number = 0;

  static getInstance(): PlaybackManager {
    if (PlaybackManager.instance === null) {
      PlaybackManager.instance = new PlaybackManager();
    }
    return PlaybackManager.instance;
  }

  isPlaying(item: DownloadItem): boolean {
    return this.currentItem !== null && this.currentItem.key === item.key;
  }

  setListener(listener: (key: string) => void): void {
    this.listener = listener;
  }

  private notifyListener(): void {
    const key = this.currentItem !== null ? this.currentItem.key : '';
    if (this.listener) {
      this.listener(key);
    }
  }

  /** 切换播放：同一文件再次点击则停止；新文件停止上一个后播放。 */
  async toggle(item: DownloadItem): Promise<void> {
    if (this.currentItem !== null && this.currentItem.key === item.key) {
      this.stop();
      return;
    }
    await this.play(item);
  }

  /**
   * 应用切到后台时调用：记录当前播放位置并暂停，
   * 回到前台后由 onForeground 自动从该位置续播。
   */
  onBackground(): void {
    const player = this.player;
    if (this.currentItem !== null && player !== null) {
      this.resumeItem = this.currentItem;
      try {
        this.resumePosition = player.state === 'idle' || player.state === 'released' ? 0 : player.currentTime;
      } catch (e) {
        this.resumePosition = 0;
      }
      try {
        if (player.state === 'playing') {
          player.pause();
        }
      } catch (e) {
        console.warn('pause on background failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      }
    }
  }

  /** 应用回到前台时调用：若切后台前有正在播放的条目，则自动续播。 */
  async onForeground(): Promise<void> {
    const target = this.resumeItem;
    const position = this.resumePosition;
    this.resumeItem = null;
    this.resumePosition = 0;
    if (target !== null && target.filePath) {
      await this.play(target, position);
    }
  }

  /** 停止当前播放并释放资源。 */
  stop(): void {
    if (this.currentItem !== null) {
      this.currentItem.isPlaying = false;
      this.currentItem = null;
      this.notifyListener();
    }
    const player = this.player;
    this.player = null;
    if (player) {
      try {
        if (player.state !== 'released') {
          player.release();
        }
      } catch (e) {
        console.warn('release player failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      }
    }
    this.closeFile();
  }

  private closeFile(): void {
    if (this.openedFile) {
      try {
        fs.closeSync(this.openedFile);
      } catch (e) {
        console.warn('close file failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      }
      this.openedFile = null;
    }
  }

  /** 解析文件路径：沙箱路径或 file:// URI 都转换为真实路径。 */
  private resolvePath(filePath: string): string {
    if (!filePath) {
      return '';
    }
    if (filePath.startsWith('file://')) {
      try {
        return new fileUri.FileUri(filePath).path;
      } catch (e) {
        console.warn('resolve file uri failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
        return '';
      }
    }
    return filePath;
  }

  private async play(item: DownloadItem, startPositionMs: number = 0): Promise<void> {
    const path = this.resolvePath(item.filePath);
    if (!path) {
      promptAction.showToast({ message: '文件不存在或路径无效' });
      return;
    }
    // 先停止上一个文件。
    this.stop();

    let file: fs.File;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    } catch (e) {
      console.error('open file failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      promptAction.showToast({ message: '无法打开文件' });
      return;
    }
    this.openedFile = file;
    let statSize: number = 0;
    try {
      statSize = fs.statSync(file.fd).size;
    } catch (e) {
      console.warn('stat file failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
    if (statSize <= 0) {
      this.closeFile();
      promptAction.showToast({ message: '文件为空' });
      return;
    }

    try {
      const player = await media.createAVPlayer();
      this.player = player;
      player.on('stateChange', (state: media.AVPlayerState) => {
        if (state === 'initialized') {
          player.prepare().catch((e: Error) => {
            console.warn('prepare failed: ' + e.message);
          });
        } else if (state === 'prepared') {
          if (startPositionMs > 0) {
            try {
              player.seek(Math.min(startPositionMs, Math.max(0, player.duration - 100)));
            } catch (e) {
              console.warn('seek on resume failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
            }
          }
          player.play().catch((e: Error) => {
            console.warn('play failed: ' + e.message);
          });
        } else if (state === 'completed') {
          this.stop();
        } else if (state === 'error') {
          promptAction.showToast({ message: '播放失败' });
          this.stop();
        }
      });
      player.on('error', (err: Error) => {
        console.error('playback error: ' + JSON.stringify(err));
      });
      const descriptor: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: statSize };
      player.fdSrc = descriptor;
      this.currentItem = item;
      item.isPlaying = true;
      this.notifyListener();
    } catch (e) {
      console.error('create player failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
      promptAction.showToast({ message: '播放器创建失败' });
      this.stop();
    }
  }
}
