import { media } from '@kit.MediaKit';
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SongItem, SongDetail } from '../model/SongItem';
import { GequhaiApi } from '../model/GequhaiApi';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import {
  LyricLine, LYRIC_LINE_HEIGHT, parseLrc, lyricIndexAtTime, lyricScrollOffset, formatTime
} from '../utils/LyricUtil';
import { requestDownload } from '../utils/DownloadFlow';
import { PlaybackManager } from '../utils/PlaybackManager';

@Entry
@Component
struct SongDetailPage {
  @State song: SongItem = { id: '', title: '', singer: '', playUrl: '' };
  @State coverUrl: string = '';
  @State previewUrl: string = '';
  @State lrc: string = '';
  private previewHeaders: Record<string, string> = {};
  @State loading: boolean = true;
  @State isPlaying: boolean = false;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;
  @State currentLine: number = 0;
  @State lyricViewportHeight: number = 240;
  @State lyricLines: LyricLine[] = [];

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private player: media.AVPlayer | null = null;
  private downloading: boolean = false;
  private downloadPath: string = '';
  private quarkCookie: string = '';
  private downloadType: string = 'mp3';
  private lyricScroller: Scroller = new Scroller();
  private seeking: boolean = false;
  private wantPlay: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['song']) {
      this.song = JSON.parse(params['song'] as string) as SongItem;
    }
    this.loadSettings();
    this.loadDetail();
    this.initPlayer();
  }

  aboutToDisappear(): void {
    if (this.player) {
      this.player.release().catch((e: Error) => {
        console.warn('release player failed: ' + e.message);
      });
      this.player = null;
    }
  }

  async loadSettings(): Promise<void> {
    try {
      await PreferencesUtil.init(this.context);
      const defaultPath = `${this.context.filesDir}/downloads`;
      this.downloadPath = await PreferencesUtil.getDownloadPath(defaultPath);
      this.quarkCookie = await PreferencesUtil.getQuarkCookie();
      this.downloadType = await PreferencesUtil.getDownloadType();
    } catch (e) {
      console.warn('load settings failed: ' + JSON.stringify(e));
    }
  }

  async loadDetail(): Promise<void> {
    this.loading = true;
    try {
      const detail: SongDetail = await GequhaiApi.getSongDetail(this.song, this.quarkCookie, this.downloadType);
      this.coverUrl = detail.coverUrl;
      this.previewUrl = detail.previewUrl;
      this.previewHeaders = detail.previewHeaders;
      this.lrc = detail.lrc;
      this.lyricLines = parseLrc(this.lrc);
    } catch (e) {
      console.warn('load detail failed: ' + JSON.stringify(e));
    } finally {
      this.loading = false;
    }
  }

  initPlayer(): void {
    media.createAVPlayer().then((player: media.AVPlayer) => {
      this.player = player;
      player.on('stateChange', (state: media.AVPlayerState) => {
        this.isPlaying = state === 'playing';
        if (state === 'initialized') {
          player.prepare().catch((e: Error) => {
            console.error('prepare failed: ' + e.message);
            promptAction.showToast({ message: '试听加载失败' });
          });
          return;
        }
        if (state === 'prepared') {
          this.durationMs = player.duration;
          if (this.wantPlay) {
            player.play().catch((e: Error) => {
              console.error('play failed: ' + e.message);
              promptAction.showToast({ message: '播放失败' });
            });
          }
          return;
        }
        if (state === 'playing' || state === 'paused') {
          this.durationMs = player.duration;
          this.currentTimeMs = player.currentTime;
          this.updateLyric();
        }
        if (state === 'completed') {
          this.isPlaying = false;
          this.wantPlay = false;
          this.currentTimeMs = 0;
          this.currentLine = 0;
          this.scrollToCurrentLine();
        }
      });
      player.on('timeUpdate', (time: number) => {
        if (this.seeking) {
          return;
        }
        this.currentTimeMs = time;
        this.updateLyric();
      });
      player.on('durationUpdate', (duration: number) => {
        this.durationMs = duration;
      });
      player.on('error', (err: Error) => {
        console.error('player error: ' + JSON.stringify(err));
        promptAction.showToast({ message: '播放失败' });
        this.isPlaying = false;
      });
    }).catch((e: Error) => {
      console.error('create player failed: ' + e.message);
    });
  }

  updateLyric(): void {
    const lines = this.lyricLines;
    if (lines.length === 0) {
      return;
    }
    const idx = lyricIndexAtTime(this.currentTimeMs, lines);
    if (idx !== this.currentLine) {
      this.currentLine = idx;
      this.scrollToCurrentLine();
    }
  }

  scrollToCurrentLine(): void {
    const lines = this.lyricLines;
    if (lines.length === 0) {
      return;
    }
    const offset = lyricScrollOffset(this.currentLine, lines.length, LYRIC_LINE_HEIGHT, this.lyricViewportHeight);
    const options: ScrollOptions = {
      xOffset: 0,
      yOffset: offset,
      animation: { duration: 300, curve: Curve.Ease }
    };
    this.lyricScroller.scrollTo(options);
  }

  async togglePreview(): Promise<void> {
    const player = this.player;
    if (!player) {
      promptAction.showToast({ message: '播放器未就绪' });
      return;
    }
    if (this.isPlaying) {
      this.wantPlay = false;
      await player.pause();
      return;
    }
    if (!this.previewUrl) {
      promptAction.showToast({ message: '暂无可用试听地址' });
      return;
    }
    // 试听与下载列表的文件播放互斥：开始试听前先停止列表播放。
    PlaybackManager.getInstance().stop();
    this.wantPlay = true;
    const state = player.state;
    if (state === 'idle' || state === 'stopped') {
      // 夸克直链需要携带 User-Agent / Cookie 等请求头，直接用 url 会被拒绝(5411006)。
      // 通过 MediaSource 携带请求头，stateChange(initialized) 后驱动 prepare/prepared 再 play。
      const headers: Record<string, string> = this.previewHeaders;
      if (Object.keys(headers).length > 0) {
        const source = media.createMediaSourceWithUrl(this.previewUrl, headers);
        player.setMediaSource(source).catch((e: Error) => {
          this.wantPlay = false;
          console.error('setMediaSource failed: ' + e.message);
          promptAction.showToast({ message: '试听加载失败' });
        });
      } else {
        player.url = this.previewUrl;
      }
      return;
    }
    if (state === 'completed') {
      player.seek(0);
    }
    if (state === 'prepared' || state === 'paused' || state === 'completed' || state === 'playing') {
      await player.play().catch((e: Error) => {
        this.wantPlay = false;
        console.error('play failed: ' + e.message);
        promptAction.showToast({ message: '播放失败' });
      });
      return;
    }
    // error / released 等异常状态：重建播放器
    this.wantPlay = false;
    promptAction.showToast({ message: '播放器状态异常，请重试' });
  }

  onSeekChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.seeking = true;
      this.currentTimeMs = value;
      this.updateLyric();
      return;
    }
    this.seeking = false;
    this.currentTimeMs = value;
    if (this.player && this.durationMs > 0) {
      this.player.seek(Math.min(Math.max(value, 0), this.durationMs));
    }
    this.updateLyric();
  }

  async onDownload(): Promise<void> {
    if (this.downloading) {
      return;
    }
    this.downloading = true;
    await requestDownload(this.song, this.downloadPath);
    this.downloading = false;
  }

  @Builder
  LyricContent() {
    Column() {
      ForEach(this.lyricLines, (line: LyricLine, index: number) => {
        Text(line.text)
          .fontSize(index === this.currentLine ? 18 : 15)
          .fontWeight(index === this.currentLine ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(index === this.currentLine ? '#31C27C' : '#777777')
          .height(LYRIC_LINE_HEIGHT)
          .width('100%')
          .textAlign(TextAlign.Center)
          .animation({ duration: 200, curve: Curve.Ease })
      }, (line: LyricLine, index: number) => `${index}_${line.timeMs}`)
    }
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.startIcon'))
          .width(24)
          .height(24)
          .onClick(() => {
            router.back();
          })
        Text(this.song.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Scroll() {
        Column() {
          if (this.coverUrl.length > 0) {
            Image(this.coverUrl)
              .width(180)
              .height(180)
              .borderRadius(12)
              .objectFit(ImageFit.Cover)
              .alt($r('app.media.startIcon'))
          } else {
            Image($r('app.media.startIcon'))
              .width(180)
              .height(180)
              .borderRadius(12)
          }

          Text(this.song.title)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 16 })
            .width('100%')
            .textAlign(TextAlign.Center)
          Text(this.song.singer)
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 4, bottom: 16 })
            .width('100%')
            .textAlign(TextAlign.Center)

          if (this.loading) {
            LoadingProgress().width(32).height(32).margin({ top: 8 })
          }

          Row() {
            Button(this.isPlaying ? '暂停' : '预览')
              .layoutWeight(1)
              .height(44)
              .fontSize(16)
              .backgroundColor('#31C27C')
              .onClick(() => {
                this.togglePreview();
              })
            Button('下载')
              .layoutWeight(1)
              .height(44)
              .fontSize(16)
              .backgroundColor('#007DFF')
              .margin({ left: 12 })
              .onClick(() => {
                this.onDownload();
              })
          }
          .width('100%')
          .margin({ top: 4 })

          Column() {
            Slider({
              value: this.currentTimeMs,
              min: 0,
              max: this.durationMs > 0 ? this.durationMs : 1,
              style: SliderStyle.OutSet
            })
              .width('100%')
              .onChange((value: number, mode: SliderChangeMode) => {
                this.onSeekChange(value, mode);
              })
            Row() {
              Text(formatTime(this.currentTimeMs))
                .fontSize(12)
                .fontColor('#888888')
              Text(formatTime(this.durationMs))
                .fontSize(12)
                .fontColor('#888888')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%')
          .margin({ top: 8 })

          Scroll(this.lyricScroller) {
            this.LyricContent()
          }
          .width('100%')
          .height(240)
          .margin({ top: 12 })
          .scrollBar(BarState.Off)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const h = Number(newValue.height);
            if (h > 0) {
              this.lyricViewportHeight = h;
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
