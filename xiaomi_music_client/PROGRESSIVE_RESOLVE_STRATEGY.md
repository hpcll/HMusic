# 渐进式播放URL解析策略

## 📌 设计理念

**问题**：搜索返回30首歌，如果一次性解析所有播放URL：
- ❌ 等待时间长（10-30秒）
- ❌ 网络请求多（30个并发）
- ❌ 资源浪费（用户可能只听前3首）
- ❌ 用户体验差（搜索结果要等很久才显示）

**解决方案**：按需解析 + 智能预加载

---

## 🎯 策略说明

### 1️⃣ **搜索完成** - 立即返回结果
```
用户搜索 "林俊杰"
  ↓
原生API返回30首（包含songId、title等基础信息）
  ↓
【立即显示】搜索结果（无播放URL，但可以看到歌曲列表）
  ↓
【后台任务】预解析前5首（异步，不阻塞UI）
```

### 2️⃣ **后台预解析** - 提前准备热门歌曲
```
搜索结果已显示
  ↓
后台默默解析前5首
  ↓
解析完成后静默更新状态
  ↓
用户点击前5首 -> 直接播放（已有URL）✅
用户点击第6-30首 -> 即时解析（1-2秒）⏳
```

### 3️⃣ **点击播放** - 按需即时解析
```
用户点击第10首歌
  ↓
检查是否已有播放URL
  ↓ (没有)
调用JS脚本解析（单首，1-2秒）
  ↓
播放
```

---

## 💡 核心代码

### 搜索流程
```dart
// lib/presentation/providers/music_search_provider.dart:207-215

// 1. 原生搜索获取基础信息
parsed = await _searchUsingNativeByStrategy(...);

if (parsed.isNotEmpty) {
  // 2. 【优化】先快速返回搜索结果
  print('搜索成功，返回 ${parsed.length} 首（稍后按需解析播放URL）');
  
  // 3. 后台预解析前5首（不阻塞）
  _preResolveTopResults(parsed, settings);
}

// 4. 立即更新UI，显示搜索结果
state = state.copyWith(onlineResults: parsed);
```

### 后台预解析
```dart
// lib/presentation/providers/music_search_provider.dart:265-317

void _preResolveTopResults(
  List<OnlineMusicResult> results,
  SourceSettings settings,
) {
  // 异步执行，不阻塞UI
  Future.microtask(() async {
    // 只预解析前5首
    final topResults = results.take(5).toList();
    
    // 批量解析（并发数降低到3）
    final resolvedResults = await jsProxyNotifier.resolveMultipleResults(
      topResults,
      preferredQuality: '320k',
      maxConcurrent: 3,
    );
    
    // 静默更新状态
    final updatedResults = List.from(state.onlineResults);
    for (int i = 0; i < resolvedResults.length; i++) {
      if (resolvedResults[i].url.isNotEmpty) {
        updatedResults[i] = resolvedResults[i];
      }
    }
    
    state = state.copyWith(onlineResults: updatedResults);
  });
}
```

### 点击播放时的即时解析
```dart
// lib/presentation/pages/music_search_page.dart:391-416

Future<String?> _resolvePlayUrlForItem(OnlineMusicResult item) async {
  // 检查是否已有URL（可能已被预解析）
  if (item.url.isNotEmpty) {
    print('✅ 已有播放URL，直接使用');
    return item.url;
  }
  
  // 没有URL，即时解析（单首）
  print('⏳ 即时解析播放URL...');
  final jsProxy = ref.read(jsProxyProvider.notifier);
  
  final url = await jsProxy.getMusicUrl(
    source: platform,
    songId: songId,
    quality: '320k',
  );
  
  return url;
}
```

---

## 📊 性能对比

### 方案A：一次性批量解析（旧方案 ❌）
```
搜索 -> 等待 -> 解析30首 -> 等待20秒 -> 显示结果
```
- 首次显示时间：**20-30秒** ❌
- 点击播放延迟：**0秒** ✅
- 网络请求：**30个并发** ❌

### 方案B：渐进式解析（新方案 ✅）
```
搜索 -> 立即显示 -> 后台解析前5首 -> 点击时按需解析
```
- 首次显示时间：**1-2秒** ✅
- 点击前5首延迟：**0秒** ✅（已预解析）
- 点击第6-30首延迟：**1-2秒** ✅（单首即时解析）
- 网络请求：**按需发起** ✅

---

## 🎯 用户体验提升

### 场景1：用户只听第1首歌
- **旧方案**：等30秒（解析30首）
- **新方案**：等2秒（预解析前5首），第1首已解析好
- **提升**：⚡ 快15倍

### 场景2：用户听完前5首
- **旧方案**：等30秒
- **新方案**：等2秒（前5首已预解析）
- **提升**：⚡ 快15倍

### 场景3：用户想听第15首
- **旧方案**：等30秒
- **新方案**：搜索1秒 + 点击时解析2秒 = 3秒
- **提升**：⚡ 快10倍

### 场景4：用户滚动浏览所有歌曲
- **旧方案**：等30秒
- **新方案**：立即显示，按需播放
- **提升**：⚡ 即时响应

---

## ⚙️ 可配置参数

可以根据实际情况调整：

```dart
// 预解析数量（默认5首）
final topResults = results.take(5).toList();

// 并发数（默认3）
maxConcurrent: 3,

// 音质（默认320k）
preferredQuality: '320k',
```

**建议配置**：
- **WiFi环境**：预解析10首，并发5
- **移动网络**：预解析3首，并发2
- **弱网环境**：预解析0首，完全按需

---

## 🔄 完整流程图

```
┌─────────────────────────────────────────────────────────┐
│ 1. 用户搜索 "林俊杰"                                      │
└────────────────┬────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────────────┐
│ 2. 原生API返回30首（包含songId等基础信息）                 │
│    - 标题、歌手、专辑、songId                             │
│    - ❌ 没有播放URL                                      │
└────────────────┬────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────────────┐
│ 3. 立即显示搜索结果（1-2秒）✅                            │
│    用户可以看到歌曲列表                                   │
└────────────────┬────────────────────────────────────────┘
                 ↓
        ┌────────┴────────┐
        ↓                 ↓
┌──────────────┐  ┌──────────────────────────────────────┐
│ 4A. 后台任务 │  │ 4B. 用户操作                           │
│              │  │                                        │
│ 预解析前5首  │  │ - 浏览列表                             │
│ (异步后台)   │  │ - 点击歌曲播放                         │
│              │  │                                        │
│ 并发数: 3    │  │                                        │
│ 时间: 3-5秒  │  │                                        │
└──────┬───────┘  └──────┬─────────────────────────────────┘
       ↓                 ↓
       │          ┌──────────────────┐
       │          │ 检查是否有播放URL │
       │          └──────┬───────────┘
       │                 ↓
       │          ┌──────┴──────┐
       │          ↓             ↓
       │    ┌─────────┐   ┌─────────────┐
       │    │ 已有URL │   │ 没有URL     │
       │    │ (前5首) │   │ (第6-30首)  │
       │    └────┬────┘   └─────┬───────┘
       │         ↓               ↓
       │    ┌─────────┐   ┌─────────────┐
       │    │直接播放 │   │即时解析(1秒)│
       │    └─────────┘   └─────┬───────┘
       │                         ↓
       │                   ┌─────────┐
       │                   │  播放   │
       │                   └─────────┘
       ↓
┌─────────────────────────┐
│ 5. 预解析完成           │
│    静默更新前5首的URL    │
│    (用户无感知)         │
└─────────────────────────┘
```

---

## 🎨 UI反馈（可选）

可以在UI上增加视觉反馈：

```dart
// 搜索结果列表项
ListTile(
  title: Text(song.title),
  subtitle: Text(song.author),
  trailing: song.url.isNotEmpty
    ? Icon(Icons.check_circle, color: Colors.green) // 已解析
    : Icon(Icons.downloading, color: Colors.grey),  // 未解析
)
```

---

## 📝 总结

### 优势 ✅
1. **响应快** - 搜索结果1-2秒显示
2. **体验好** - 点击前5首无延迟
3. **省资源** - 只解析用户需要的
4. **不阻塞** - 后台预解析不影响UI

### 注意事项 ⚠️
1. 预解析失败不影响搜索功能
2. 点击播放时仍会检查并按需解析
3. 预解析数量可根据网络环境调整

### 未来优化 🚀
1. 根据网络状态动态调整预解析数量
2. 记录用户播放习惯，智能预解析
3. 使用队列管理解析任务，避免重复
4. 添加解析进度指示器

---

**版本**：V1.2.1+
**更新日期**：2025-10-03
