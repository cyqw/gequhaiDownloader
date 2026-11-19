import { describe, it, expect } from '@ohos/hypium';
import {
  networkKindFromBearerTypes,
  decideStart,
  networkTransitionAction,
  BEARER_CELLULAR,
  BEARER_WIFI,
  BEARER_ETHERNET,
  BEARER_VPN
} from '../../../main/ets/utils/NetworkUtil';

export default function networkUtilTest() {
  describe('NetworkUtilTest', () => {
    it('wifi_bearer_is_wlan', 0, () => {
      expect(networkKindFromBearerTypes([BEARER_WIFI])).assertEqual('wlan');
    });

    it('ethernet_bearer_is_wlan', 0, () => {
      expect(networkKindFromBearerTypes([BEARER_ETHERNET])).assertEqual('wlan');
    });

    it('cellular_bearer_is_mobile', 0, () => {
      expect(networkKindFromBearerTypes([BEARER_CELLULAR])).assertEqual('mobile');
    });

    it('wifi_wins_over_cellular', 0, () => {
      expect(networkKindFromBearerTypes([BEARER_CELLULAR, BEARER_WIFI])).assertEqual('wlan');
    });

    it('empty_bearer_is_none', 0, () => {
      expect(networkKindFromBearerTypes([])).assertEqual('none');
    });

    it('vpn_only_is_unknown', 0, () => {
      expect(networkKindFromBearerTypes([BEARER_VPN])).assertEqual('unknown');
    });

    it('mobile_without_permission_prompts', 0, () => {
      expect(decideStart('mobile', false)).assertEqual('prompt');
    });

    it('mobile_with_permission_starts', 0, () => {
      expect(decideStart('mobile', true)).assertEqual('start');
    });

    it('non_mobile_always_starts', 0, () => {
      expect(decideStart('wlan', false)).assertEqual('start');
      expect(decideStart('unknown', false)).assertEqual('start');
      expect(decideStart('none', false)).assertEqual('start');
    });

    it('wlan_to_mobile_pauses', 0, () => {
      expect(networkTransitionAction('wlan', 'mobile')).assertEqual('pause');
    });

    it('mobile_to_wlan_resumes', 0, () => {
      expect(networkTransitionAction('mobile', 'wlan')).assertEqual('resume');
    });

    it('same_network_does_nothing', 0, () => {
      expect(networkTransitionAction('wlan', 'wlan')).assertEqual('none');
      expect(networkTransitionAction('mobile', 'mobile')).assertEqual('none');
    });

    it('unrelated_transition_does_nothing', 0, () => {
      expect(networkTransitionAction('none', 'mobile')).assertEqual('none');
      expect(networkTransitionAction('unknown', 'wlan')).assertEqual('none');
    });
  });
}
