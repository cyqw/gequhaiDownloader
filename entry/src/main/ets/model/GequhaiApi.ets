import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { QuarkParser } from '../utils/QuarkParser';
import { DownloadInfo, SongDetail, SongItem } from './SongItem';

const BASE_URL: string = 'https://www.gequhai.com';
const UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function tryDecodeQuarkUrl(encoded: string): string {
  if (!encoded) {
    return '';
  }
  try {
    const normalized = encoded.replace(/#/g, 'H').replace(/%/g, 'S');
    const base64Helper = new util.Base64Helper();
    const bytes = base64Helper.decodeSync(normalized);
    const decoder = util.TextDecoder.create('utf-8');
    const decoded = decoder.decodeToString(bytes);
    if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
      return decoded;
    }
  } catch (e) {
    console.warn('decode quark url failed: ' + JSON.stringify(e));
  }
  return '';
}

function extractWindowVar(html: string, name: string): string {
  const re1 = new RegExp(`window\\.${name}\\s*=\\s*['\\\"]([^'\\\"]*)['\\\"]`);
  const m1 = html.match(re1);
  if (m1) {
    return m1[1];
  }
  const re2 = new RegExp(`window\\.${name}\\s*=\\s*(-?\\d+)`);
  const m2 = html.match(re2);
  if (m2) {
    return m2[1];
  }
  return '';
}

/**
 * 在页面提供的两种音源之间按用户选择的类型挑选：
 * - mp3  -> mp3_extra_url（高品质 MP3）
 * - flac -> mp3_extra_url2（无损 FLAC）
 * 当所选类型不存在时，回退到另一种可用类型；两者都没有时返回空字符串。
 */
export function pickQuarkShareUrl(mp3Share: string, flacShare: string, fileType: string): string {
  if (fileType === 'flac') {
    return flacShare || mp3Share;
  }
  return mp3Share || flacShare;
}

/**
 * 从详情页 HTML 中抽取 id 为 targetId 的 div 的纯文本，
 * 并把 <br> 转换为换行（与站点 jQuery 的 .text() 行为一致）。
 */
function extractDivText(html: string, targetId: string): string {
  const re = new RegExp(`<div[^>]*id=["']${targetId}["'][^>]*>([\\s\\S]*?)<\\/div>`, 'i');
  const m = html.match(re);
  if (!m) {
    return '';
  }
  let text = m[1]
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
  return text.trim();
}

export class GequhaiApi {
  /**
   * 获取歌曲详情：封面、试听地址、带时间轴的 LRC 歌词。
   * 试听地址来自站点 /api/music（与播放页 APlayer 一致）；
   * 若该接口不可用，则尝试用直链解析结果作为预览源。
   */
  static async getSongDetail(song: SongItem, quarkCookie: string = '', fileType: string = 'mp3'): Promise<SongDetail> {
    const detail: SongDetail = {
      id: song.id,
      title: song.title,
      singer: song.singer,
      playUrl: song.playUrl,
      coverUrl: '',
      previewUrl: '',
      lrc: '',
      previewHeaders: {}
    };
    const httpRequest = http.createHttp();
    let pageHtml = '';
    let playId = '';
    let mp3Type = '0';
    try {
      const resp = await httpRequest.request(song.playUrl, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': UA, 'Referer': BASE_URL },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      if (resp.responseCode === 200) {
        pageHtml = resp.result as string;
        detail.coverUrl = extractWindowVar(pageHtml, 'mp3_cover');
        playId = extractWindowVar(pageHtml, 'play_id');
        const typeVal = extractWindowVar(pageHtml, 'mp3_type');
        if (typeVal) {
          mp3Type = typeVal;
        }
        detail.lrc = extractDivText(pageHtml, 'content-lrc2');
      }
    } catch (e) {
      console.warn('fetch song detail page failed: ' + JSON.stringify(e));
    }

    // 站点试听接口：POST /api/music，参数 id=play_id&type=mp3_type。
    if (playId) {
      try {
        const apiResp = await httpRequest.request(`${BASE_URL}/api/music`, {
          method: http.RequestMethod.POST,
          header: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent': UA,
            'X-Requested-With': 'http',
            'X-Custom-Header': 'Key',
            'Origin': BASE_URL,
            'Referer': song.playUrl
          },
          extraData: `id=${encodeURIComponent(playId)}&type=${encodeURIComponent(mp3Type)}`,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 15000,
          readTimeout: 15000
        });
        if (apiResp.responseCode === 200) {
          const obj = JSON.parse(apiResp.result as string) as Record<string, Object>;
          const data = obj['data'] as Record<string, Object>;
          const url = data && data['url'] ? (data['url'] as string) : '';
          if (url && url.startsWith('http')) {
            detail.previewUrl = url;
            detail.previewHeaders = {
              'User-Agent': UA,
              'Referer': 'https://pan.quark.cn/'
            };
          }
        }
      } catch (e) {
        console.warn('fetch preview url failed: ' + JSON.stringify(e));
      }
    }
    httpRequest.destroy();

    // 试听接口不可用时的兜底：用下载直链作为预览源。
    if (!detail.previewUrl) {
      try {
        const info = await GequhaiApi.getDownloadInfo(song.playUrl, song.id, quarkCookie, fileType);
        if (info.url && info.url.startsWith('http')) {
          detail.previewUrl = info.url;
          if (info.downloadHeaders) {
            detail.previewHeaders = info.downloadHeaders;
          }
        }
      } catch (e) {
        console.warn('fallback preview url failed: ' + JSON.stringify(e));
      }
    }
    return detail;
  }

  static async search(keyword: string, page: number = 1): Promise<SongItem[]> {
    const httpRequest = http.createHttp();
    const encoded = encodeURIComponent(keyword);
    // 站点搜索入口已改为 /search?s=<关键词>（旧的 /s/<关键词> 现在返回 301 跳转）。
    let url = `${BASE_URL}/search?s=${encoded}`;
    if (page > 1) {
      url = `${url}&page=${page}`;
    }
    try {
      let resp = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': UA,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': BASE_URL
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      // 兼容站点再次调整入口：跟随 301/302 的 location 再请求一次。
      if (resp.responseCode === 301 || resp.responseCode === 302) {
        const location = resp.header['location'] as string;
        if (location && location.startsWith('http')) {
          resp = await httpRequest.request(location, {
            method: http.RequestMethod.GET,
            header: {
              'User-Agent': UA,
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Referer': BASE_URL
            },
            expectDataType: http.HttpDataType.STRING,
            connectTimeout: 15000,
            readTimeout: 15000
          });
        }
      }
      if (resp.responseCode !== 200) {
        console.warn(`Gequhai search HTTP ${resp.responseCode}`);
        return [];
      }
      const html = resp.result as string;
      return GequhaiApi.parseSearchHtml(html);
    } catch (e) {
      console.error('Gequhai search error: ' + JSON.stringify(e));
      return [];
    } finally {
      httpRequest.destroy();
    }
  }

  private static parseSearchHtml(html: string): SongItem[] {
    const results: SongItem[] = [];
    const tableMatch = html.match(/<table[^>]*id=["']myTables["'][\s\S]*?<tbody>([\s\S]*?)<\/tbody>/i);
    if (!tableMatch) {
      return results;
    }
    const tbody = tableMatch[1];
    const rowRegex = /<tr[\s\S]*?<\/tr>/gi;
    const rows = tbody.match(rowRegex) || [];
    for (const row of rows) {
      const tdRegex = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      const tds: string[] = [];
      let m: RegExpExecArray | null;
      while ((m = tdRegex.exec(row)) !== null) {
        tds.push(m[1]);
      }
      if (tds.length < 3) {
        continue;
      }
      const linkMatch = tds[1].match(/<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/i);
      if (!linkMatch) {
        continue;
      }
      const href = linkMatch[1];
      const title = decodeHtmlEntities(linkMatch[2].replace(/<[^>]+>/g, '').trim());
      const singer = decodeHtmlEntities(tds[2].replace(/<[^>]+>/g, '').trim());
      const idMatch = href.match(/\/play\/(\d+)/);
      const id = idMatch ? idMatch[1] : '';
      const playUrl = href.startsWith('http') ? href : `${BASE_URL}${href}`;
      if (id && title) {
        results.push({ id, title, singer, playUrl });
      }
    }
    return results;
  }

  static async getDownloadInfo(playUrl: string, id: string, quarkCookie: string = '', fileType: string = 'mp3'): Promise<DownloadInfo> {
    const httpRequest = http.createHttp();
    let quarkShareUrl = '';
    try {
      let mp3Type = '0';
      let pageHtml = '';
      try {
        const pageResp = await httpRequest.request(playUrl, {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': UA,
            'Referer': BASE_URL
          },
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 15000,
          readTimeout: 15000
        });
        if (pageResp.responseCode === 200) {
          pageHtml = pageResp.result as string;
          const typeVal = extractWindowVar(pageHtml, 'mp3_type');
          if (typeVal) {
            mp3Type = typeVal;
          }
          const q1 = tryDecodeQuarkUrl(extractWindowVar(pageHtml, 'mp3_extra_url'));
          const q2 = tryDecodeQuarkUrl(extractWindowVar(pageHtml, 'mp3_extra_url2'));
          // 页面提供两种音源：mp3_extra_url = 高品质MP3，mp3_extra_url2 = 无损FLAC。
          // 按用户选择的类型优先，若该类型不存在则回退到另一种可用类型。
          quarkShareUrl = pickQuarkShareUrl(q1, q2, fileType);
          if (!quarkShareUrl) {
            const qMatch = pageHtml.match(/https?:\/\/pan\.quark\.cn\/s\/[A-Za-z0-9_-]+/);
            if (qMatch) {
              quarkShareUrl = qMatch[0];
            }
          }
        }
      } catch (e) {
        console.warn('Failed to fetch play page: ' + JSON.stringify(e));
      }

      // 1) Try direct download URL from api/music
      try {
        const apiResp = await httpRequest.request(`${BASE_URL}/api/music`, {
          method: http.RequestMethod.POST,
          header: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent': UA,
            'X-Requested-With': 'Http',
            'X-Custom-Header': 'Key',
            'Origin': BASE_URL,
            'Referer': playUrl
          },
          extraData: `id=${encodeURIComponent(id)}&type=${encodeURIComponent(mp3Type)}`,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 15000,
          readTimeout: 15000
        });
        if (apiResp.responseCode === 200) {
          const body = apiResp.result as string;
          const obj = JSON.parse(body) as Record<string, Object>;
          const data = obj['data'] as Record<string, Object>;
          const url = data && data['url'] ? (data['url'] as string) : '';
          if (url && url.startsWith('http') && url.indexOf('pan.quark.cn/s/') < 0) {
            return { url, isQuarkShare: false, quarkShareUrl };
          }
          if (url && url.indexOf('pan.quark.cn') >= 0 && !quarkShareUrl) {
            quarkShareUrl = url;
          }
        }
      } catch (e) {
        console.warn('api/music failed: ' + JSON.stringify(e));
      }

      // 2) Fallback: try appData fields that may contain direct URLs
      if (pageHtml) {
        const candidates: string[] = [
          extractWindowVar(pageHtml, 'mp3_url'),
          extractWindowVar(pageHtml, 'play_url'),
          extractWindowVar(pageHtml, 'url')
        ];
        for (const c of candidates) {
          if (c && c.startsWith('http') && c.indexOf('pan.quark.cn/s/') < 0) {
            return { url: c, isQuarkShare: false, quarkShareUrl };
          }
        }
      }

      // 3) Quark share detected: resolve to a direct download url (guest endpoint needs no cookie)
      if (quarkShareUrl) {
        try {
          const resolved = await QuarkParser.resolveShare(quarkShareUrl, quarkCookie);
          if (resolved.downloadUrl) {
            console.info('Quark resolved: ' + resolved.fileName + ', size=' + resolved.size);
            const headers: Record<string, string> = {
              'User-Agent': resolved.userAgent,
              'Referer': 'https://pan.quark.cn/'
            };
            if (resolved.cookie && resolved.cookie.length > 0) {
              headers['Cookie'] = resolved.cookie;
            }
            return {
              url: resolved.downloadUrl,
              isQuarkShare: false,
              quarkShareUrl,
              fileNameHint: resolved.fileName,
              downloadHeaders: headers
            };
          }
        } catch (e) {
          let msg = e instanceof Error ? e.message : JSON.stringify(e);
          if (msg === 'QUARK_AUTH_EXPIRED' || msg.indexOf('QUARK_AUTH_EXPIRED') >= 0) {
            msg = '夸克登录已过期，请到“我的”页面重新登录夸克网盘后重试';
          }
          console.warn('Quark resolve failed: ' + msg);
          return { url: '', isQuarkShare: true, quarkShareUrl, errorHint: msg };
        }
        return { url: '', isQuarkShare: true, quarkShareUrl, errorHint: '夸克链接解析失败' };
      }
      return { url: '', isQuarkShare: false, quarkShareUrl: '' };
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error('Gequhai getDownloadInfo error: ' + msg);
      return { url: '', isQuarkShare: false, quarkShareUrl };
    } finally {
      httpRequest.destroy();
    }
  }

  // Compatibility helper
  static async getDownloadUrl(playUrl: string, id: string, quarkCookie: string = '', fileType: string = 'mp3'): Promise<string> {
    const info = await GequhaiApi.getDownloadInfo(playUrl, id, quarkCookie, fileType);
    return info.url;
  }
}
