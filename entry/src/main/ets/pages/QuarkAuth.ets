import { webview } from '@kit.ArkWeb';
import { router, promptAction } from '@kit.ArkUI';
import { PreferencesUtil } from '../utils/PreferencesUtil';

@Entry
@Component
struct QuarkAuth {
  controller: webview.WebviewController = new webview.WebviewController();
  @State currentUrl: string = 'https://pan.quark.cn/';
  @State cookiePreview: string = '';

  /** 桌面 UA：夸克网盘在移动 UA 下会跳转到“下载App”落地页，无法登录；桌面 UA 才显示登录入口。 */
  private static readonly DESKTOP_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  aboutToAppear(): void {
    webview.WebviewController.setWebDebuggingAccess(true);
  }

  async saveCookie(): Promise<void> {
    try {
      const cm = webview.WebCookieManager;
      // 合并夸克各域名的 Cookie：登录态可能分布在 pan / drive-pc / drive-h 等域。
      const urls = ['https://pan.quark.cn/', 'https://drive-pc.quark.cn/', 'https://drive-h.quark.cn/'];
      const parts: string[] = [];
      for (const url of urls) {
        try {
          const c = cm.fetchCookieSync(url);
          if (c && c.trim().length > 0) {
            parts.push(c.trim());
          }
        } catch (e) {
          // ignore
        }
      }
      let cookie = parts.join('; ');
      // 去重同名 Cookie 片段，避免 token 冲突。
      const seen = new Set<string>();
      const kept: string[] = [];
      for (const seg of cookie.split(';')) {
        const s = seg.trim();
        if (!s) {
          continue;
        }
        const name = s.split('=')[0];
        if (seen.has(name)) {
          continue;
        }
        seen.add(name);
        kept.push(s);
      }
      cookie = kept.join('; ');
      if (!cookie || cookie.trim().length === 0) {
        promptAction.showToast({ message: '未获取到Cookie，请先完成登录' });
        return;
      }
      await PreferencesUtil.setQuarkCookie(cookie);
      this.cookiePreview = cookie.length > 120 ? cookie.substring(0, 120) + '...' : cookie;
      promptAction.showToast({ message: '夸克Cookie获取并保存成功' });
    } catch (e) {
      console.error('save cookie error: ' + JSON.stringify(e));
      promptAction.showToast({ message: '获取Cookie失败' });
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .height(36)
          .onClick(() => {
            router.back();
          })
        Blank().layoutWeight(1)
        Button('获取并保存Cookie')
          .height(36)
          .onClick(() => {
            this.saveCookie();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      if (this.cookiePreview) {
        Text('已保存Cookie: ' + this.cookiePreview)
          .fontSize(12)
          .fontColor('#2E7D32')
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 6 })
      } else {
        Text('请在下方页面登录夸克网盘，登录完成后点击“获取并保存Cookie”。')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 6 })
      }

      Web({ src: this.currentUrl, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .databaseAccess(true)
        .layoutWeight(1)
        .width('100%')
        .onControllerAttached(() => {
          // 控制器附着后立即设置桌面 UA，页面加载时即为桌面版，显示登录入口。
          try {
            this.controller.setCustomUserAgent(QuarkAuth.DESKTOP_UA);
          } catch (e) {
            console.warn('set custom UA failed: ' + JSON.stringify(e));
          }
        })
        .onPageEnd((event) => {
          if (event && event.url) {
            this.currentUrl = event.url;
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
