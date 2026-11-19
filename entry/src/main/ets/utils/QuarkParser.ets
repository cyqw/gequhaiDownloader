import { http } from '@kit.NetworkKit';

export interface QuarkResolveResult {
  downloadUrl: string;
  fileName: string;
  size: number;
  cookie: string;
  userAgent: string;
}

interface QuarkHttpResult {
  body: Record<string, Object>;
  cookies: string;
}

interface QuarkDownloadResult {
  body: Record<string, Object>;
  cookies: string;
  url: string;
}

const WEB_UA: string = 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.71 Safari/537.36 Core/1.94.225.400 QQBrowser/12.2.5544.400';
const DL_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/3.20.0 Chrome/112.0.5615.165 Electron/24.1.3.8 Safari/537.36 Channel/pckk_other_ch';

const TOKEN_URL: string = 'https://drive-h.quark.cn/1/clouddrive/share/sharepage/token';
const DETAIL_URL: string = 'https://drive-h.quark.cn/1/clouddrive/share/sharepage/detail';
const DOWNLOAD_URL: string = 'https://drive-pc.quark.cn/1/clouddrive/file/download';
const PATH_LIST_URL: string = 'https://drive-pc.quark.cn/1/clouddrive/file/info/path_list';
const SAVE_URL: string = 'https://drive-pc.quark.cn/1/clouddrive/share/sharepage/save';
const TASK_URL: string = 'https://drive-pc.quark.cn/1/clouddrive/task';

interface QuarkFile {
  fid: string;
  shareFidToken: string;
  name: string;
  size: number;
  isDir: boolean;
}

function nowMs(): string {
  return Date.now().toString();
}

function errText(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  try {
    return JSON.stringify(e);
  } catch (err) {
    return '未知错误';
  }
}

function getPwdId(shareUrl: string): string {
  const clean = shareUrl.split('?')[0].split('#')[0];
  const parts = clean.split('/');
  return parts[parts.length - 1] || '';
}

function toQuery(params: Record<string, string>): string {
  const parts: string[] = [];
  const keys = Object.keys(params);
  for (const k of keys) {
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`);
  }
  return parts.join('&');
}

function baseHeaders(cookie: string, ua: string): Record<string, string> {
  const headers: Record<string, string> = {
    'user-agent': ua,
    'origin': 'https://pan.quark.cn',
    'referer': 'https://pan.quark.cn/',
    'accept-language': 'zh-CN,zh;q=0.9'
  };
  if (cookie && cookie.trim()) {
    headers['cookie'] = cookie;
  }
  return headers;
}

/**
 * 仅保留下载所需的 __pugs Cookie（夸克下载直链会校验该 Cookie）。
 * HarmonyOS http 模块返回的 cookies 为 Netscape Cookie Jar 文本，每行字段以制表符分隔：
 * domain \t includeSubdomains \t path \t secure \t expires \t name \t value
 */
function extractPugsCookie(cookieJar: string): string {
  if (!cookieJar) {
    return '';
  }
  const lines = cookieJar.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.indexOf('__pugs') < 0) {
      continue;
    }
    const parts = trimmed.split('\t');
    if (parts.length >= 7 && parts[5] === '__pugs') {
      return `__pugs=${parts[6]}`;
    }
    // 兼容 name=value; ... 形式的 Set-Cookie 文本
    const match = trimmed.match(/__pugs=([^;\t]+)/);
    if (match) {
      return `__pugs=${match[1]}`;
    }
  }
  return '';
}

async function sendJson(client: http.HttpRequest, method: http.RequestMethod, url: string, params: string,
  body: string, cookie: string, ua: string, extraHeaders?: Record<string, string>): Promise<QuarkHttpResult> {
  const header = baseHeaders(cookie, ua);
  if (body) {
    header['content-type'] = 'application/json';
  }
  if (extraHeaders) {
    const keys = Object.keys(extraHeaders);
    for (const k of keys) {
      header[k] = extraHeaders[k];
    }
  }
  const resp = await client.request(url + (params ? `?${params}` : ''), {
    method: method,
    header: header,
    extraData: body,
    expectDataType: http.HttpDataType.STRING,
    connectTimeout: 15000,
    readTimeout: 20000
  });
  if (resp.responseCode !== 200) {
    // 夸克下载接口在触发游客大小限制时返回 HTTP 400，但 body 中带 code=23018。
    // 必须在抛错前解析 body，否则 guestDownloadUrl 无法识别限制并回退到 Cookie 转存。
    let code = 0;
    let msg = '';
    try {
      const errBody = JSON.parse(resp.result as string) as Record<string, Object>;
      code = Number(errBody['code'] || 0);
      msg = (errBody['message'] as string) || '';
    } catch (e) {
      // body 非 JSON 时保持空信息
    }
    if (code === 23018) {
      throw new Error('QUARK_GUEST_LIMIT');
    }
    // 登录态过期（401/require login/st invalid）时给出可操作的提示。
    const lowerMsg = msg.toLowerCase();
    if (resp.responseCode === 401 || code === 31001 || code === 31004 ||
      lowerMsg.indexOf('require login') >= 0 || lowerMsg.indexOf('st invalid') >= 0 ||
      lowerMsg.indexOf('token invalid') >= 0) {
      throw new Error('QUARK_AUTH_EXPIRED');
    }
    throw new Error(`夸克接口请求失败(HTTP ${resp.responseCode})${code ? `, code=${code}` : ''}${msg ? `: ${msg}` : ''}`);
  }
  const parsed = JSON.parse(resp.result as string) as Record<string, Object>;
  return { body: parsed, cookies: resp.cookies || '' };
}

function getData(obj: Record<string, Object>): Record<string, Object> {
  return (obj['data'] as Record<string, Object>) || {};
}

function parseFileList(res: Record<string, Object>): QuarkFile[] {
  const list = (getData(res)['list'] as Object[]) || [];
  const files: QuarkFile[] = [];
  for (const it of list) {
    const rec = it as Record<string, Object>;
    const isDir = rec['dir'] === true || rec['file'] === false;
    files.push({
      fid: (rec['fid'] as string) || '',
      shareFidToken: (rec['share_fid_token'] as string) || '',
      name: (rec['file_name'] as string) || '',
      size: Number(rec['size'] || 0),
      isDir: isDir
    });
  }
  return files;
}

async function findLargestFile(client: http.HttpRequest, pwdId: string, stoken: string, pdirFid: string,
  cookie: string, depth: number): Promise<QuarkFile | null> {
  if (depth > 6) {
    return null;
  }
  const params = toQuery({
    'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': '', 'ver': '2', 'pwd_id': pwdId, 'stoken': stoken,
    'pdir_fid': pdirFid, 'force': '0', '_page': '1', '_size': '100', '_fetch_banner': '0',
    '_fetch_share': '0', 'fetch_relate_conversation': '0', '_fetch_total': '1',
    '_sort': 'file_type:asc,file_name:asc', '__dt': '951', '__t': nowMs()
  });
  const res = await sendJson(client, http.RequestMethod.GET, DETAIL_URL, params, '', cookie, WEB_UA);
  const files = parseFileList(res.body);
  let best: QuarkFile | null = null;
  for (const f of files) {
    let candidate: QuarkFile | null = null;
    if (f.isDir) {
      candidate = await findLargestFile(client, pwdId, stoken, f.fid, cookie, depth + 1);
    } else {
      candidate = f;
    }
    if (candidate && (!best || candidate.size > best.size)) {
      best = candidate;
    }
  }
  return best;
}

async function guestDownloadUrl(client: http.HttpRequest, pwdId: string, stoken: string,
  file: QuarkFile, cookie: string): Promise<QuarkDownloadResult> {
  const body = JSON.stringify({
    'fids': [file.fid],
    'fids_token': [file.shareFidToken],
    'pwd_id': pwdId,
    'stoken': stoken
  });
  const res = await sendJson(client, http.RequestMethod.POST, DOWNLOAD_URL,
    toQuery({ 'entry': 'ft', 'fr': 'pc', 'pr': 'ucpro' }), body, cookie, DL_UA);
  const code = Number(res.body['code'] || 0);
  if (code === 23018) {
    throw new Error('QUARK_GUEST_LIMIT');
  }
  if (code !== 0) {
    const msg = (res.body['message'] as string) || '';
    throw new Error(`夸克直链获取失败(${code})${msg ? ': ' + msg : ''}`);
  }
  const arr = (res.body['data'] as Object[]) || [];
  if (arr.length === 0) {
    throw new Error('夸克未返回下载地址');
  }
  const url = ((arr[0] as Record<string, Object>)['download_url'] as string) || '';
  return { body: res.body, cookies: res.cookies, url: url };
}

async function saveAndDownload(client: http.HttpRequest, pwdId: string, stoken: string,
  file: QuarkFile, cookie: string): Promise<QuarkDownloadResult> {
  const pathBody = JSON.stringify({ 'file_path': ['/来自：分享'] });
  const pathList = await sendJson(client, http.RequestMethod.POST, PATH_LIST_URL,
    toQuery({ 'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': '', '__dt': '1266', '__t': nowMs() }),
    pathBody, cookie, WEB_UA);
  const pathArr = (pathList.body['data'] as Object[]) || [];
  if (pathArr.length === 0) {
    throw new Error('无法访问夸克网盘目录，请重新完成夸克认证');
  }
  const toPdirFid = ((pathArr[0] as Record<string, Object>)['fid'] as string) || '';
  if (!toPdirFid) {
    throw new Error('无法获取夸克保存目录');
  }
  const saveBody = JSON.stringify({
    'pwd_id': pwdId,
    'stoken': stoken,
    'pdir_fid': '0',
    'to_pdir_fid': toPdirFid,
    'fid_list': [file.fid],
    'fid_token_list': [file.shareFidToken],
    'scene': 'link'
  });
  const save = await sendJson(client, http.RequestMethod.POST, SAVE_URL,
    toQuery({ 'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': '', '__dt': '5660', '__t': nowMs() }),
    saveBody, cookie, WEB_UA);
  const taskId = (getData(save.body)['task_id'] as string) || '';
  if (!taskId) {
    throw new Error('夸克转存失败，请重新完成夸克认证');
  }
  let fidEncrypt = '';
  for (let i = 0; i < 8; i++) {
    try {
      const task = await sendJson(client, http.RequestMethod.GET, TASK_URL,
        toQuery({ 'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': '', 'task_id': taskId, 'retry_index': `${i}`, '__dt': '6355', '__t': nowMs() }),
        '', cookie, WEB_UA);
      const saveAs = (getData(task.body)['save_as'] as Record<string, Object>) || {};
      const topFids = (saveAs['save_as_top_fids'] as Object[]) || [];
      if (topFids.length > 0) {
        fidEncrypt = topFids[0] as string;
        break;
      }
    } catch (e) {
      // retry
    }
    await new Promise<void>((resolve) => setTimeout(resolve, 300));
  }
  if (!fidEncrypt) {
    throw new Error('夸克转存未完成，请稍后重试');
  }
  const dlBody = JSON.stringify({ 'fids': [fidEncrypt] });
  const dl = await sendJson(client, http.RequestMethod.POST, DOWNLOAD_URL,
    toQuery({ 'entry': 'ft', 'fr': 'pc', 'pr': 'ucpro' }), dlBody, cookie, DL_UA);
  const arr = (dl.body['data'] as Object[]) || [];
  if (arr.length === 0) {
    throw new Error('获取夸克下载地址失败');
  }
  const url = ((arr[0] as Record<string, Object>)['download_url'] as string) || '';
  return { body: dl.body, cookies: dl.cookies, url: url };
}

export class QuarkParser {
  /**
   * 解析夸克分享链接为可下载直链。
   * 优先使用游客直链接口（无需登录）；当文件超出游客限制时，若提供了 Cookie 则回退到转存下载。
   */
  static async resolveShare(shareUrl: string, cookie: string = '', passcode: string = ''): Promise<QuarkResolveResult> {
    const pwdId = getPwdId(shareUrl);
    if (!pwdId) {
      throw new Error('无效的夸克分享链接');
    }
    const client = http.createHttp();
    try {
      const tokenBody = JSON.stringify({
        'pwd_id': pwdId,
        'passcode': passcode,
        'support_visit_limit_private_share': 'true'
      });
      const token = await sendJson(client, http.RequestMethod.POST, TOKEN_URL,
        toQuery({ 'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': '', '__dt': '597', '__t': nowMs() }),
        tokenBody, cookie, WEB_UA);
      const stoken = (getData(token.body)['stoken'] as string) || '';
      if (!stoken) {
        throw new Error('获取夸克分享信息失败，链接可能已失效');
      }

      const file = await findLargestFile(client, pwdId, stoken, '0', cookie, 0);
      if (!file || !file.fid || !file.shareFidToken) {
        throw new Error('夸克分享中未找到可下载文件');
      }

      try {
        const guest = await guestDownloadUrl(client, pwdId, stoken, file, cookie);
        if (guest.url) {
          // 携带登录 Cookie 时，大文件的游客接口也会返回 dl-pc-*.drive.quark.cn 直链，
          // 该直链需要登录态才能下载，因此必须把完整 Cookie 透传给下载任务。
          const pugs = extractPugsCookie(guest.cookies);
          let guestCookie = pugs;
          if (cookie && cookie.trim()) {
            guestCookie = pugs && cookie.indexOf('__pugs=') < 0 ? `${cookie}; ${pugs}` : cookie;
          }
          return {
            downloadUrl: guest.url,
            fileName: file.name,
            size: file.size,
            cookie: guestCookie,
            userAgent: DL_UA
          };
        }
      } catch (e) {
        const msg = errText(e);
        if (msg.indexOf('QUARK_GUEST_LIMIT') < 0) {
          throw new Error(msg);
        }
      }

      if (!cookie || !cookie.trim()) {
        throw new Error('文件超出游客下载大小限制，请先完成夸克认证后重试');
      }
      const saved = await saveAndDownload(client, pwdId, stoken, file, cookie);
      if (!saved.url) {
        throw new Error('获取夸克下载地址失败');
      }
      // 转存下载直链（dl-pc-*.drive.quark.cn）会校验登录态，必须携带完整登录 Cookie，
      // 仅 __pugs 会返回 HTTP 412，导致系统下载任务失败(code 8)。
      const pugs = extractPugsCookie(saved.cookies);
      let saveCookie = cookie;
      if (pugs && saveCookie.indexOf('__pugs=') < 0) {
        saveCookie = `${saveCookie}; ${pugs}`;
      }
      return {
        downloadUrl: saved.url,
        fileName: file.name,
        size: file.size,
        cookie: saveCookie,
        userAgent: DL_UA
      };
    } finally {
      client.destroy();
    }
  }
}
