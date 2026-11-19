import { DownloadItem, DownloadState } from './DownloadManager';

/** 可序列化的下载条目数据（不含运行时的播放器状态）。 */
export interface DownloadItemData {
  key: string;
  songId: string;
  title: string;
  singer: string;
  playUrl: string;
  state: string;
  fileName: string;
  receivedSize: number;
  totalSize: number;
  errorMsg: string;
  allowMobile: boolean;
  pausedByNetwork: boolean;
  filePath: string;
  createdAt: number;
}

/** 重启后无法继续的中间状态，统一标记为失败并给出提示。 */
function restoredState(state: string): DownloadState {
  switch (state) {
    case DownloadState.COMPLETED:
      return DownloadState.COMPLETED;
    case DownloadState.FAILED:
      return DownloadState.FAILED;
    case DownloadState.PAUSED:
      return DownloadState.PAUSED;
    case DownloadState.WAITING:
      return DownloadState.WAITING;
    default:
      // RESOLVING / CONFIRMING / DOWNLOADING 的系统下载任务在重启后已丢失
      return DownloadState.FAILED;
  }
}

export function itemToData(item: DownloadItem): DownloadItemData {
  const data: DownloadItemData = {
    key: item.key,
    songId: item.songId,
    title: item.title,
    singer: item.singer,
    playUrl: item.playUrl,
    state: item.state,
    fileName: item.fileName,
    receivedSize: item.receivedSize,
    totalSize: item.totalSize,
    errorMsg: item.errorMsg,
    allowMobile: item.allowMobile,
    pausedByNetwork: item.pausedByNetwork,
    filePath: item.filePath,
    createdAt: item.createdAt
  };
  return data;
}

export function dataToItem(data: DownloadItemData): DownloadItem {
  const item = new DownloadItem(data.key, data.songId, data.title, data.singer, data.playUrl);
  item.state = restoredState(data.state);
  if (item.state === DownloadState.FAILED &&
    (data.state === DownloadState.RESOLVING || data.state === DownloadState.CONFIRMING ||
      data.state === DownloadState.DOWNLOADING)) {
    item.errorMsg = '应用重启导致下载中断，请点击下载重试';
  } else {
    item.errorMsg = data.errorMsg;
  }
  item.fileName = data.fileName;
  item.receivedSize = data.receivedSize;
  item.totalSize = data.totalSize;
  item.allowMobile = data.allowMobile;
  item.pausedByNetwork = data.pausedByNetwork;
  item.filePath = data.filePath;
  item.createdAt = data.createdAt || 0;
  return item;
}

export function serializeItems(items: DownloadItem[]): string {
  const arr: DownloadItemData[] = [];
  for (let i = 0; i < items.length; i++) {
    arr.push(itemToData(items[i]));
  }
  return JSON.stringify(arr);
}

export function deserializeItems(json: string): DownloadItem[] {
  const items: DownloadItem[] = [];
  if (!json) {
    return items;
  }
  try {
    const arr = JSON.parse(json) as DownloadItemData[];
    if (!arr || !Array.isArray(arr)) {
      return items;
    }
    for (let i = 0; i < arr.length; i++) {
      const d = arr[i];
      if (d && d.key && d.songId) {
        items.push(dataToItem(d));
      }
    }
  } catch (e) {
    console.warn('deserialize download items failed: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
  }
  return items;
}
