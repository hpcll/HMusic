# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

HMusic 是一款智能音乐播放器,支持两种播放模式:
- **xiaomusic 模式**: 通过 xiaomusic 服务端控制小爱音箱(需部署服务端)
- **直连模式**: 直接通过小米 IoT API 控制小爱音箱(无需服务端)

## 常用命令

### 开发环境

```bash
# 获取依赖
flutter pub get

# 运行应用 (开发模式)
flutter run

# 代码生成 (用于 Riverpod 和 JSON 序列化)
flutter pub run build_runner build --delete-conflicting-outputs

# 清理构建缓存
flutter clean && flutter pub get
```

### 构建发布版本

```bash
# 使用自动化构建脚本 (推荐)
./build_release.sh

# 该脚本会:
# 1. 自动读取并可选更新版本号
# 2. 提供多种构建选项 (Android 通用版/分架构版/iOS)
# 3. 自动签名和混淆
# 4. 生成 SHA256 校验和
# 5. 输出到 build/release/ 目录

# 手动构建 Android APK (通用版)
flutter build apk --release --obfuscate --split-debug-info=build/symbols

# 手动构建 Android APK (分架构版,体积更小)
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols

# 手动构建 iOS IPA (无签名)
flutter build ios --release --no-codesign --obfuscate --split-debug-info=build/symbols
```

### 测试

```bash
# 运行所有测试
flutter test

# 运行单个测试文件
flutter test test/path/to/test_file.dart

# 查看测试覆盖率
flutter test --coverage
```

## 核心架构

### 状态管理

使用 **Riverpod** 进行状态管理,所有 Provider 定义在 `lib/presentation/providers/` 目录。

**关键 Provider:**

- `playbackProvider` - 播放控制总控制器
- `playbackModeProvider` - 播放模式选择 (xiaomusic/直连)
- `directModeProvider` - 直连模式状态管理
- `authProvider` - xiaomusic 模式认证
- `deviceProvider` - 设备选择
- `musicSearchProvider` - 音乐搜索

### 策略模式架构

播放控制使用**策略模式**,支持多种播放策略:

```
PlaybackProvider
    └── PlaybackStrategy (抽象接口)
            ├── RemotePlaybackStrategy (xiaomusic 模式)
            │       └── 通过 xiaomusic 服务端 API 控制
            ├── MiIoTDirectPlaybackStrategy (直连模式)
            │       └── 直接调用小米 IoT Cloud API
            └── LocalPlaybackStrategy (本地播放)
                    └── 使用 just_audio 本地播放
```

**核心文件:**
- `lib/data/services/playback_strategy.dart` - 策略接口定义
- `lib/data/services/remote_playback_strategy.dart` - xiaomusic 模式实现
- `lib/data/services/mi_iot_direct_playback_strategy.dart` - 直连模式实现
- `lib/data/services/local_playback_strategy.dart` - 本地播放实现

### 双模式设计

**xiaomusic 模式:**
- ✅ 功能完整 (播放控制、进度、音量、播放列表)
- ✅ 支持本地音乐库管理
- ⚠️ 需要部署 xiaomusic 服务端

**直连模式:**
- ✅ 无需服务端,仅需小米账号
- ✅ 支持音乐搜索和播放
- ⚠️ 受小米 IoT API 限制,不支持进度查询和音量控制

**模式切换实现:**
1. `playbackModeProvider` 保存当前选择的模式
2. `PlaybackProvider._initializeStrategy()` 根据模式创建对应策略
3. 配置通过 `SharedPreferences` 持久化

### 路由管理

使用 **GoRouter** 进行路由管理,配置在 `lib/app_router.dart`。

**主要路由:**
- `/` - 首页 (通过 AuthWrapper 自动跳转)
- `/mode_selection` - 播放模式选择页
- `/direct_login` - 直连模式登录页
- `/settings` - 设置页面
- `/now-playing` - 正在播放页面

## 代码规范

### 导入顺序

```dart
// 1. Flutter SDK
import 'package:flutter/material.dart';

// 2. 第三方包 (按字母顺序)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 3. 项目内部 (相对路径)
import '../models/music.dart';
import '../providers/playback_provider.dart';
```

### 命名规范

- **Provider**: `xxxProvider` (例: `playbackProvider`)
- **Notifier**: `XxxNotifier` (例: `PlaybackNotifier`)
- **State**: `XxxState` (例: `PlaybackState`)
- **Page**: `XxxPage` (例: `NowPlayingPage`)
- **Service**: `XxxService` (例: `MiIoTService`)
- **Strategy**: `XxxPlaybackStrategy` (例: `RemotePlaybackStrategy`)

### 日志规范

使用 emoji 前缀标识日志类型:

```dart
debugPrint('✅ [模块] 成功信息');
debugPrint('⚠️ [模块] 警告信息');
debugPrint('❌ [模块] 错误信息');
debugPrint('🔧 [模块] 调试信息');
debugPrint('📡 [模块] 网络请求');
```

### 状态管理模式

所有 Provider 使用 `StateNotifier` 模式:

```dart
// 1. 定义 State 类 (使用 sealed class 确保类型安全)
sealed class XxxState {}
class XxxInitial extends XxxState {}
class XxxLoading extends XxxState {}
class XxxSuccess extends XxxState {}
class XxxError extends XxxState {}

// 2. 定义 Notifier
class XxxNotifier extends StateNotifier<XxxState> {
  XxxNotifier() : super(XxxInitial());
}

// 3. 定义 Provider
final xxxProvider = StateNotifierProvider<XxxNotifier, XxxState>((ref) {
  return XxxNotifier();
});
```

## 重要设计模式

### 1. 策略模式 (Strategy Pattern)

**用途**: 播放控制支持多种策略

**实现位置**: `lib/data/services/playback_strategy.dart`

**如何扩展**:
1. 创建新策略类实现 `PlaybackStrategy` 接口
2. 在 `PlaybackProvider._initializeStrategy()` 中添加策略选择逻辑
3. 更新 `PlaybackMode` 枚举 (如需新模式)

### 2. Provider 依赖注入

**用途**: 管理依赖关系和状态共享

**核心文件**: `lib/presentation/providers/`

**注意事项**:
- 使用 `ref.read()` 读取一次性值
- 使用 `ref.watch()` 监听状态变化
- 避免循环依赖

### 3. 配置持久化

**使用 SharedPreferences 保存配置:**

```dart
// 保存
final prefs = await SharedPreferences.getInstance();
await prefs.setString('key', 'value');

// 读取
final value = prefs.getString('key');
```

**已持久化的配置:**
- 播放模式选择 (`playback_mode`)
- 直连模式账号密码 (`direct_mode_account`, `direct_mode_password`)
- xiaomusic 服务器配置 (在 `authProvider` 中)
- 设备选择 (在 `deviceProvider` 中)

## 小米 IoT API 说明

### 登录流程

```
1. GET https://account.xiaomi.com/pass/serviceLogin?sid=micoapi
   → 获取 _sign

2. POST https://account.xiaomi.com/pass/serviceLoginAuth2
   Body: {user, hash(MD5), sid, _sign}
   → 获取 location URL

3. GET location URL
   → 从 Cookie 获取 serviceToken 和 userId
```

### 播放音乐

```
POST https://api.mina.mi.com/remote/ubus
Query: ?deviceId=xxx&message=player_play_url&path=mediaplayer
Headers: Cookie: serviceToken=xxx; userId=xxx
Body: {"url": "音乐URL"}
```

**实现位置**: `lib/data/services/mi_iot_service.dart`

## 依赖说明

### 核心依赖

- `flutter_riverpod: ^2.4.9` - 状态管理
- `dio: ^5.4.0` - HTTP 客户端
- `go_router: ^12.1.3` - 路由管理
- `just_audio: ^0.9.36` - 音频播放
- `audio_service: ^0.18.12` - 后台音频服务
- `shared_preferences: ^2.2.2` - 本地存储
- `cached_network_image: ^3.3.0` - 图片缓存

### 开发依赖

- `riverpod_generator: ^2.3.9` - Provider 代码生成
- `json_serializable: ^6.7.1` - JSON 序列化
- `build_runner: ^2.4.7` - 代码生成工具
- `flutter_lints: ^5.0.0` - 代码规范检查

## 关键文件说明

### 服务层 (lib/data/services/)

- `mi_iot_service.dart` - 小米 IoT API 封装
- `music_api_service.dart` - xiaomusic API 封装
- `native_music_search_service.dart` - 本地音乐扫描
- `album_cover_service.dart` - 专辑封面获取

### Provider 层 (lib/presentation/providers/)

- `playback_provider.dart` - 播放控制总控制器 (⭐ 核心)
- `playback_mode_helper.dart` - 播放模式辅助工具
- `direct_mode_provider.dart` - 直连模式状态管理
- `music_search_provider.dart` - 音乐搜索
- `initialization_provider.dart` - 应用初始化

### 页面层 (lib/presentation/pages/)

- `playback_mode_selection_page.dart` - 模式选择页
- `direct_mode_login_page.dart` - 直连模式登录页
- `now_playing_page.dart` - 正在播放页
- `music_search_page.dart` - 音乐搜索页
- `control_panel_page.dart` - 控制面板页

## 调试技巧

### 1. 查看 Provider 状态

在 `ProviderScope` 中添加 `observers`:

```dart
ProviderScope(
  observers: [_ProviderLogger()],
  child: MyApp(),
);

class _ProviderLogger extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    debugPrint('🔧 [Provider] ${provider.name ?? provider.runtimeType} updated');
  }
}
```

### 2. 网络请求调试

在 `DioClient` 中已配置拦截器,会自动打印请求和响应。

查看位置: `lib/presentation/providers/dio_provider.dart`

### 3. 播放状态调试

在 `PlaybackProvider` 中大量使用 `debugPrint`,运行时可直接查看控制台输出。

## 常见问题

### Q1: 如何添加新的播放模式?

1. 在 `PlaybackMode` 枚举中添加新模式
2. 创建新的策略类实现 `PlaybackStrategy` 接口
3. 在 `PlaybackProvider._initializeStrategy()` 中添加策略选择
4. 在模式选择页面添加对应入口

### Q2: 如何修改播放控制逻辑?

修改 `PlaybackProvider` 中的方法,它会自动调用当前策略的对应方法。

### Q3: 直连模式为什么不支持进度查询?

小米 IoT Cloud API 不提供播放状态查询接口,只能发送播放指令,无法获取实时进度。

### Q4: 如何处理不同模式的功能差异?

在 UI 层检查 `playbackModeProvider` 和 `state.isLocalMode`,根据模式动态显示/隐藏功能。

例如:
```dart
final mode = ref.watch(playbackModeProvider);
if (mode == PlaybackMode.miIoTDirect) {
  // 直连模式 - 隐藏进度条
} else {
  // 其他模式 - 显示进度条
}
```

## 版本发布流程

1. 更新版本号 (使用 `build_release.sh` 自动更新)
2. 运行构建脚本: `./build_release.sh`
3. 测试构建产物
4. 创建 Git tag: `git tag v2.x.x && git push --tags`
5. 在 GitHub 创建 Release,上传构建产物
6. 保存 `build/symbols/` 用于崩溃分析

## 参考文档

- `ARCHITECTURE.md` - 详细架构设计文档
- `INTEGRATION_GUIDE.md` - 双模式集成指南
- `TODO.md` - 开发任务清单
- `DEVLOG.md` - 开发日志
- `README.md` - 项目说明和用户指南

---

## 关联项目: xiaomusic

**重要**: HMusic 的直连模式实现参考了 xiaomusic 项目及其依赖库 miservice-fork。

### 项目关系

```
HMusic (Flutter 客户端)
    ├── xiaomusic 模式: 调用 xiaomusic 服务端 API
    └── 直连模式: 参考 miservice-fork 实现，直接调用小米 IoT API

xiaomusic (Python 服务端) - /Users/pchu/PycharmProjects/xiaomusic
    └── 依赖 miservice-fork 库与小米 IoT API 交互
        └── GitHub: https://github.com/yihong0618/MiService
```

### xiaomusic 项目位置

**本地路径**: `/Users/pchu/PycharmProjects/xiaomusic`

**核心文件**:
- `xiaomusic/xiaomusic.py` - 主逻辑，包含播放控制实现
- `xiaomusic/const.py` - 常量定义，包含设备型号列表

### miservice-fork 关键实现参考

**源码位置**: https://github.com/yihong0618/MiService/blob/main/miservice/minaservice.py

**播放音乐的两种 API**:

1. **`player_play_url`** (简单播放):
```python
# 适用于大多数设备
await ubus_request(deviceId, "player_play_url", "mediaplayer", {
    "url": url,
    "type": 2,  # type=2 是普通类型
    "media": "app_ios"
})
```

2. **`player_play_music`** (完整播放):
```python
# 适用于特定设备 (X08C, X08E, LX05 等)
# ⚠️ 关键点: audio_type 的设置
audio_type = ""  # type=2 时为空字符串！
if _type == 1:
    audio_type = "MUSIC"  # 只有 type=1 时才设置为 "MUSIC"

music = {
    "payload": {
        "audio_type": audio_type,  # 不要错误地设置为 "MUSIC"！
        "audio_items": [...],
        ...
    }
}
await ubus_request(deviceId, "player_play_music", "mediaplayer", {
    "startaudioid": audio_id,
    "music": json.dumps(music)
})
```

**需要使用 `player_play_music` API 的设备型号**:
```python
_USE_PLAY_MUSIC_API = [
    "LX04", "LX05", "L05B", "L05C", "L06", "L06A",
    "X08A", "X10A", "X08C", "X08E", "X8F"
]
```

### 已知问题与解决方案

#### 问题: 音箱有反应但不响

**原因**: `audio_type` 设置错误

**错误实现**:
```dart
'audio_type': 'MUSIC',  // ❌ 错误！
```

**正确实现**:
```dart
'audio_type': '',  // ✅ 正确！type=2 时应为空字符串
```

**修复位置**: `lib/data/services/mi_iot_service.dart:330`

### 小米 IoT API 详细说明

**API 端点**: `https://api2.mina.mi.com/remote/ubus`

**请求格式**:
```dart
POST /remote/ubus
Content-Type: application/x-www-form-urlencoded
Cookie: serviceToken=xxx; userId=xxx

Body (form-urlencoded):
- deviceId: 设备ID
- method: API方法名 (player_play_url / player_play_music / player_play_operation)
- path: mediaplayer
- message: JSON字符串 (必须是字符串，不是对象！)
- requestId: app_ios_xxx
```

**注意事项**:
- `message` 参数必须是 JSON 字符串，不是 JSON 对象
- `player_play_music` 的 `music` 字段需要二次 JSON 编码
- URL 必须是音箱能访问的公网地址

