/** 用户存储下常见目录对应的友好名称。 */
const USER_FOLDER_NAMES: Map<string, string> = new Map<string, string>([
  ['Download', '下载'],
  ['Downloads', '下载'],
  ['Documents', '文档'],
  ['Desktop', '桌面'],
  ['Pictures', '图片'],
  ['Music', '音乐'],
  ['Videos', '视频'],
  ['Movies', '视频'],
  ['DCIM', '相机'],
  ['Android', '应用数据']
]);

/** 文件管理中用户存储的根路径。 */
const USER_ROOT = '/storage/Users/currentUser';

/** 去掉 file:// 协议头与 authority，并做百分号解码。 */
function normalizePath(path: string): string {
  let raw = path.trim();
  if (raw.startsWith('file://')) {
    // 形如 file://<authority>/<path>，丢弃协议头与 authority，保留从首个 '/' 开始的部分
    raw = raw.substring('file://'.length);
    const slash = raw.indexOf('/');
    raw = slash >= 0 ? raw.substring(slash) : '/' + raw;
  }
  try {
    raw = decodeURIComponent(raw);
  } catch (e) {
    // 解码失败时保留原字符串
  }
  return raw;
}

/** 去掉结尾多余的斜杠（保留根斜杠）。 */
function trimTrailingSlash(path: string): string {
  let s = path;
  while (s.length > 1 && s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/** 把用户存储下的子路径首段替换为友好名称。 */
function friendlyUserSubPath(sub: string): string {
  const segs: string[] = sub.split('/');
  if (segs.length > 0) {
    const mapped = USER_FOLDER_NAMES.get(segs[0]);
    if (mapped !== undefined) {
      segs[0] = mapped;
    }
  }
  return segs.join('/');
}

/**
 * 把下载保存路径转换成更友好的展示文本，避免直接显示 file:// 开头的原始 URI。
 *
 * 例如：
 *  - file://docs/storage/Users/currentUser/Download          -> 内部存储/下载
 *  - file://docs/storage/Users/currentUser/Download/歌曲海     -> 内部存储/下载/歌曲海
 *  - /data/storage/el2/base/haps/entry/files/downloads        -> 应用内部存储/downloads
 *  - 未设置                                                    -> 未设置
 */
export function formatDownloadPath(path: string): string {
  if (!path || path.trim().length === 0) {
    return '未设置';
  }
  const p = trimTrailingSlash(normalizePath(path));

  // 应用沙箱路径
  if (p.startsWith('/data/storage/')) {
    const filesIdx = p.indexOf('/files');
    if (filesIdx >= 0) {
      const rest = p.substring(filesIdx + '/files'.length);
      return `应用内部存储${rest}`;
    }
    return '应用内部存储';
  }

  // 文件管理中的用户存储
  if (p === USER_ROOT) {
    return '内部存储';
  }
  if (p.startsWith(USER_ROOT + '/')) {
    return `内部存储/${friendlyUserSubPath(p.substring(USER_ROOT.length + 1))}`;
  }
  if (p.startsWith('/storage/')) {
    return `内部存储/${friendlyUserSubPath(p.substring('/storage/'.length))}`;
  }

  // 其它情况直接返回去掉协议后的路径
  return p;
}
