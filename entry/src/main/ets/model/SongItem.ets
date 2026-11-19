export interface SongItem {
  id: string;
  title: string;
  singer: string;
  playUrl: string;
}

/** 歌曲详情页数据：封面、预览地址、带时间轴的歌词。 */
export interface SongDetail {
  id: string;
  title: string;
  singer: string;
  playUrl: string;
  coverUrl: string;
  previewUrl: string;
  lrc: string;
  previewHeaders: Record<string, string>;
}

export interface DownloadInfo {
  url: string;
  isQuarkShare: boolean;
  quarkShareUrl: string;
  fileNameHint?: string;
  errorHint?: string;
  downloadHeaders?: Record<string, string>;
}
