import { describe, it, expect } from '@ohos/hypium';
import { request } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common, Want } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { QuarkParser } from '../../../main/ets/utils/QuarkParser';
import { TestContext } from './TestContext';

// 公开分享链接（游客可解析），用于验证夸克分享直链解析流程
const PUBLIC_SHARE: string = 'https://pan.quark.cn/s/f8db5fca42cf';

function sandboxDir(): string {
  const ctx = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  return ctx.filesDir + '/test_downloads';
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

/** request.downloadFile 需要一个 BaseContext；测试运行器环境下取当前顶层 Ability 的上下文。 */
async function resolveAbilityContext(): Promise<common.UIAbilityContext | null> {
  if (TestContext.abilityContext !== null) {
    return TestContext.abilityContext;
  }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  try {
    const top = await delegator.getCurrentTopAbility();
    if (top && top.context) {
      return top.context as common.UIAbilityContext;
    }
  } catch (e) {
    // ignore
  }
  const want: Want = {
    bundleName: 'com.cy.gequhai.downloader',
    abilityName: 'EntryAbility'
  };
  await delegator.startAbility(want);
  for (let i = 0; i < 5; i++) {
    await sleep(1000);
    const top = await delegator.getCurrentTopAbility();
    if (top && top.context) {
      return top.context as common.UIAbilityContext;
    }
  }
  return null;
}

export default function quarkParserTest() {
  describe('QuarkParserTest', () => {
    it('resolve_public_share_should_return_direct_url', 0, async (done: Function) => {
      try {
        const res = await QuarkParser.resolveShare(PUBLIC_SHARE, '');
        expect(res.downloadUrl.length > 0).assertTrue();
        expect(res.downloadUrl.startsWith('http')).assertTrue();
        expect(res.fileName.length > 0).assertTrue();
        // 游客下载直链必须带上下载校验 Cookie（__pugs），否则会返回 412
        expect(res.cookie.length > 0).assertTrue();
        done();
      } catch (e) {
        const msg = e instanceof Error ? e.message : JSON.stringify(e);
        console.error('resolve public share failed: ' + msg);
        expect().assertFail();
        done();
      }
    });

    it('resolved_url_should_be_downloadable', 0, async (done: Function) => {
      const dir = sandboxDir();
      const filePath = dir + '/quark_test.flac';
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, true);
        }
      } catch (e) {
        // ignore
      }
      try {
        if (fs.accessSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      } catch (e) {
        // ignore
      }
      try {
        const res = await QuarkParser.resolveShare(PUBLIC_SHARE, '');
        const headers: Record<string, string> = {
          'User-Agent': res.userAgent,
          'Referer': 'https://pan.quark.cn/'
        };
        if (res.cookie && res.cookie.length > 0) {
          headers['Cookie'] = res.cookie;
        }

        const ctx = await resolveAbilityContext();
        expect(ctx !== null).assertTrue();
        const abilityContext = ctx as common.UIAbilityContext;

        const task = await request.downloadFile(abilityContext, {
          url: res.downloadUrl,
          filePath: filePath,
          header: headers,
          enableMetered: true,
          enableRoaming: true
        });
        await new Promise<void>((resolve, reject) => {
          task.on('complete', () => {
            resolve();
          });
          task.on('fail', (err: number) => {
            reject(new Error('download failed code=' + err));
          });
        });
        const stat = fs.statSync(filePath);
        console.info('downloaded size=' + stat.size + ', expected=' + res.size);
        expect(stat.size > 1000).assertTrue();
        done();
      } catch (e) {
        const msg = e instanceof Error ? e.message : JSON.stringify(e);
        console.error('download resolved url failed: ' + msg);
        expect().assertFail();
        done();
      }
    });

    it('invalid_share_should_throw', 0, async (done: Function) => {
      try {
        await QuarkParser.resolveShare('https://pan.quark.cn/s/', '');
        expect().assertFail();
        done();
      } catch (e) {
        expect(true).assertTrue();
        done();
      }
    });
  });
}
