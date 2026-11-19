import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { pickQuarkShareUrl } from '../../../main/ets/model/GequhaiApi';
import { PreferencesUtil, DOWNLOAD_TYPE_MP3, DOWNLOAD_TYPE_FLAC } from '../../../main/ets/utils/PreferencesUtil';

const MP3_SHARE: string = 'https://pan.quark.cn/s/mp3share';
const FLAC_SHARE: string = 'https://pan.quark.cn/s/flacshare';

export default function downloadTypeTest() {
  describe('DownloadTypeTest', () => {
    it('select_mp3_should_prefer_mp3', 0, () => {
      expect(pickQuarkShareUrl(MP3_SHARE, FLAC_SHARE, DOWNLOAD_TYPE_MP3)).assertEqual(MP3_SHARE);
    });

    it('select_flac_should_prefer_flac', 0, () => {
      expect(pickQuarkShareUrl(MP3_SHARE, FLAC_SHARE, DOWNLOAD_TYPE_FLAC)).assertEqual(FLAC_SHARE);
    });

    it('missing_requested_flac_should_fallback_to_mp3', 0, () => {
      expect(pickQuarkShareUrl(MP3_SHARE, '', DOWNLOAD_TYPE_FLAC)).assertEqual(MP3_SHARE);
    });

    it('missing_requested_mp3_should_fallback_to_flac', 0, () => {
      expect(pickQuarkShareUrl('', FLAC_SHARE, DOWNLOAD_TYPE_MP3)).assertEqual(FLAC_SHARE);
    });

    it('both_missing_should_return_empty', 0, () => {
      expect(pickQuarkShareUrl('', '', DOWNLOAD_TYPE_MP3)).assertEqual('');
      expect(pickQuarkShareUrl('', '', DOWNLOAD_TYPE_FLAC)).assertEqual('');
    });

    it('download_type_setting_should_persist', 0, async (done: Function) => {
      try {
        const ctx = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
        await PreferencesUtil.init(ctx);
        await PreferencesUtil.setDownloadType(DOWNLOAD_TYPE_FLAC);
        expect(await PreferencesUtil.getDownloadType()).assertEqual(DOWNLOAD_TYPE_FLAC);
        await PreferencesUtil.setDownloadType(DOWNLOAD_TYPE_MP3);
        expect(await PreferencesUtil.getDownloadType()).assertEqual(DOWNLOAD_TYPE_MP3);
        done();
      } catch (e) {
        expect().assertFail();
        done();
      }
    });
  });
}
