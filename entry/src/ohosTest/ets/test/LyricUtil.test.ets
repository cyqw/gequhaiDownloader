import { describe, it, expect } from '@ohos/hypium';
import {
  LyricLine, LYRIC_LINE_HEIGHT, parseLrc, lyricIndexAtTime, lyricScrollOffset, formatTime
} from '../../../main/ets/utils/LyricUtil';

export default function lyricUtilTest() {
  describe('LyricUtilTest', () => {
    it('parse_lrc_basic', 0, () => {
      const lines = parseLrc('[00:12.50]第一行\n[01:05.00]第二行');
      expect(lines.length).assertEqual(2);
      expect(lines[0].timeMs).assertEqual(12500);
      expect(lines[0].text).assertEqual('第一行');
      expect(lines[1].timeMs).assertEqual(65000);
    });

    it('parse_lrc_multiple_timestamps', 0, () => {
      const lines = parseLrc('[00:01.00][00:03.00]重复歌词');
      expect(lines.length).assertEqual(2);
      expect(lines[0].timeMs).assertEqual(1000);
      expect(lines[1].timeMs).assertEqual(3000);
      expect(lines[1].text).assertEqual('重复歌词');
    });

    it('parse_lrc_sorted_and_empty_filtered', 0, () => {
      const lines = parseLrc('[01:00.00]晚\n[00:10.00]早\n[00:20.00]');
      expect(lines.length).assertEqual(2);
      expect(lines[0].text).assertEqual('早');
      expect(lines[1].text).assertEqual('晚');
    });

    it('parse_lrc_empty_input', 0, () => {
      expect(parseLrc('').length).assertEqual(0);
    });

    it('lyric_index_at_time', 0, () => {
      const lines: LyricLine[] = parseLrc('[00:00.00]A\n[00:05.00]B\n[00:10.00]C');
      expect(lyricIndexAtTime(0, lines)).assertEqual(0);
      expect(lyricIndexAtTime(4999, lines)).assertEqual(0);
      expect(lyricIndexAtTime(5000, lines)).assertEqual(1);
      expect(lyricIndexAtTime(9999, lines)).assertEqual(1);
      expect(lyricIndexAtTime(60000, lines)).assertEqual(2);
    });

    it('empty_lyrics_index_is_minus_one', 0, () => {
      expect(lyricIndexAtTime(1000, [])).assertEqual(-1);
    });

    it('scroll_offset_first_line_at_top', 0, () => {
      // 20 行，每行 44，视口 240；第 0 行 -> 偏移 0（第一行贴顶）
      expect(lyricScrollOffset(0, 20, LYRIC_LINE_HEIGHT, 240)).assertEqual(0);
    });

    it('scroll_offset_last_line_at_bottom', 0, () => {
      const h = LYRIC_LINE_HEIGHT;
      const view = 240;
      const maxOffset = 20 * h - view;
      expect(lyricScrollOffset(19, 20, h, view)).assertEqual(maxOffset);
    });

    it('scroll_offset_middle_centered', 0, () => {
      const h = LYRIC_LINE_HEIGHT;
      const view = 240;
      const expected = 10 * h - (view - h) / 2;
      expect(lyricScrollOffset(10, 20, h, view)).assertEqual(expected);
    });

    it('scroll_offset_content_shorter_than_viewport', 0, () => {
      // 内容不足一屏时始终为 0
      expect(lyricScrollOffset(2, 3, h(), 240)).assertEqual(0);
    });

    it('format_time', 0, () => {
      expect(formatTime(0)).assertEqual('00:00');
      expect(formatTime(65000)).assertEqual('01:05');
      expect(formatTime(-100)).assertEqual('00:00');
    });
  });
}

function h(): number {
  return LYRIC_LINE_HEIGHT;
}
