import { describe, it, expect } from '@ohos/hypium';
import { DownloadManager, DownloadItem, DownloadState } from '../../../main/ets/utils/DownloadManager';

/** 通过函数读取状态，避免 ArkTS 对属性做赋值后的类型收窄。 */
function currentState(item: DownloadItem): DownloadState {
  return item.state;
}

/** 清空单例中残留的（持久化恢复的）任务，保证每个测试独立。 */
function clearItems(mgr: DownloadManager): void {
  mgr.getItems().splice(0, mgr.getItems().length);
}

export default function downloadManagerTest() {
  describe('DownloadManagerTest', () => {
    it('wlan_to_mobile_pauses_active_item', 0, () => {
      const mgr = DownloadManager.getInstance();
      clearItems(mgr);
      const item = new DownloadItem('t_pause', 's1', 'title', 'singer', 'https://example.com/play/1');
      item.state = DownloadState.DOWNLOADING;
      item.allowMobile = false;
      mgr.getItems().push(item);

      mgr.evaluateNetwork('wlan');
      mgr.evaluateNetwork('mobile');

      expect(item.state).assertEqual(DownloadState.PAUSED);
      expect(item.pausedByNetwork).assertTrue();
      mgr.removeItem(item);
    });

    it('wlan_to_mobile_keeps_item_when_mobile_allowed', 0, () => {
      const mgr = DownloadManager.getInstance();
      clearItems(mgr);
      const item = new DownloadItem('t_allow', 's2', 'title', 'singer', 'https://example.com/play/2');
      item.state = DownloadState.DOWNLOADING;
      item.allowMobile = true;
      mgr.getItems().push(item);

      mgr.evaluateNetwork('wlan');
      mgr.evaluateNetwork('mobile');

      expect(item.state).assertEqual(DownloadState.DOWNLOADING);
      expect(item.pausedByNetwork).assertFalse();
      mgr.removeItem(item);
    });

    it('mobile_to_wlan_resumes_paused_item', 0, () => {
      const mgr = DownloadManager.getInstance();
      clearItems(mgr);
      const item = new DownloadItem('t_resume', 's3', 'title', 'singer', 'https://example.com/play/3');
      item.state = DownloadState.DOWNLOADING;
      item.allowMobile = false;
      mgr.getItems().push(item);

      mgr.evaluateNetwork('wlan');
      mgr.evaluateNetwork('mobile');
      expect(item.state).assertEqual(DownloadState.PAUSED);

      mgr.evaluateNetwork('wlan');
      expect(item.pausedByNetwork).assertFalse();
      expect(currentState(item) === DownloadState.PAUSED).assertFalse();
      mgr.removeItem(item);
    });

    it('remove_item_deletes_from_list', 0, () => {
      const mgr = DownloadManager.getInstance();
      clearItems(mgr);
      const item = new DownloadItem('t_remove', 's4', 'title', 'singer', 'https://example.com/play/4');
      mgr.getItems().push(item);
      expect(mgr.getItems().length).assertEqual(1);
      mgr.removeItem(item);
      expect(mgr.getItems().length).assertEqual(0);
    });

    it('remove_item_by_key_when_reference_differs', 0, () => {
      const mgr = DownloadManager.getInstance();
      clearItems(mgr);
      const stored = new DownloadItem('t_proxy', 's5', 'title', 'singer', 'https://example.com/play/5');
      mgr.getItems().push(stored);
      // 模拟 @ObjectLink 传给子组件的 @Observed 代理：引用不同但 key 相同
      const proxyLike = new DownloadItem('t_proxy', 's5', 'title', 'singer', 'https://example.com/play/5');
      mgr.removeItem(proxyLike);
      expect(mgr.getItems().length).assertEqual(0);
    });
  });
}
