import { promptAction } from '@kit.ArkUI';
import { SongItem } from '../model/SongItem';
import { DownloadManager } from './DownloadManager';
import { decideStart } from './NetworkUtil';

export type DownloadRequestResult = 'no-path' | 'duplicate' | 'waiting' | 'started';

/**
 * 统一的“开始下载”入口：检查路径、重复任务、移动网络提示，然后加入下载列表。
 * 搜索页与歌曲详情页共用，保证两处行为一致。
 */
export async function requestDownload(song: SongItem, downloadPath: string): Promise<DownloadRequestResult> {
  if (!downloadPath) {
    promptAction.showToast({ message: '请先在“我的”页面配置下载路径' });
    return 'no-path';
  }
  const manager = DownloadManager.getInstance();
  if (manager.hasAny(song.id)) {
    promptAction.showToast({ message: '该歌曲已在下载列表中' });
    return 'duplicate';
  }
  const decision = decideStart(manager.getNetworkKind(), false);
  let allowMobile = false;
  if (decision === 'prompt') {
    const res = await promptAction.showDialog({
      title: '移动网络提示',
      message: '当前正在使用移动网络。是否直接使用移动网络下载？选择“等待 WLAN”将在连接到 WLAN 后自动开始。',
      buttons: [
        { text: '直接下载', color: '#007DFF' },
        { text: '等待 WLAN', color: '#666666' }
      ]
    });
    allowMobile = res.index === 0;
  }
  await manager.enqueue(song, allowMobile);
  if (decision === 'prompt' && !allowMobile) {
    promptAction.showToast({ message: '已加入下载列表，等待 WLAN 连接后自动开始' });
    return 'waiting';
  }
  promptAction.showToast({ message: '已加入下载列表' });
  return 'started';
}
