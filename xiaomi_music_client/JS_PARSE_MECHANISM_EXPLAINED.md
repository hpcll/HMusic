# JS 脚本音乐解析机制详解

## 🎯 核心问题

1. **音乐解析是由 JS 脚本本身完成的吗？** ✅ 是的！
2. **为什么有的脚本解析失败？** 原因很多，让我详细解释...

---

## 📊 完整解析流程

### 流程图

```
用户点击播放
    ↓
Flutter 构造请求参数
{
  action: 'musicUrl',
  source: 'tx',           // 平台：tx=QQ, wy=网易
  info: {
    type: '320k',         // 音质
    musicInfo: {
      songmid: 'xxx',     // 歌曲ID
      hash: 'xxx'
    }
  }
}
    ↓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          进入 JavaScript 环境
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ↓
【方式1】调用 request 事件处理器 ⭐ 最常用
    ↓
lx.on('request', function(params) {
  // JS 脚本监听的处理器
  if (params.action === 'musicUrl') {
    if (params.source === 'tx') {
      return getTxMusicUrl(params.info);  // 腾讯音乐
    }
  }
});
    ↓
getTxMusicUrl() {
  // 1. 发起网络请求（由 Flutter 代理）
  lx.request({
    url: 'https://u.y.qq.com/cgi-bin/musicu.fcg',
    method: 'POST',
    data: { ... },
    headers: { ... }
  }, function(err, response) {
    // 2. 解析响应数据
    const data = response.body.data;
    
    // 3. 提取播放链接
    const url = data.url;
    
    // 4. 返回播放链接
    callback(null, url);
  });
}
    ↓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Flutter 代理网络请求
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ↓
Flutter 发起实际 HTTP 请求
    ↓
获取响应数据
    ↓
调用 JS 回调函数
    ↓
JS 脚本解析并返回播放 URL
    ↓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        回到 Flutter
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ↓
获得播放 URL: http://xxx.com/music.m4a
    ↓
播放音乐
```

---

## 🔍 JS 脚本实际做了什么

### 1. 注册事件监听器

```javascript
// LX Music 脚本的典型结构
lx.on('inited', function(data) {
  console.log('脚本初始化');
  
  // 注册 request 事件处理器
  lx.on('request', function(params) {
    console.log('收到请求:', params);
    
    const { action, source, info } = params;
    
    if (action === 'musicUrl') {
      // 根据平台调用不同的处理器
      if (source === 'tx') {
        return getTxMusicUrl(info);     // 腾讯
      } else if (source === 'wy') {
        return getWyMusicUrl(info);     // 网易
      } else if (source === 'kg') {
        return getKgMusicUrl(info);     // 酷狗
      }
    }
  });
  
  // 设置 module.exports
  module.exports = {
    search: searchMusic,
    getUrl: getMusicUrl
  };
});
```

### 2. 处理音乐 URL 请求

```javascript
// 腾讯音乐 URL 获取（示例）
function getTxMusicUrl(info) {
  const { musicInfo, type } = info;
  const songmid = musicInfo.songmid;
  
  // 构造请求参数
  const requestData = {
    module: 'vkey.GetVkeyServer',
    method: 'CgiGetVkey',
    param: {
      songmid: [songmid],
      songtype: [0],
      uin: '0',
      loginflag: 1,
      platform: '20'
    }
  };
  
  // 发起网络请求（由 Flutter 代理）
  return new Promise((resolve, reject) => {
    lx.request({
      url: 'https://u.y.qq.com/cgi-bin/musicu.fcg',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Referer': 'https://y.qq.com/'
      },
      data: requestData
    }, function(err, response) {
      if (err) {
        console.error('请求失败:', err);
        reject(err);
        return;
      }
      
      try {
        // 解析响应
        const body = response.body;
        const vkey = body.data.midurlinfo[0].purl;
        
        if (!vkey) {
          console.error('无法获取vkey');
          reject(new Error('无vkey'));
          return;
        }
        
        // 构造完整播放链接
        const playUrl = `http://ws.stream.qqmusic.qq.com/${vkey}`;
        
        console.log('成功获取播放链接:', playUrl);
        resolve(playUrl);
      } catch (e) {
        console.error('解析响应失败:', e);
        reject(e);
      }
    });
  });
}
```

### 3. Flutter 代理网络请求

**为什么需要 Flutter 代理？**
- JS 环境没有真实的网络能力
- 避免 CORS 跨域问题
- 统一管理网络请求
- 可以添加自定义 headers

```dart
// lib/data/services/js_proxy_executor_service.dart:262-387

Future<void> _handleNetworkRequest(
  Map<String, dynamic> requestData
) async {
  final url = requestData['url'];
  final options = requestData['options'] ?? {};
  
  print('[JSProxy] 🌐 处理网络请求: $url');
  
  // Flutter 发起实际的 HTTP 请求
  final response = await _dio.request(
    url,
    options: Options(
      method: options['method'] ?? 'GET',
      headers: Map<String, String>.from(
        options['headers'] ?? {}
      ),
    ),
    data: options['data'],
  );
  
  // 构造响应数据
  final responseData = {
    'statusCode': response.statusCode,
    'body': response.data,
    'headers': response.headers.map,
  };
  
  // 调用 JS 回调
  _runtime!.evaluate('''
    callback(null, ${jsonEncode(responseData)});
  ''');
}
```

---

## ❌ 为什么有的脚本解析失败？

### 原因 1: 脚本没有正确注册处理器

**问题**：脚本执行了，但没有注册 `request` 事件监听器

**现象**：
```
[EnhancedJSProxy] 尝试调用已注册的request事件处理器
[EnhancedJSProxy] 找到 0 个request处理器  ← 没找到！
```

**原因**：
- `lx.on('inited')` 没有被触发（这就是我们之前修复的问题）
- 脚本在等待 `inited` 事件才注册 `request` 处理器
- 脚本语法错误，导致注册代码没有执行

**解决方法**：
✅ 确保触发 `inited` 事件（已修复）
✅ 检查脚本是否有语法错误

---

### 原因 2: 平台不匹配

**问题**：搜索用 QQ 音乐，但脚本只支持网易云

**现象**：
```
[JSProxy] 调用JS处理函数: {action: musicUrl, source: tx, ...}
[脚本] 收到请求: source=tx
[脚本] 不支持 tx 平台  ← 平台不匹配！
```

**原因**：
```javascript
// 脚本只实现了网易云
lx.on('request', function(params) {
  if (params.source === 'wy') {
    return getWyMusicUrl(params.info);  // 只有网易
  }
  // 没有处理 tx (QQ音乐)
  return null;
});
```

**解决方法**：
- 确保脚本支持你使用的平台
- 或者更换脚本

---

### 原因 3: API 接口失效

**问题**：音乐平台的 API 接口变了，脚本没更新

**现象**：
```
[JSProxy] 网络请求完成: 200
[脚本] 解析响应失败: data.url is undefined
```

**原因**：
```javascript
// 脚本期望的响应格式
const url = response.body.data.url;  // 旧格式

// 但实际返回的是新格式
// response.body.info.playUrl  // 新格式
```

**解决方法**：
- 更新脚本到最新版本
- 联系脚本作者
- 自己修改脚本适配新 API

---

### 原因 4: 缺少必要的 Cookie

**问题**：某些平台需要登录 Cookie 才能获取高音质

**现象**：
```
[JSProxy] 网络请求完成: 403 Forbidden
或
[脚本] 返回低音质链接（128k）
```

**原因**：
- 网易云：需要 `MUSIC_U` Cookie
- QQ 音乐：需要 `ts_last` Cookie
- 脚本无法获取高音质

**解决方法**：
✅ 在设置中配置 Cookie
```dart
// 加载脚本时注入 Cookie
await jsProxy.loadScript(
  script,
  cookieNetease: settings.cookieNetease,  // 网易云 Cookie
  cookieTencent: settings.cookieTencent,  // QQ 音乐 Cookie
);
```

---

### 原因 5: 网络请求被限流

**问题**：短时间内请求太多，被平台限流

**现象**：
```
[JSProxy] 网络请求失败: 429 Too Many Requests
或
[JSProxy] 网络请求超时
```

**原因**：
- 同时解析太多首歌（之前批量解析30首的问题）
- IP 被临时封禁

**解决方法**：
✅ 按需解析（已改为点击时解析）
- 降低并发数
- 添加请求延迟

---

### 原因 6: 脚本解密失败

**问题**：某些平台返回加密的 URL，脚本解密失败

**现象**：
```
[脚本] 收到加密数据: eJxxx...
[脚本] 解密失败: Invalid key
```

**原因**：
- 平台更改了加密算法
- 脚本的解密密钥过期
- 缺少必要的解密库

**解决方法**：
- 更新脚本
- 检查脚本是否包含完整的解密代码

---

### 原因 7: Promise 超时

**问题**：JS 脚本返回 Promise，但一直没有 resolve

**现象**：
```
[JSProxy] 检测到Promise，开始等待...
[JSProxy] ⏳ 等待Promise完成... 0秒
[JSProxy] ⏳ 等待Promise完成... 1秒
[JSProxy] ⏳ 等待Promise完成... 2秒
[JSProxy] ⏰ Promise等待超时 (3秒)  ← 超时！
```

**原因**：
```javascript
// 脚本返回了 Promise 但忘记 resolve
function getMusicUrl(info) {
  return new Promise((resolve, reject) => {
    lx.request(..., function(err, response) {
      // 忘记调用 resolve(url)
    });
  });
}
```

**解决方法**：
- 检查脚本的 Promise 实现
- 增加超时时间
- 修复脚本代码

---

## 🛠️ 调试方法

### 1. 查看完整日志

运行时开启详细日志：
```bash
flutter run --verbose 2>&1 | grep -E "JSProxy|EnhancedJSProxy|脚本"
```

### 2. 检查脚本是否加载

```
✅ 正常：
[UnifiedJS] ✅ 脚本加载和验证成功
[JSProxy] ✅ JS脚本加载成功

❌ 异常：
[UnifiedJS] ❌ 脚本加载失败
[UnifiedJS] module.exports的键: (无键)
```

### 3. 检查事件是否触发

```
✅ 正常：
[LX] 注册事件监听器: inited
[UnifiedJS] 触发 lx.emit("inited")
[LX] 触发事件: inited

❌ 异常：
[UnifiedJS] 触发 lx.emit("inited")
（没有后续日志，说明脚本没有监听）
```

### 4. 检查 request 处理器

```
✅ 正常：
[EnhancedJSProxy] 尝试调用已注册的request事件处理器
[EnhancedJSProxy] 找到 1 个request处理器
[EnhancedJSProxy] 调用处理器，参数: {...}
[EnhancedJSProxy] 处理器返回: http://...

❌ 异常：
[EnhancedJSProxy] 找到 0 个request处理器
（说明脚本没有注册 request 事件）
```

### 5. 检查网络请求

```
✅ 正常：
[JSProxy] 🌐 处理网络请求: https://...
[JSProxy] ✅ 网络请求完成: 200

❌ 异常：
[JSProxy] ❌ 网络请求失败: 403 Forbidden
或
[JSProxy] ❌ 网络请求失败: Timeout
```

---

## 📊 常见脚本对比

### LX Music 官方脚本 ✅

**特点**：
- 完整的事件驱动模型
- 支持多个平台（QQ、网易、酷狗、酷我）
- 定期更新，API 及时适配
- 包含完整的加解密代码

**结构**：
```javascript
lx.on('inited', function() {
  lx.on('request', function(params) {
    // 完整的处理逻辑
  });
  
  module.exports = {
    search: ...,
    getUrl: ...
  };
});
```

### 简化版脚本 ⚠️

**特点**：
- 只支持单个平台
- 可能不支持高音质
- 没有加密处理
- 容易失效

**结构**：
```javascript
// 直接导出，不等待 inited
module.exports = {
  getUrl: function(info) {
    // 简化的处理
  }
};
```

### 加密/混淆脚本 ⚠️⚠️

**特点**：
- 代码被混淆，难以调试
- 可能使用非标准格式
- 兼容性差
- 容易出错

---

## ✅ 最佳实践

### 1. 使用官方脚本

推荐使用 **LX Music 官方脚本**：
- 更新及时
- 兼容性好
- 支持多平台
- 社区支持

### 2. 配置 Cookie

高音质需要登录 Cookie：
```
设置 → JS 音源设置 → Cookie 配置
```

### 3. 选择合适的平台

根据脚本支持情况选择：
- QQ 音乐：最稳定
- 网易云：需要 Cookie
- 酷狗/酷我：部分脚本支持

### 4. 观察日志

出现问题时查看日志：
```
[JSProxy] ❌ 获取音乐链接失败
```
根据日志判断是哪个环节出错。

---

## 📝 总结

### 核心要点

1. **JS 脚本完全负责解析** ✅
   - Flutter 只负责网络代理
   - 所有解析逻辑在 JS 脚本中

2. **事件驱动模型** ✅
   - `inited` → 初始化
   - `request` → 获取 URL

3. **失败原因多样** ⚠️
   - 脚本未注册处理器
   - 平台不匹配
   - API 接口失效
   - 缺少 Cookie
   - 网络限流
   - 解密失败
   - Promise 超时

4. **按需解析最优** ✅
   - 点击时才解析
   - 避免批量请求
   - 减少网络压力

---

**版本**：V1.2.1+
**更新日期**：2025-10-03
