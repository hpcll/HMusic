# JS 脚本返回值规范

## 🚀 快速回答你的问题

### JS 脚本可以返回哪些信息？

| 信息类型 | 返回数据 | 用途 | 你的脚本是否支持 |
|---------|---------|------|----------------|
| **1. 播放 URL** | `string` | 播放音乐 | ✅ 已支持 |
| **2. 歌词** | `string`（LRC 格式） | 显示滚动歌词 | ❌ 需要扩展 |
| **3. 专辑封面图** | `string`（图片 URL） | 显示高清封面 | ❌ 需要扩展 |
| 4. 搜索结果 | `Array<Object>` | 搜索音乐（APP 用原生） | ❌ 不需要 |
| 5. 歌单列表 | `Array<Object>` | 显示歌单 | ❌ 未实现 |
| 6. 热歌榜 | `Array<Object>` | 排行榜 | ❌ 未实现 |
| 7. 专辑信息 | `Object` | 专辑详情 | ❌ 未实现 |
| 8. 歌手信息 | `Object` | 歌手详情 | ❌ 未实现 |

### 核心要点

1. **播放 URL**（必需）：`return "http://music.qq.com/xxx.mp3"`
2. **歌词**（可选）：`return "[00:00.00]歌词开始\n[00:05.00]..."`
3. **封面图**（可选）：`return "http://image.com/cover.jpg"`
4. **错误处理**：`throw new Error("错误消息")`

---

## 📖 核心概念

**JS 脚本负责所有业务逻辑，Flutter 只负责基础设施。**

```
┌─────────────────────────────────────┐
│ Flutter 职责                         │
│ • 代理网络请求                       │
│ • 提供 JS 运行时                     │
│ • 等待并接收 JS 返回值               │
└─────────────────────────────────────┘
              ↕️
┌─────────────────────────────────────┐
│ JS 脚本职责                          │
│ • 处理业务逻辑（判断 code 等）        │
│ • 返回最终结果                       │
│ • 成功：返回具体数据                 │
│ • 失败：抛出错误                     │
└─────────────────────────────────────┘
```

---

## 🎯 JS 脚本可以返回的信息

### 1. 音乐播放 URL（最常用）

#### ✅ 成功返回

**类型**：`string` 或 `Promise<string>`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'musicUrl') {
    // 方式1：直接返回字符串
    return "http://music.qq.com/xxx.mp3";
    
    // 方式2：返回 Promise
    return Promise.resolve("http://music.qq.com/xxx.mp3");
    
    // 方式3：async/await
    const url = await getMusicUrl(...);
    return url;  // 字符串
  }
});
```

**Flutter 接收**：
```dart
final String? url = await jsProxy.getMusicUrl(
  source: 'tx',
  songId: 'xxx',
  quality: '320k',
);

if (url != null && url.isNotEmpty) {
  print('播放 URL: $url');
  playMusic(url);  // ✅ 直接播放
}
```

---

#### ❌ 失败返回

**类型**：`Error` 或 `Promise.reject(Error)`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'musicUrl') {
    const response = await httpFetch(...);
    
    // 判断业务逻辑
    switch (response.body.code) {
      case 200:
        return response.body.url;  // ✅ 成功
        
      case 403:
        throw new Error("Key失效/鉴权失败");  // ❌ 失败
        
      case 500:
        throw new Error("服务器错误");  // ❌ 失败
        
      case 429:
        throw new Error("请求过于频繁");  // ❌ 失败
        
      default:
        throw new Error(response.body.message || "未知错误");
    }
  }
});
```

**Flutter 接收**：
```dart
try {
  final url = await jsProxy.getMusicUrl(...);
  playMusic(url);  // ✅ 成功
} catch (e) {
  print('获取失败: $e');  // ❌ 显示错误消息
  showError('播放失败：$e');
}
```

---

### 2. 搜索结果（如果使用 JS 搜索）

**注意**：当前 APP 使用**原生 API 搜索**，所以不需要 JS 返回搜索结果。

但如果未来支持 JS 搜索，应该返回：

#### 格式

**类型**：`Array<Object>` 或 `Promise<Array<Object>>`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'search') {
    const response = await httpFetch(...);
    
    if (response.body.code === 200) {
      // 返回歌曲列表数组
      return response.body.data.list.map(song => ({
        songId: song.id,           // ✅ 必需
        title: song.name,          // ✅ 必需
        author: song.artist,       // ✅ 必需
        album: song.album,         // 可选
        duration: song.duration,   // 可选（秒）
        platform: source,          // 可选
      }));
    } else {
      throw new Error(response.body.message);
    }
  }
});
```

---

### 3. 歌词（LRC 格式）

#### 格式

**类型**：`string` 或 `Promise<string>`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'lyric') {
    const response = await httpFetch(
      `${API_URL}/lyric?source=${source}&songId=${info.musicInfo.songmid}`,
      { ... }
    );
    
    if (response.body.code === 200) {
      // 返回 LRC 格式字符串
      return response.body.lyric;
      // 例如：
      // [00:00.00]歌词开始
      // [00:05.00]第一句歌词
      // [00:10.00]第二句歌词
    } else {
      throw new Error("歌词获取失败");
    }
  }
});
```

**Flutter 接收**：
```dart
final String? lyric = await jsProxy.getLyric(
  source: 'tx',
  songId: 'xxx',
);

if (lyric != null) {
  parseLRC(lyric);  // 解析并显示歌词
}
```

---

### 4. 专辑封面图（高清图）

#### 格式

**类型**：`string`（图片 URL）或 `Promise<string>`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'pic') {
    const response = await httpFetch(
      `${API_URL}/pic?source=${source}&songId=${info.musicInfo.songmid}`,
      { ... }
    );
    
    if (response.body.code === 200) {
      // 返回高清封面 URL
      return response.body.picUrl;
      // 例如：http://y.gtimg.cn/music/photo_new/T002R800x800M000xxx.jpg
    } else {
      throw new Error("封面获取失败");
    }
  }
});
```

**Flutter 接收**：
```dart
final String? picUrl = await jsProxy.getPic(
  source: 'tx',
  songId: 'xxx',
);

if (picUrl != null) {
  Image.network(picUrl);  // 显示封面
}
```

---

### 5. 音质列表

#### 格式

**类型**：`Array<string>`

**说明**：通常在脚本初始化时声明，不需要动态请求。

**示例**：
```javascript
// 在 send(EVENT_NAMES.inited) 中声明
send(EVENT_NAMES.inited, {
  status: true,
  sources: {
    'tx': {
      name: '腾讯音乐',
      type: 'music',
      actions: ['musicUrl', 'lyric', 'pic'],
      qualitys: ['128k', '320k'],  // ✅ 支持的音质列表
    }
  }
});
```

---

### 6. 歌单列表

#### 格式

**类型**：`Array<Object>`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'songList') {
    const response = await httpFetch(
      `${API_URL}/songlist?source=${source}&id=${info.id}`,
      { ... }
    );
    
    if (response.body.code === 200) {
      // 返回歌曲列表
      return response.body.list.map(song => ({
        songId: song.id,
        title: song.name,
        author: song.artist,
        album: song.album,
        duration: song.duration,  // 秒
        platform: source,
      }));
    } else {
      throw new Error("歌单获取失败");
    }
  }
});
```

---

### 7. 热歌榜/排行榜

#### 格式

**类型**：`Array<Object>`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'hotList') {
    const response = await httpFetch(
      `${API_URL}/hotlist?source=${source}&type=${info.type}`,
      { ... }
    );
    
    if (response.body.code === 200) {
      return response.body.list.map(song => ({
        songId: song.id,
        title: song.name,
        author: song.artist,
        rank: song.rank,  // 排名
      }));
    } else {
      throw new Error("榜单获取失败");
    }
  }
});
```

---

### 8. 专辑信息

#### 格式

**类型**：`Object`

**示例**：
```javascript
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  if (action === 'albumInfo') {
    const response = await httpFetch(
      `${API_URL}/album?source=${source}&albumId=${info.albumId}`,
      { ... }
    );
    
    if (response.body.code === 200) {
      return {
        albumId: response.body.id,
        albumName: response.body.name,
        artist: response.body.artist,
        picUrl: response.body.picUrl,
        publishTime: response.body.publishTime,
        songList: response.body.songList,  // 歌曲列表
      };
    } else {
      throw new Error("专辑信息获取失败");
    }
  }
});
```

---

### 9. 音源信息（脚本元数据）

#### 格式

**类型**：`Object`

**示例**：
```javascript
// 通过 send(EVENT_NAMES.inited) 发送
send(EVENT_NAMES.inited, {
  status: true,
  openDevTools: false,  // 是否打开开发者工具
  sources: {
    'tx': {
      name: '腾讯音乐',
      type: 'music',
      actions: ['musicUrl', 'lyric', 'pic'],  // ✅ 支持的操作
      qualitys: ['128k', '320k'],              // ✅ 支持的音质
    },
    'wy': {
      name: '网易云音乐',
      type: 'music',
      actions: ['musicUrl', 'lyric', 'pic', 'songList', 'hotList'],
      qualitys: ['128k', '320k', 'flac'],
    }
  }
});
```

---

## 📊 完整的返回值类型总结

| Action | 成功返回 | 失败返回 | 说明 | 你的脚本是否支持 |
|--------|---------|---------|------|----------------|
| **`musicUrl`** | `string` | `Error` | **播放链接**（必需） | ✅ 已支持 |
| `lyric` | `string` | `Error` | **LRC 格式歌词** | ❌ 未实现 |
| `pic` | `string` | `Error` | **专辑封面图 URL** | ❌ 未实现 |
| `search` | `Array<Object>` | `Error` | 搜索结果列表 | ❌ 未实现（APP 用原生搜索） |
| `songList` | `Array<Object>` | `Error` | 歌单列表 | ❌ 未实现 |
| `hotList` | `Array<Object>` | `Error` | 热歌榜/排行榜 | ❌ 未实现 |
| `albumInfo` | `Object` | `Error` | 专辑详细信息 | ❌ 未实现 |
| `artistInfo` | `Object` | `Error` | 歌手详细信息 | ❌ 未实现 |

### 你的脚本当前状态

看你的脚本（第111行）：
```javascript
actions: ["musicUrl"]  // ✅ 只支持播放链接
```

**如果你想支持歌词和封面图**，需要在脚本中添加对应的处理逻辑。

---

## 🔍 你的脚本示例分析

### 你的脚本（`lx-music-windyday.js`）

```javascript
const handleGetMusicUrl = async (source, musicInfo, quality) => {
  // 1. 发起网络请求
  const request = await httpFetch(
    `${API_URL}/url?source=${source}&songId=${songId}&quality=${quality}`,
    { ... }
  );
  
  // 2. 获取响应
  const { body } = request;
  
  // 3. ✅ 判断业务 code（JS 脚本的职责）
  switch (body.code) {
    case 200:
      console.log(`获取成功: ${body.url}`);
      return body.url;  // ✅ 返回 string
      
    case 403:
      console.log('Key失效/鉴权失败');
      throw new Error("Key失效/鉴权失败");  // ❌ 抛出 Error
      
    case 500:
      console.log(`服务器错误: ${body.message}`);
      throw new Error(`获取URL失败, ${body.message}`);
      
    case 429:
      console.log('请求过于频繁');
      throw new Error("请求过速");
      
    default:
      throw new Error(body.message ?? "未知错误");
  }
};

// 4. 注册事件处理器
on(EVENT_NAMES.request, ({ action, source, info }) => {
  if (action === 'musicUrl') {
    return handleGetMusicUrl(source, info.musicInfo, info.type)
      .then(url => Promise.resolve(url))   // ✅ 成功：返回 URL 字符串
      .catch(err => Promise.reject(err));  // ❌ 失败：抛出错误
  }
});
```

### Flutter 接收流程

```dart
// 1. 调用 JS
final url = await jsProxy.getMusicUrl(
  source: 'tx',
  songId: 'xxx',
  quality: '320k',
);

// 2. 接收结果
// JS 返回：
//   - 成功 → url = "http://music.qq.com/xxx.mp3"
//   - 失败 → 抛出异常，url = null

// 3. 使用结果
if (url != null && url.isNotEmpty) {
  playMusic(url);  // ✅ 播放
} else {
  showError('获取播放链接失败');  // ❌ 显示错误
}
```

---

## 🎯 关键要点

### 1. JS 脚本的职责

✅ **应该做**：
- 发起网络请求（通过 `lx.request`）
- 判断业务逻辑（检查 `code`）
- 处理错误情况
- 返回最终结果（字符串、对象、数组）
- 抛出有意义的错误消息

❌ **不应该做**：
- 返回原始 API 响应（让 Flutter 判断 code）
- 返回复杂的嵌套对象（Flutter 不知道怎么处理）
- 静默失败（不抛出错误）

### 2. Flutter 的职责

✅ **应该做**：
- 代理网络请求（`lx.request` → Dio）
- 提供 JS 运行时环境
- 等待 JS Promise
- 接收最终结果（字符串）
- 处理异常

❌ **不应该做**：
- 判断 API 的 `code`（业务逻辑）
- 解析 API 响应结构
- 猜测返回值类型

---

## 📝 类型定义（TypeScript 风格）

```typescript
// LX Music 事件处理器
type EventHandler = (params: EventParams) => Promise<any> | any;

interface EventParams {
  action: 'musicUrl' | 'search' | 'lyric' | 'qualities';
  source: string;  // 'tx' | 'wy' | 'kg' | 'kw' | 'mg'
  info: {
    type?: string;           // 音质：'128k' | '320k' | 'flac'
    musicInfo?: {
      songmid?: string;      // 歌曲 ID
      hash?: string;         // 歌曲 hash
      [key: string]: any;
    };
    keyword?: string;        // 搜索关键词
    page?: number;           // 分页
  };
}

// ===== 返回值类型 =====

// 1. 音乐 URL
type MusicUrlResult = string;  // "http://music.qq.com/xxx.mp3"

// 2. 搜索结果
type SearchResult = Array<{
  songId: string;       // 必需
  title: string;        // 必需
  author: string;       // 必需
  album?: string;
  duration?: number;    // 秒
  platform?: string;
  url?: string;         // 可选，可能没有
}>;

// 3. 歌词
type LyricResult = string;  // LRC 格式

// 4. 音质列表
type QualitiesResult = Array<string>;  // ['128k', '320k', 'flac']

// 5. 错误
type ErrorResult = Error;  // throw new Error("错误消息")
```

---

## 🧪 测试你的脚本

### 完整的调用示例

```javascript
// ===== JS 脚本侧 =====
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  console.log('收到请求:', action, source, info);
  
  if (action === 'musicUrl') {
    try {
      // 发起请求
      const response = await httpFetch(...);
      
      // 判断业务 code
      if (response.body.code === 200) {
        const url = response.body.url;
        console.log('返回 URL:', url);
        return url;  // ✅ 成功
      } else {
        console.error('API 错误:', response.body.message);
        throw new Error(response.body.message);  // ❌ 失败
      }
    } catch (error) {
      console.error('异常:', error);
      throw error;  // ❌ 网络异常等
    }
  }
  
  return Promise.reject('不支持的 action');
});
```

```dart
// ===== Flutter 侧 =====
try {
  print('[Flutter] 开始获取播放 URL...');
  
  final url = await jsProxy.getMusicUrl(
    source: 'tx',
    songId: '001ABC123',
    quality: '320k',
  );
  
  print('[Flutter] 成功获取 URL: $url');
  
  if (url != null && url.isNotEmpty) {
    playMusic(url);  // ✅ 播放
  }
  
} catch (e) {
  print('[Flutter] 获取失败: $e');
  showError('播放失败：$e');  // ❌ 显示错误
}
```

---

## 🎉 总结

### JS 脚本能返回的信息

| 信息类型 | 数据类型 | 示例 |
|---------|---------|------|
| **播放 URL** | `string` | `"http://music.qq.com/xxx.mp3"` |
| 搜索结果 | `Array<Object>` | `[{songId: '...', title: '...', ...}]` |
| 歌词 | `string` | `"[00:00.00]歌词开始\n[00:05.00]..."` |
| 音质列表 | `Array<string>` | `['128k', '320k', 'flac']` |
| **错误** | `Error` | `throw new Error("错误消息")` |

### 核心原则

1. ✅ **JS 处理业务逻辑**（判断 code）
2. ✅ **JS 返回最终结果**（字符串或对象）
3. ✅ **Flutter 只接收结果**（不判断 code）
4. ✅ **职责清晰分离**（各司其职）

---

---

## 🔧 如何扩展你的脚本支持歌词和封面图

### 1. 修改脚本声明

**当前**（第106-114行）：
```javascript
const musicSources = {};
MUSIC_SOURCE.forEach((item) => {
  musicSources[item] = {
    name: item,
    type: "music",
    actions: ["musicUrl"],  // ❌ 只有播放链接
    qualitys: MUSIC_QUALITY[item],
  };
});
```

**修改为**：
```javascript
const musicSources = {};
MUSIC_SOURCE.forEach((item) => {
  musicSources[item] = {
    name: item,
    type: "music",
    actions: ["musicUrl", "lyric", "pic"],  // ✅ 添加歌词和封面图
    qualitys: MUSIC_QUALITY[item],
  };
});
```

---

### 2. 添加歌词处理函数

**在 `handleGetMusicUrl` 后面添加**：
```javascript
const handleGetLyric = async (source, musicInfo) => {
  const songId = musicInfo.hash ?? musicInfo.songmid;
  const request = await httpFetch(
    `${API_URL}/lyric?source=${source}&songId=${songId}`,
    {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": `${
          env ? `lx-music-${env}/${version}` : `lx-music-request/${version}`
        }`,
        "X-Request-Key": API_KEY,
      },
    }
  );
  const { body } = request;
  
  switch (body.code) {
    case 200:
      console.log(`handleGetLyric(${source}_${songId}) success`);
      return body.lyric;  // ✅ 返回 LRC 字符串
    case 404:
      throw new Error("歌词不存在");
    case 403:
      throw new Error("Key失效/鉴权失败");
    default:
      throw new Error(body.message ?? "获取歌词失败");
  }
};
```

---

### 3. 添加封面图处理函数

```javascript
const handleGetPic = async (source, musicInfo) => {
  const songId = musicInfo.hash ?? musicInfo.songmid;
  const request = await httpFetch(
    `${API_URL}/pic?source=${source}&songId=${songId}`,
    {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": `${
          env ? `lx-music-${env}/${version}` : `lx-music-request/${version}`
        }`,
        "X-Request-Key": API_KEY,
      },
    }
  );
  const { body } = request;
  
  switch (body.code) {
    case 200:
      console.log(`handleGetPic(${source}_${songId}) success: ${body.picUrl}`);
      return body.picUrl;  // ✅ 返回图片 URL
    case 404:
      throw new Error("封面不存在");
    case 403:
      throw new Error("Key失效/鉴权失败");
    default:
      throw new Error(body.message ?? "获取封面失败");
  }
};
```

---

### 4. 修改事件处理器

**当前**（第116-137行）：
```javascript
on(EVENT_NAMES.request, ({ action, source, info }) => {
  switch (action) {
    case "musicUrl":
      // ...
      return handleGetMusicUrl(source, info.musicInfo, info.type)
        .then((data) => Promise.resolve(data))
        .catch((err) => Promise.reject(err));
    default:
      console.error(`action(${action}) not support`);
      return Promise.reject("action not support");
  }
});
```

**修改为**：
```javascript
on(EVENT_NAMES.request, ({ action, source, info }) => {
  switch (action) {
    case "musicUrl":
      if (env != "mobile") {
        console.group(`Handle Action(musicUrl)`);
        console.log("source", source);
        console.log("quality", info.type);
        console.log("musicInfo", info.musicInfo);
      }
      return handleGetMusicUrl(source, info.musicInfo, info.type)
        .then((data) => Promise.resolve(data))
        .catch((err) => Promise.reject(err));
    
    // ✅ 添加歌词处理
    case "lyric":
      console.log(`Handle Action(lyric) for ${source}`);
      return handleGetLyric(source, info.musicInfo)
        .then((data) => Promise.resolve(data))
        .catch((err) => Promise.reject(err));
    
    // ✅ 添加封面图处理
    case "pic":
      console.log(`Handle Action(pic) for ${source}`);
      return handleGetPic(source, info.musicInfo)
        .then((data) => Promise.resolve(data))
        .catch((err) => Promise.reject(err));
    
    default:
      console.error(`action(${action}) not support`);
      return Promise.reject("action not support");
  }
});
```

---

### 5. 完整的扩展脚本示例

<details>
<summary>点击查看完整代码</summary>

```javascript
const handleGetMusicUrl = async (source, musicInfo, quality) => {
  // ... 原有代码 ...
};

// ✅ 新增：歌词处理
const handleGetLyric = async (source, musicInfo) => {
  const songId = musicInfo.hash ?? musicInfo.songmid;
  const request = await httpFetch(
    `${API_URL}/lyric?source=${source}&songId=${songId}`,
    {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": `${env ? `lx-music-${env}/${version}` : `lx-music-request/${version}`}`,
        "X-Request-Key": API_KEY,
      },
    }
  );
  const { body } = request;
  if (body.code === 200) return body.lyric;
  throw new Error(body.message ?? "获取歌词失败");
};

// ✅ 新增：封面图处理
const handleGetPic = async (source, musicInfo) => {
  const songId = musicInfo.hash ?? musicInfo.songmid;
  const request = await httpFetch(
    `${API_URL}/pic?source=${source}&songId=${songId}`,
    {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": `${env ? `lx-music-${env}/${version}` : `lx-music-request/${version}`}`,
        "X-Request-Key": API_KEY,
      },
    }
  );
  const { body } = request;
  if (body.code === 200) return body.picUrl;
  throw new Error(body.message ?? "获取封面失败");
};

const musicSources = {};
MUSIC_SOURCE.forEach((item) => {
  musicSources[item] = {
    name: item,
    type: "music",
    actions: ["musicUrl", "lyric", "pic"],  // ✅ 声明支持的功能
    qualitys: MUSIC_QUALITY[item],
  };
});

on(EVENT_NAMES.request, ({ action, source, info }) => {
  switch (action) {
    case "musicUrl":
      return handleGetMusicUrl(source, info.musicInfo, info.type)
        .then((data) => Promise.resolve(data))
        .catch((err) => Promise.reject(err));
    
    case "lyric":
      return handleGetLyric(source, info.musicInfo)
        .then((data) => Promise.resolve(data))
        .catch((err) => Promise.reject(err));
    
    case "pic":
      return handleGetPic(source, info.musicInfo)
        .then((data) => Promise.resolve(data))
        .catch((err) => Promise.reject(err));
    
    default:
      return Promise.reject("action not support");
  }
});

send(EVENT_NAMES.inited, {
  status: true,
  openDevTools: DEV_ENABLE,
  sources: musicSources,
});
```

</details>

---

### 6. 你的 API 是否支持？

**需要确认你的 API (`https://lx.010.xx.kg`) 是否提供这些接口**：

```bash
# 歌词接口
GET https://lx.010.xx.kg/lyric?source=tx&songId=xxx
返回: { code: 200, lyric: "[00:00.00]歌词内容..." }

# 封面图接口
GET https://lx.010.xx.kg/pic?source=tx&songId=xxx
返回: { code: 200, picUrl: "http://..." }
```

如果 API 不支持，可能需要：
1. 升级 API 服务
2. 或者使用其他来源获取歌词/封面（如直接调用各平台 API）

---

**版本**：V1.2.1+  
**更新日期**：2025-10-03  
**状态**：✅ 已彻底修复，Flutter 不再判断 code
