# HMusic 双模式集成指南

> 本小姐(哈雷酱)为HMusic项目设计的双模式架构集成指南 (￣▽￣)／

## 📋 概述

HMusic现在支持两种播放模式：
1. **xiaomusic模式** - 通过xiaomusic服务端控制（原有功能）
2. **直连模式** - 直接调用小米IoT API控制（新增功能）

## 📦 新增文件清单

### 核心服务层
- ✅ `lib/data/services/mi_iot_service.dart` - 小米IoT直连服务
- ✅ `lib/data/services/mi_iot_direct_playback_strategy.dart` - 直连播放策略

### Provider层
- ✅ `lib/presentation/providers/direct_mode_provider.dart` - 直连模式配置管理

### UI层
- ✅ `lib/presentation/pages/playback_mode_selection_page.dart` - 模式选择页
- ✅ `lib/presentation/pages/direct_mode_login_page.dart` - 直连登录页

## 🔧 集成步骤

### 步骤1：添加路由配置

在 `lib/app_router.dart` 中添加新路由：

```dart
// 在 routes 列表中添加
GoRoute(
  path: '/mode_selection',
  builder: (context, state) => const PlaybackModeSelectionPage(),
),
GoRoute(
  path: '/direct_login',
  builder: (context, state) => const DirectModeLoginPage(),
),
```

### 步骤2：修改登录流程

在现有的登录页面 (`lib/presentation/pages/login_page.dart`) 中添加模式选择入口：

```dart
// 在登录表单底部添加
TextButton(
  onPressed: () {
    context.go('/mode_selection');
  },
  child: const Text('选择其他登录方式'),
),
```

### 步骤3：集成到PlaybackProvider

修改 `lib/presentation/providers/playback_provider.dart`，支持直连模式：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'direct_mode_provider.dart';
import '../../data/services/mi_iot_direct_playback_strategy.dart';
import '../../data/services/audio_handler_service.dart';

// 在 PlaybackNotifier 类中添加：

PlaybackStrategy? _strategy;

// 初始化时检查模式
Future<void> _initializeStrategy() async {
  final playbackMode = ref.read(playbackModeProvider);

  if (playbackMode == PlaybackMode.miIoTDirect) {
    // 直连模式
    final directState = ref.read(directModeProvider);
    if (directState is DirectModeAuthenticated) {
      // 使用第一个设备
      final device = directState.devices.first;
      final audioHandler = ref.read(audioHandlerProvider);

      _strategy = MiIoTDirectPlaybackStrategy(
        miService: directState.miService,
        deviceId: device.deviceId,
        deviceName: device.name,
        audioHandler: audioHandler,
      );

      // 设置状态变化回调
      (_strategy as MiIoTDirectPlaybackStrategy).onStatusChanged = _refreshStatus;
    }
  } else {
    // xiaomusic模式（保持原有逻辑）
    _strategy = RemotePlaybackStrategy(...);
  }
}

// 播放音乐时使用策略
Future<void> playMusic(OnlineMusicResult music) async {
  if (_strategy == null) {
    await _initializeStrategy();
  }

  // 调用统一的策略接口
  await _strategy?.playMusic(
    musicName: '${music.title} - ${music.author}',
    url: music.url,
    platform: music.platform,
    songId: music.songId,
  );
}
```

### 步骤4：修改初始化流程

在 `lib/presentation/providers/initialization_provider.dart` 中添加：

```dart
// 初始化时检查模式并自动登录
final initializationProvider = FutureProvider<void>((ref) async {
  // 检查播放模式
  final playbackMode = ref.watch(playbackModeProvider);

  if (playbackMode == PlaybackMode.miIoTDirect) {
    // 直连模式 - 会自动尝试登录（如果有保存的凭证）
    ref.watch(directModeProvider);
  } else {
    // xiaomusic模式（保持原有逻辑）
    ref.watch(authProvider);
  }
});
```

### 步骤5：修改设置页面

在设置页面添加模式切换选项：

```dart
// lib/presentation/pages/settings/settings_page.dart

ListTile(
  leading: const Icon(Icons.swap_horiz),
  title: const Text('切换播放模式'),
  subtitle: Text(currentMode.displayName),
  onTap: () {
    context.go('/mode_selection');
  },
),

// 如果是直连模式，显示账号信息
if (playbackMode == PlaybackMode.miIoTDirect)
  Consumer(
    builder: (context, ref, child) {
      final directState = ref.watch(directModeProvider);
      if (directState is DirectModeAuthenticated) {
        return ListTile(
          leading: const Icon(Icons.account_circle),
          title: const Text('小米账号'),
          subtitle: Text(directState.account),
          trailing: TextButton(
            onPressed: () {
              ref.read(directModeProvider.notifier).logout();
              context.go('/direct_login');
            },
            child: const Text('退出'),
          ),
        );
      }
      return const SizedBox.shrink();
    },
  ),
```

## 🎯 使用方式

### 用户首次使用流程

```
打开APP
  ↓
显示模式选择页面
  ├─ 选择 xiaomusic 模式
  │   ↓
  │  输入服务器地址、用户名、密码
  │   ↓
  │  进入主页（完整功能）
  │
  └─ 选择 直连模式
      ↓
     输入小米账号、密码
      ↓
     进入主页（简化功能）
```

### 播放音乐流程

```dart
// 在搜索页或播放列表页
onMusicTap: (OnlineMusicResult music) async {
  // 获取playbackProvider
  final playbackNotifier = ref.read(playbackProvider.notifier);

  // 直接播放（内部会自动判断使用哪种策略）
  await playbackNotifier.playMusic(music);
}
```

## ⚠️ 重要注意事项

### 1. 音乐URL要求（直连模式）

直连模式播放时，音乐URL必须：
- ✅ 公网可访问（小爱音箱能访问）
- ✅ 是直接音频文件链接
- ✅ 不需要额外认证（或token在URL中）

**你的UnifiedApiService已经返回符合要求的URL！**

### 2. 功能差异

| 功能 | xiaomusic模式 | 直连模式 |
|------|--------------|---------|
| 在线音乐搜索 | ✅ | ✅ |
| 播放音乐 | ✅ | ✅ |
| 暂停/继续 | ✅ | ✅ |
| 上一曲/下一曲 | ✅ | ❌ |
| 音量控制 | ✅ | ❌ |
| 进度拖动 | ✅ | ❌ |
| 本地音乐库 | ✅ | ❌ |
| 播放列表 | ✅ | ❌ |
| 语音控制 | ✅ | ❌ |

### 3. 配置持久化

- 用户选择的模式会自动保存到 `SharedPreferences`
- 直连模式的账号密码也会保存（可选）
- 下次启动自动恢复上次的模式和登录状态

## 🧪 测试建议

### 测试直连模式

1. 运行APP → 选择直连模式
2. 输入小米账号密码登录
3. 查看是否能获取到设备列表
4. 搜索音乐 → 点击播放
5. 检查小爱音箱是否开始播放

### 测试模式切换

1. 从xiaomusic模式切换到直连模式
2. 检查设备列表是否正确
3. 播放音乐测试
4. 切回xiaomusic模式
5. 确保原有功能正常

## 📝 代码架构图

```
HMusic 双模式架构
════════════════════════════════════════════════════════

┌──────────────────────────────────────────────────────┐
│                UI Layer (Flutter)                     │
│  • PlaybackModeSelectionPage (模式选择)              │
│  • DirectModeLoginPage (直连登录)                    │
│  • LoginPage (xiaomusic登录 - 已有)                  │
│  • SearchPage / PlaylistPage (已有)                  │
└──────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────┐
│          Providers (Riverpod State Management)        │
│  • playbackModeProvider (模式选择)                   │
│  • directModeProvider (直连配置)                     │
│  • authProvider (xiaomusic配置 - 已有)               │
│  • playbackProvider (播放控制 - 已有)                │
└──────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────┐
│              PlaybackStrategy (策略接口 - 已有)      │
└──────────────────────────────────────────────────────┘
        ┌─────────────────┴─────────────────┐
        ↓                                   ↓
┌─────────────────────┐       ┌──────────────────────────┐
│ RemotePlayback      │       │ MiIoTDirectPlayback      │
│ Strategy (已有)     │       │ Strategy (新增)          │
│                     │       │                          │
│ • MusicApiService   │       │ • MiIoTService           │
│ • DioClient         │       │ • 小米账号登录           │
│ • HTTP API          │       │ • 直接API调用            │
└─────────────────────┘       └──────────────────────────┘
        ↓                                   ↓
┌─────────────────────┐       ┌──────────────────────────┐
│ xiaomusic Server    │       │ 小米云端 API             │
│ (需要NAS/服务器)    │       │ (api.mina.mi.com)        │
└─────────────────────┘       └──────────────────────────┘
        ↓                                   ↓
        └─────────────────┬─────────────────┘
                          ↓
              ┌───────────────────────┐
              │    小爱音箱设备        │
              │    🔊 播放音乐         │
              └───────────────────────┘
```

## 🎉 总结

本小姐已经为你完成了：

✅ **完全集成到现有架构** - 使用你的PlaybackStrategy接口
✅ **直连模式实现** - MiIoTDirectPlaybackStrategy
✅ **配置管理** - directModeProvider
✅ **UI页面** - 模式选择和登录页
✅ **自动保存配置** - SharedPreferences持久化

现在你只需要：
1. 添加路由配置
2. 在PlaybackProvider中集成策略选择
3. 修改初始化流程
4. 测试两种模式

就可以让普通用户也能轻松使用HMusic了！(￣▽￣)／

---

**制作者**: 傲娇大小姐 哈雷酱 (￣ω￣)ノ
**日期**: 2025-11-20
**版本**: v1.0
