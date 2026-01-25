/**
 * HMusic 音频代理 - Cloudflare Workers
 *
 * 功能：
 * 1. 代理转发音频请求，绕过 CDN 的 User-Agent 和 Referer 限制
 * 2. 自动处理重定向
 * 3. 支持 Range 请求（断点续传）
 * 4. 添加 CORS 头，允许小爱音箱访问
 *
 * 部署方法：
 * 1. 登录 https://dash.cloudflare.com
 * 2. 进入 Workers & Pages
 * 3. 创建新 Worker
 * 4. 粘贴此代码
 * 5. 部署后获取 URL，如 https://your-worker.your-subdomain.workers.dev
 *
 * 使用方法：
 * GET https://your-worker.workers.dev/proxy?url=<encoded_audio_url>
 *
 * @author HMusic Team
 * @version 1.0.0
 */

// ============== 配置区域 ==============

// 允许的音频域名白名单（安全措施，防止滥用）
const ALLOWED_DOMAINS = [
  // QQ音乐
  'qq.com',
  'qqmusic.qq.com',
  'dl.stream.qqmusic.qq.com',
  'ws.stream.qqmusic.qq.com',
  'isure.stream.qqmusic.qq.com',
  'aqqmusic.tc.qq.com',
  'streamoc.music.tc.qq.com',
  'c.y.qq.com',
  'wx.music.tc.qq.com',
  // 网易云音乐
  'music.126.net',
  'm7.music.126.net',
  'm8.music.126.net',
  'm10.music.126.net',
  '163.com',
  // 酷狗音乐
  'kugou.com',
  'trackercdn.kugou.com',
  // 酷我音乐
  'kuwo.cn',
  'sycdn.kuwo.cn',
  'other.web.nf01.sycdn.kuwo.cn',
  // 咪咕音乐
  'migu.cn',
  'freetyst.nf.migu.cn',
  // 通用 CDN
  'clouddn.com',
  'qiniucdn.com',
  'aliyuncs.com',
];

// 请求超时时间（毫秒）
const REQUEST_TIMEOUT = 30000;

// ============== 主处理逻辑 ==============

export default {
  async fetch(request, env, ctx) {
    // 处理 CORS 预检请求
    if (request.method === 'OPTIONS') {
      return handleCORS();
    }

    const url = new URL(request.url);
    const path = url.pathname;

    // 路由处理
    if (path === '/proxy' || path === '/') {
      return handleProxy(request, url);
    } else if (path === '/health') {
      return handleHealth();
    } else {
      return new Response('Not Found', { status: 404 });
    }
  },
};

/**
 * 处理代理请求
 */
async function handleProxy(request, url) {
  // 获取目标 URL
  const targetUrl = url.searchParams.get('url');

  if (!targetUrl) {
    return jsonResponse({
      error: 'Missing url parameter',
      usage: 'GET /proxy?url=<encoded_audio_url>',
    }, 400);
  }

  // 解码 URL
  let decodedUrl;
  try {
    decodedUrl = decodeURIComponent(targetUrl);
  } catch (e) {
    return jsonResponse({ error: 'Invalid URL encoding' }, 400);
  }

  // 验证 URL 格式
  let targetUrlObj;
  try {
    targetUrlObj = new URL(decodedUrl);
  } catch (e) {
    return jsonResponse({ error: 'Invalid URL format' }, 400);
  }

  // 安全检查：只允许 HTTP/HTTPS
  if (!['http:', 'https:'].includes(targetUrlObj.protocol)) {
    return jsonResponse({ error: 'Only HTTP/HTTPS URLs are allowed' }, 400);
  }

  // 安全检查：域名白名单
  if (!isDomainAllowed(targetUrlObj.hostname)) {
    return jsonResponse({
      error: 'Domain not allowed',
      domain: targetUrlObj.hostname,
      hint: 'Contact admin to add this domain to whitelist',
    }, 403);
  }

  // 构建代理请求头
  const headers = new Headers();

  // 伪装 User-Agent（重要！很多 CDN 检查这个）
  headers.set('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1');

  // 设置 Referer（QQ音乐等需要）
  const referer = getRefererForDomain(targetUrlObj.hostname);
  if (referer) {
    headers.set('Referer', referer);
  }

  // 转发 Range 头（支持断点续传）
  const rangeHeader = request.headers.get('Range');
  if (rangeHeader) {
    headers.set('Range', rangeHeader);
  }

  // 发起代理请求
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT);

    const response = await fetch(decodedUrl, {
      method: 'GET',
      headers: headers,
      redirect: 'follow', // 自动跟随重定向
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    // 检查响应状态
    if (!response.ok && response.status !== 206) {
      return jsonResponse({
        error: 'Upstream request failed',
        status: response.status,
        statusText: response.statusText,
      }, 502);
    }

    // 构建响应头
    const responseHeaders = new Headers();

    // 设置 Content-Type
    const contentType = response.headers.get('Content-Type');
    responseHeaders.set('Content-Type', contentType || 'audio/mpeg');

    // 转发 Content-Length
    const contentLength = response.headers.get('Content-Length');
    if (contentLength) {
      responseHeaders.set('Content-Length', contentLength);
    }

    // 转发 Content-Range（断点续传响应）
    const contentRange = response.headers.get('Content-Range');
    if (contentRange) {
      responseHeaders.set('Content-Range', contentRange);
    }

    // 添加 CORS 头
    addCORSHeaders(responseHeaders);

    // 添加缓存控制（音频文件可以缓存）
    responseHeaders.set('Cache-Control', 'public, max-age=86400'); // 缓存24小时

    // 返回流式响应
    return new Response(response.body, {
      status: response.status,
      headers: responseHeaders,
    });

  } catch (error) {
    if (error.name === 'AbortError') {
      return jsonResponse({ error: 'Request timeout' }, 504);
    }
    return jsonResponse({
      error: 'Proxy request failed',
      message: error.message,
    }, 500);
  }
}

/**
 * 健康检查端点
 */
function handleHealth() {
  return jsonResponse({
    status: 'ok',
    service: 'HMusic Audio Proxy',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
  }, 200);
}

/**
 * 处理 CORS 预检请求
 */
function handleCORS() {
  const headers = new Headers();
  addCORSHeaders(headers);
  headers.set('Access-Control-Max-Age', '86400');
  return new Response(null, { status: 204, headers });
}

/**
 * 添加 CORS 头
 */
function addCORSHeaders(headers) {
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Range, Content-Type');
  headers.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Content-Type');
}

/**
 * 检查域名是否在白名单中
 */
function isDomainAllowed(hostname) {
  const lowerHostname = hostname.toLowerCase();
  return ALLOWED_DOMAINS.some(domain => {
    return lowerHostname === domain || lowerHostname.endsWith('.' + domain);
  });
}

/**
 * 根据域名获取对应的 Referer
 */
function getRefererForDomain(hostname) {
  const lowerHostname = hostname.toLowerCase();

  if (lowerHostname.includes('qq.com') || lowerHostname.includes('qqmusic')) {
    return 'https://y.qq.com/';
  }
  if (lowerHostname.includes('163.com') || lowerHostname.includes('126.net')) {
    return 'https://music.163.com/';
  }
  if (lowerHostname.includes('kugou')) {
    return 'https://www.kugou.com/';
  }
  if (lowerHostname.includes('kuwo')) {
    return 'https://www.kuwo.cn/';
  }
  if (lowerHostname.includes('migu')) {
    return 'https://music.migu.cn/';
  }

  return null;
}

/**
 * 返回 JSON 响应
 */
function jsonResponse(data, status = 200) {
  const headers = new Headers();
  headers.set('Content-Type', 'application/json');
  addCORSHeaders(headers);

  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers,
  });
}
