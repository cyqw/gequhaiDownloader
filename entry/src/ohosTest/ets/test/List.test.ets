import abilityTest from './Ability.test';
import quarkParserTest from './QuarkParser.test';
import downloadTypeTest from './DownloadType.test';
import networkUtilTest from './NetworkUtil.test';
import downloadManagerTest from './DownloadManager.test';
import lyricUtilTest from './LyricUtil.test';
import downloadStorageTest from './DownloadStorage.test';
import pathUtilTest from './PathUtil.test';

export default function testsuite() {
  abilityTest();
  quarkParserTest();
  downloadTypeTest();
  networkUtilTest();
  downloadManagerTest();
  lyricUtilTest();
  downloadStorageTest();
  pathUtilTest();
}
