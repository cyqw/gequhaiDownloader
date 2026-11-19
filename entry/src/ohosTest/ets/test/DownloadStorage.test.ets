import { describe, it, expect } from '@ohos/hypium';
import { DownloadItem, DownloadState } from '../../../main/ets/utils/DownloadManager';
import {
  serializeItems, deserializeItems, itemToData, dataToItem
} from '../../../main/ets/utils/DownloadStorage';

export default function downloadStorageTest() {
  describe('DownloadStorageTest', () => {
    it('serialize_then_deserialize_keeps_fields', 0, () => {
      const item = new DownloadItem('k1', 's1', '晴天', '周杰伦', 'https://x/play/1');
      item.state = DownloadState.COMPLETED;
      item.fileName = '晴天-周杰伦.mp3';
      item.receivedSize = 1000;
      item.totalSize = 1000;
      item.errorMsg = '';
      item.allowMobile = true;
      item.pausedByNetwork = false;
      item.filePath = 'file://docs/x/晴天-周杰伦.mp3';
      item.createdAt = 1700000000000;

      const json = serializeItems([item]);
      const restored = deserializeItems(json);
      expect(restored.length).assertEqual(1);
      expect(restored[0].key).assertEqual('k1');
      expect(restored[0].songId).assertEqual('s1');
      expect(restored[0].title).assertEqual('晴天');
      expect(restored[0].fileName).assertEqual('晴天-周杰伦.mp3');
      expect(restored[0].state).assertEqual(DownloadState.COMPLETED);
      expect(restored[0].receivedSize).assertEqual(1000);
      expect(restored[0].filePath).assertEqual('file://docs/x/晴天-周杰伦.mp3');
      expect(restored[0].createdAt).assertEqual(1700000000000);
    });

    it('item_to_data_roundtrip', 0, () => {
      const item = new DownloadItem('k2', 's2', 't', 'a', 'u');
      item.state = DownloadState.PAUSED;
      item.pausedByNetwork = true;
      const data = itemToData(item);
      const back = dataToItem(data);
      expect(back.key).assertEqual('k2');
      expect(back.state).assertEqual(DownloadState.PAUSED);
      expect(back.pausedByNetwork).assertTrue();
    });

    it('interrupted_states_become_failed_with_hint', 0, () => {
      const downloading = new DownloadItem('k3', 's3', 't', 'a', 'u');
      downloading.state = DownloadState.DOWNLOADING;
      const resolving = new DownloadItem('k4', 's4', 't', 'a', 'u');
      resolving.state = DownloadState.RESOLVING;
      const confirming = new DownloadItem('k5', 's5', 't', 'a', 'u');
      confirming.state = DownloadState.CONFIRMING;

      const json = serializeItems([downloading, resolving, confirming]);
      const restored = deserializeItems(json);
      expect(restored.length).assertEqual(3);
      expect(restored[0].state).assertEqual(DownloadState.FAILED);
      expect(restored[0].errorMsg).assertEqual('应用重启导致下载中断，请点击下载重试');
      expect(restored[1].state).assertEqual(DownloadState.FAILED);
      expect(restored[2].state).assertEqual(DownloadState.FAILED);
    });

    it('terminal_states_preserved', 0, () => {
      const completed = new DownloadItem('k6', 's6', 't', 'a', 'u');
      completed.state = DownloadState.COMPLETED;
      const failed = new DownloadItem('k7', 's7', 't', 'a', 'u');
      failed.state = DownloadState.FAILED;
      failed.errorMsg = 'x';
      const waiting = new DownloadItem('k8', 's8', 't', 'a', 'u');
      waiting.state = DownloadState.WAITING;

      const restored = deserializeItems(serializeItems([completed, failed, waiting]));
      expect(restored[0].state).assertEqual(DownloadState.COMPLETED);
      expect(restored[1].state).assertEqual(DownloadState.FAILED);
      expect(restored[1].errorMsg).assertEqual('x');
      expect(restored[2].state).assertEqual(DownloadState.WAITING);
    });

    it('empty_and_invalid_json', 0, () => {
      expect(deserializeItems('').length).assertEqual(0);
      expect(deserializeItems('not json').length).assertEqual(0);
      expect(deserializeItems('[]').length).assertEqual(0);
    });

    it('isPlaying_not_persisted', 0, () => {
      const item = new DownloadItem('k9', 's9', 't', 'a', 'u');
      item.state = DownloadState.COMPLETED;
      item.isPlaying = true;
      const restored = deserializeItems(serializeItems([item]));
      expect(restored[0].isPlaying).assertFalse();
    });
  });
}
