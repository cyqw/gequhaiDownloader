import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'gequhai_settings';
const KEY_DOWNLOAD_PATH: string = 'download_path';
const KEY_QUARK_COOKIE: string = 'quark_cookie';
const KEY_DOWNLOAD_TYPE: string = 'download_type';
const KEY_DOWNLOAD_ITEMS: string = 'download_items';
export const DOWNLOAD_TYPE_MP3: string = 'mp3';
export const DOWNLOAD_TYPE_FLAC: string = 'flac';

export class PreferencesUtil {
  private static pref: preferences.Preferences | null = null;

  static async init(context: common.Context): Promise<void> {
    if (!PreferencesUtil.pref) {
      PreferencesUtil.pref = await preferences.getPreferences(context, STORE_NAME);
    }
  }

  static async getDownloadPath(defaultPath: string): Promise<string> {
    if (!PreferencesUtil.pref) {
      return defaultPath;
    }
    const value = await PreferencesUtil.pref.get(KEY_DOWNLOAD_PATH, defaultPath);
    return value as string;
  }

  static async setDownloadPath(path: string): Promise<void> {
    if (!PreferencesUtil.pref) {
      return;
    }
    await PreferencesUtil.pref.put(KEY_DOWNLOAD_PATH, path);
    await PreferencesUtil.pref.flush();
  }

  static async getQuarkCookie(): Promise<string> {
    if (!PreferencesUtil.pref) {
      return '';
    }
    const value = await PreferencesUtil.pref.get(KEY_QUARK_COOKIE, '');
    return value as string;
  }

  static async setQuarkCookie(cookie: string): Promise<void> {
    if (!PreferencesUtil.pref) {
      return;
    }
    await PreferencesUtil.pref.put(KEY_QUARK_COOKIE, cookie);
    await PreferencesUtil.pref.flush();
  }

  static async getDownloadType(): Promise<string> {
    if (!PreferencesUtil.pref) {
      return DOWNLOAD_TYPE_MP3;
    }
    const value = await PreferencesUtil.pref.get(KEY_DOWNLOAD_TYPE, DOWNLOAD_TYPE_MP3);
    return value as string;
  }

  static async setDownloadType(type: string): Promise<void> {
    if (!PreferencesUtil.pref) {
      return;
    }
    await PreferencesUtil.pref.put(KEY_DOWNLOAD_TYPE, type);
    await PreferencesUtil.pref.flush();
  }

  static async getDownloadItems(): Promise<string> {
    if (!PreferencesUtil.pref) {
      return '';
    }
    const value = await PreferencesUtil.pref.get(KEY_DOWNLOAD_ITEMS, '');
    return value as string;
  }

  static async setDownloadItems(json: string): Promise<void> {
    if (!PreferencesUtil.pref) {
      return;
    }
    await PreferencesUtil.pref.put(KEY_DOWNLOAD_ITEMS, json);
    await PreferencesUtil.pref.flush();
  }
}
