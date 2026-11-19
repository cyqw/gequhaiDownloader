import { describe, it, expect } from '@ohos/hypium';
import { formatDownloadPath } from '../../../main/ets/utils/PathUtil';

export default function pathUtilTest() {
  describe('PathUtilTest', () => {
    it('file_uri_download_folder', 0, () => {
      expect(formatDownloadPath('file://docs/storage/Users/currentUser/Download'))
        .assertEqual('内部存储/下载');
    });

    it('file_uri_with_sub_folder', 0, () => {
      expect(formatDownloadPath('file://docs/storage/Users/currentUser/Download/歌曲海'))
        .assertEqual('内部存储/下载/歌曲海');
    });

    it('file_uri_with_encoded_chinese', 0, () => {
      expect(formatDownloadPath('file://docs/storage/Users/currentUser/Download/%E6%AD%8C%E6%9B%B2%E6%B5%B7'))
        .assertEqual('内部存储/下载/歌曲海');
    });

    it('file_uri_documents_folder', 0, () => {
      expect(formatDownloadPath('file://docs/storage/Users/currentUser/Documents/MyMusic'))
        .assertEqual('内部存储/文档/MyMusic');
    });

    it('file_uri_user_root', 0, () => {
      expect(formatDownloadPath('file://docs/storage/Users/currentUser'))
        .assertEqual('内部存储');
    });

    it('file_uri_trailing_slash_trimmed', 0, () => {
      expect(formatDownloadPath('file://docs/storage/Users/currentUser/Download/'))
        .assertEqual('内部存储/下载');
    });

    it('sandbox_default_path', 0, () => {
      expect(formatDownloadPath('/data/storage/el2/base/haps/entry/files/downloads'))
        .assertEqual('应用内部存储/downloads');
    });

    it('sandbox_path_without_files', 0, () => {
      expect(formatDownloadPath('/data/storage/el2/base'))
        .assertEqual('应用内部存储');
    });

    it('plain_absolute_path_kept', 0, () => {
      expect(formatDownloadPath('/storage/Users/currentUser/Download'))
        .assertEqual('内部存储/下载');
    });

    it('empty_means_unset', 0, () => {
      expect(formatDownloadPath('')).assertEqual('未设置');
      expect(formatDownloadPath('   ')).assertEqual('未设置');
    });
  });
}
