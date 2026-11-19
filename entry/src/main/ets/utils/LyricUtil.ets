/**
 * LRC 歌词解析与进度计算的纯函数工具。
 * 不依赖任何 Kit，便于在 ohosTest 中直接单元测试。
 */

export interface LyricLine {
  /** 时间点（毫秒）。 */
  timeMs: number;
  /** 歌词文本。 */
  text: string;
}

/** 单行歌词高度（vp）。UI 与滚动计算共用，保持一致。 */
export const LYRIC_LINE_HEIGHT: number = 44;

/** 解析 LRC 文本为按时间排序的歌词行。支持 [mm:ss.xx] / [mm:ss] / 一行多个时间戳。 */
export function parseLrc(lrc: string): LyricLine[] {
  const lines: LyricLine[] = [];
  if (!lrc) {
    return lines;
  }
  const tagRegex = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  const rawLines = lrc.split(/\r?\n/);
  for (const raw of rawLines) {
    const text = raw.replace(tagRegex, '').trim();
    if (!text) {
      continue;
    }
    tagRegex.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = tagRegex.exec(raw)) !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      let ms = 0;
      if (m[3]) {
        const frac = m[3];
        ms = parseInt(frac, 10) * (frac.length === 1 ? 100 : frac.length === 2 ? 10 : 1);
      }
      const timeMs = min * 60 * 1000 + sec * 1000 + ms;
      lines.push({ timeMs: timeMs, text: text });
    }
  }
  lines.sort((a: LyricLine, b: LyricLine): number => a.timeMs - b.timeMs);
  return lines;
}

/** 返回 timeMs 所在歌词行的索引；在第一行之前返回 0。 */
export function lyricIndexAtTime(timeMs: number, lines: LyricLine[]): number {
  if (!lines || lines.length === 0) {
    return -1;
  }
  let lo = 0;
  let hi = lines.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >>> 1;
    if (lines[mid].timeMs <= timeMs) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return hi < 0 ? 0 : hi;
}

/**
 * 计算高亮行应滚动到的 y 偏移（vp）。
 * - 目标是把当前行居中；
 * - 当内容不足以铺满视口时返回 0；
 * - 靠近开头/结尾时钳制到边界，保证第一行贴顶、最后一行贴底。
 */
export function lyricScrollOffset(currentIndex: number, lineCount: number,
  lineHeight: number, viewportHeight: number): number {
  if (lineCount <= 0 || lineHeight <= 0) {
    return 0;
  }
  const contentHeight = lineCount * lineHeight;
  const maxOffset = Math.max(0, contentHeight - viewportHeight);
  const centerOffset = currentIndex * lineHeight - (viewportHeight - lineHeight) / 2;
  if (centerOffset <= 0) {
    return 0;
  }
  if (centerOffset >= maxOffset) {
    return maxOffset;
  }
  return centerOffset;
}

/** 把毫秒格式化为 mm:ss。 */
export function formatTime(ms: number): string {
  if (ms < 0) {
    ms = 0;
  }
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  const mm = min < 10 ? '0' + min : '' + min;
  const ss = sec < 10 ? '0' + sec : '' + sec;
  return `${mm}:${ss}`;
}
