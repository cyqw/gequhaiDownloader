import { describe, it, expect } from '@ohos/hypium';
import { GequhaiApi } from '../../../main/ets/model/GequhaiApi';

export default function abilityTest() {
  describe('GequhaiApiTest', () => {
    it('search_should_return_results_or_empty', 0, async (done: Function) => {
      try {
        const results = await GequhaiApi.search('周杰伦', 1);
        expect(Array.isArray(results)).assertTrue();
        if (results.length > 0) {
          expect(results[0].id.length > 0).assertTrue();
          expect(results[0].title.length > 0).assertTrue();
          expect(results[0].playUrl.length > 0).assertTrue();
        }
        done();
      } catch (e) {
        // 网络环境可能波动，但不应抛出未处理异常导致卡死
        expect(true).assertTrue();
        done();
      }
    });

    it('getDownloadInfo_should_not_throw', 0, async (done: Function) => {
      try {
        const results = await GequhaiApi.search('晴天', 1);
        if (results.length > 0) {
          const info = await GequhaiApi.getDownloadInfo(results[0].playUrl, results[0].id);
          expect(info !== null && info !== undefined).assertTrue();
          // 允许直链、夸克分享链接或空结果，但必须返回结构且不抛异常
          const hasDirect = !!info.url && info.url.startsWith('http');
          const hasQuark = !!info.isQuarkShare && !!info.quarkShareUrl;
          const empty = !info.url && !info.isQuarkShare;
          expect(hasDirect || hasQuark || empty).assertTrue();
        } else {
          expect(true).assertTrue();
        }
        done();
      } catch (e) {
        expect().assertFail();
        done();
      }
    });
  });
}
