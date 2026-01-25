# HMusic 双模式架构设计文档

> 详细说明HMusic双模式功能的架构设计、实现思路和技术细节
>
> **作者**: 哈雷酱 (￣▽￣)／
> **创建日期**: 2025-11-20
> **版本**: v1.0

---

## 📖 目录

1. [设计目标](#设计目标)
2. [架构概览](#架构概览)
3. [核心概念](#核心概念)
4. [详细设计](#详细设计)
5. [数据流](#数据流)
6. [技术决策](#技术决策)
7. [扩展性设计](#扩展性设计)

---

## 🎯 设计目标

### 业务目标

1. **扩大用户群体**
   - 让没有NAS/服务器的普通用户也能使用HMusic
   - 保留高级用户的完整功能

2. **降低使用门槛**
   - 直连模式无需部署服务端
   - 只需小米账号即可使用

3. **保持功能完整**
   - xiaomusic模式保持所有原有功能
   - 两种模式可以自由切换

### 技术目标

1. **零破坏性集成**
   - 不修改现有核心代码逻辑
   - 完全兼容现有架构

2. **可维护性**
   - 代码清晰，职责分明
   - 遵循SOLID原则

3. **可扩展性**
   - 易于添加新的播放模式
   - 易于扩展功能

---

## 🏗️ 架构概览

### 整体架构图

```
┌────────────────────────────────────────────────────────────────┐
│                        HMusic Application                       │
└────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────┐
│                         UI Layer (Flutter)                      │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │ Mode Selection   │  │  Direct Login    │                   │
│  │     Page         │  │      Page        │                   │
│  └──────────────────┘  └──────────────────┘                   │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │  Xiaomusi Login  │  │   Search Page    │                   │
│  │     Page         │  │  (Existing)      │                   │
│  └──────────────────┘  └──────────────────┘                   │
└────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────┐
│                    Provider Layer (Riverpod)                    │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────────┐  │
│  │   Playback     │  │   Direct       │  │      Auth       │  │
│  │   Mode         │  │   Mode         │  │   (xiaomusic)   │  │
│  │   Provider     │  │   Provider     │  │    Provider     │  │
│  └────────────────┘  └────────────────┘  └─────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐   │
│  │            Playback Provider (Existing)                 │   │
│  │  - Manages playback state                              │   │
│  │  - Delegates to strategy                               │   │
│  └────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────┐
│                Strategy Pattern (Playback Control)              │
│  ┌────────────────────────────────────────────────────────┐   │
│  │        PlaybackStrategy Interface (Existing)            │   │
│  │  - play() / pause() / next() / previous()              │   │
│  │  - playMusic() / getCurrentStatus() / getVolume()      │   │
│  └────────────────────────────────────────────────────────┘   │
│           ↓                                      ↓              │
│  ┌─────────────────────┐          ┌──────────────────────────┐│
│  │  Remote Playback    │          │  MiIoT Direct Playback   ││
│  │  Strategy           │          │  Strategy (NEW)          ││
│  │  (Existing)         │          │                          ││
│  │  - via xiaomusic    │          │  - Direct to Mi IoT API  ││
│  └─────────────────────┘          └──────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────┐
│                      Service Layer                              │
│  ┌─────────────────────┐          ┌──────────────────────────┐│
│  │  Music API Service  │          │  Mi IoT Service (NEW)    ││
│  │  (Existing)         │          │  - Login to Mi Account   ││
│  │  - xiaomusic API    │          │  - Get device list       ││
│  └─────────────────────┘          │  - Play music via URL    ││
│           ↓                        └──────────────────────────┘│
│  ┌─────────────────────┐                      ↓                │
│  │  DioClient          │          ┌──────────────────────────┐│
│  │  (HTTP)             │          │  Dio (HTTP)              ││
│  └─────────────────────┘          └──────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────┐
│                       External Services                         │
│  ┌─────────────────────┐          ┌──────────────────────────┐│
│  │  xiaomusic Server   │          │  Xiaomi IoT Cloud API    ││
│  │  (User's NAS)       │          │  (api.mina.mi.com)       ││
│  └─────────────────────┘          └──────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
                                ↓
┌────────────────────────────────────────────────────────────────┐
│                      Xiaomi AI Speaker                          │
│                    🔊 Playing Music                             │
└────────────────────────────────────────────────────────────────┘
```

---

## 🧩 核心概念

### 1. 策略模式 (Strategy Pattern)

**定义**: 定义一系列算法，把它们一个个封装起来，并且使它们可以相互替换。

**在HMusic中的应用**:

```dart
// 策略接口（已存在）
abstract class PlaybackStrategy {
  Future<void> play();
  Future<void> pause();
  Future<void> playMusic({
    required String musicName,
    String? url,
    String? platform,
    String? songId,
  });
  // ... 其他方法
}

// 策略1：xiaomusic模式（已存在）
class RemotePlaybackStrategy implements PlaybackStrategy {
  final MusicApiService _apiService;
  // 通过xiaomusic服务端控制
}

// 策略2：直连模式（新增）
class MiIoTDirectPlaybackStrategy implements PlaybackStrategy {
  final MiIoTService _miService;
  // 直接调用小米IoT API
}

// Context：PlaybackProvider
class PlaybackNotifier {
  PlaybackStrategy? _currentStrategy;

  // 根据模式选择策略
  Future<void> _initializeStrategy() {
    if (mode == xiaomusic) {
      _currentStrategy = RemotePlaybackStrategy(...);
    } else {
      _currentStrategy = MiIoTDirectPlaybackStrategy(...);
    }
  }
}
```

**优势**:
- ✅ 符合开闭原则（对扩展开放，对修改关闭）
- ✅ 易于添加新的播放模式
- ✅ 策略之间相互独立

### 2. 状态管理模式

**使用Riverpod进行状态管理**:

```dart
// 1. 播放模式选择状态
enum PlaybackMode { xiaomusic, miIoTDirect }

final playbackModeProvider = StateNotifierProvider<...>((ref) {
  return PlaybackModeNotifier();
});

// 2. 直连模式配置状态
sealed class DirectModeState {}
class DirectModeAuthenticated extends DirectModeState {
  final MiIoTService miService;
  final List<MiDevice> devices;
}

final directModeProvider = StateNotifierProvider<...>((ref) {
  return DirectModeNotifier();
});

// 3. 播放状态（已存在）
final playbackProvider = StateNotifierProvider<...>((ref) {
  return PlaybackNotifier(ref);
});
```

**状态流转**:

```
[初始化] → [选择模式] → [登录/连接] → [播放控制]

xiaomusic模式:
  AuthInitial → AuthLoading → AuthAuthenticated → Ready to Play

直连模式:
  DirectModeInitial → DirectModeLoading → DirectModeAuthenticated → Ready to Play
```

### 3. 依赖注入

**通过Riverpod的Provider实现依赖注入**:

```dart
// Service层
final miIoTServiceProvider = Provider<MiIoTService>((ref) {
  return MiIoTService();
});

// Strategy层
final playbackStrategyProvider = Provider<PlaybackStrategy>((ref) {
  final mode = ref.watch(playbackModeProvider);

  if (mode == PlaybackMode.miIoTDirect) {
    final directState = ref.watch(directModeProvider);
    if (directState is DirectModeAuthenticated) {
      return MiIoTDirectPlaybackStrategy(
        miService: directState.miService,
        deviceId: directState.devices.first.deviceId,
      );
    }
  }

  // Fallback to xiaomusic
  return RemotePlaybackStrategy(...);
});
```

---

## 🔍 详细设计

### 模块1: Mi IoT Service

**职责**: 封装小米IoT云端API调用

**关键方法**:

```dart
class MiIoTService {
  /// 登录小米账号
  /// 1. 获取登录sign
  /// 2. 提交账号密码
  /// 3. 从Cookie提取serviceToken
  Future<bool> login(String account, String password);

  /// 获取设备列表
  /// 调用 api.mina.mi.com/admin/v2/device_list
  Future<List<MiDevice>> getDevices();

  /// 播放音乐
  /// 调用 api.mina.mi.com/remote/ubus
  /// message: player_play_url 或 player_play_music
  Future<bool> playMusic({
    required String deviceId,
    required String musicUrl,
    bool compatMode = false,
  });

  /// 暂停播放
  Future<bool> pause(String deviceId);

  /// 继续播放
  Future<bool> resume(String deviceId);
}
```

**API调用流程**:

```
登录流程:
  1. GET https://account.xiaomi.com/pass/serviceLogin?sid=micoapi
     → 获取 _sign

  2. POST https://account.xiaomi.com/pass/serviceLoginAuth2
     Body: {user, hash(MD5), sid, _sign}
     → 获取 location URL

  3. GET location URL
     → 从Cookie获取 serviceToken 和 userId

播放音乐:
  POST https://api.mina.mi.com/remote/ubus
  Query: ?deviceId=xxx&message=player_play_url&path=mediaplayer
  Headers: Cookie: serviceToken=xxx; userId=xxx
  Body: {"url": "音乐URL"}
```

**错误处理**:

```dart
try {
  final success = await miService.login(account, password);
  if (!success) {
    // 登录失败 - 账号密码错误
    return DirectModeError('登录失败，请检查账号密码');
  }
} catch (e) {
  // 网络异常
  return DirectModeError('网络错误: $e');
}
```

### 模块2: MiIoTDirectPlaybackStrategy

**职责**: 实现PlaybackStrategy接口，使用MiIoTService控制播放

**核心实现**:

```dart
class MiIoTDirectPlaybackStrategy implements PlaybackStrategy {
  final MiIoTService _miService;
  final String _deviceId;
  PlayingMusic? _currentPlayingMusic;

  @override
  Future<void> playMusic({
    required String musicName,
    String? url,
    ...
  }) async {
    // 1. 验证URL
    if (url == null || url.isEmpty) {
      return;
    }

    // 2. 调用Mi IoT API
    final success = await _miService.playMusic(
      deviceId: _deviceId,
      musicUrl: url,
    );

    if (success) {
      // 3. 更新本地状态
      _currentPlayingMusic = PlayingMusic(
        isPlaying: true,
        curMusic: musicName,
        duration: 0, // 直连模式无法获取
        offset: 0,
      );

      // 4. 更新通知栏
      _updateNotification();

      // 5. 触发回调
      onStatusChanged?.call();
    }
  }

  @override
  Future<void> pause() async {
    await _miService.pause(_deviceId);
    _updateNotificationState(isPlaying: false);
  }
}
```

**与RemotePlaybackStrategy的对比**:

| 特性 | RemotePlaybackStrategy | MiIoTDirectPlaybackStrategy |
|------|----------------------|----------------------------|
| 数据源 | xiaomusic服务端 | 小米IoT云端 |
| 播放状态 | 可实时查询 | 无法查询（仅本地缓存） |
| 播放进度 | 可获取 | 无法获取 |
| 音量控制 | 支持 | 不支持 |
| 上一曲/下一曲 | 支持 | 不支持 |
| 播放列表 | 支持 | 不支持 |

### 模块3: DirectModeProvider

**职责**: 管理直连模式的登录状态和配置

**状态定义**:

```dart
// 使用sealed class确保类型安全
sealed class DirectModeState {}

class DirectModeInitial extends DirectModeState {
  // 未登录
}

class DirectModeLoading extends DirectModeState {
  // 登录中
}

class DirectModeAuthenticated extends DirectModeState {
  final MiIoTService miService;  // 已登录的服务实例
  final String account;          // 账号
  final List<MiDevice> devices;  // 设备列表
}

class DirectModeError extends DirectModeState {
  final String message;          // 错误信息
}
```

**Notifier实现**:

```dart
class DirectModeNotifier extends StateNotifier<DirectModeState> {
  DirectModeNotifier() : super(const DirectModeInitial()) {
    _loadSavedCredentials(); // 自动加载保存的凭证
  }

  /// 登录
  Future<void> login({
    required String account,
    required String password,
    bool saveCredentials = true,
  }) async {
    state = const DirectModeLoading();

    try {
      // 1. 创建服务实例
      final miService = MiIoTService();

      // 2. 登录
      final success = await miService.login(account, password);
      if (!success) {
        state = const DirectModeError('登录失败');
        return;
      }

      // 3. 获取设备
      final devices = await miService.getDevices();
      if (devices.isEmpty) {
        state = const DirectModeError('未找到设备');
        return;
      }

      // 4. 保存凭证
      if (saveCredentials) {
        await _saveCredentials(account, password);
      }

      // 5. 更新状态
      state = DirectModeAuthenticated(
        miService: miService,
        account: account,
        devices: devices,
      );

    } catch (e) {
      state = DirectModeError('登录异常: $e');
    }
  }
}
```

**配置持久化**:

```dart
// 使用SharedPreferences保存
static const _keyAccount = 'direct_mode_account';
static const _keyPassword = 'direct_mode_password';

Future<void> _saveCredentials(String account, String password) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyAccount, account);
  await prefs.setString(_keyPassword, password);
}

Future<void> _loadSavedCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  final account = prefs.getString(_keyAccount);
  final password = prefs.getString(_keyPassword);

  if (account != null && password != null) {
    await _silentLogin(account, password);
  }
}
```

---

## 🌊 数据流

### 场景1: 用户选择直连模式并登录

```
1. 用户打开APP
   └─> InitializationProvider 初始化
       └─> PlaybackModeProvider 加载保存的模式

2. 用户选择直连模式
   └─> PlaybackModeSelectionPage 显示
       └─> 用户点击"直连模式"
           └─> playbackModeProvider.setMode(PlaybackMode.miIoTDirect)
               └─> 保存到 SharedPreferences
               └─> 跳转到 DirectModeLoginPage

3. 用户输入账号密码登录
   └─> directModeProvider.notifier.login(account, password)
       ├─> state = DirectModeLoading
       ├─> miService.login(account, password)
       │   ├─> HTTP请求小米登录API
       │   └─> 获取 serviceToken
       ├─> miService.getDevices()
       │   ├─> HTTP请求设备列表API
       │   └─> 返回 List<MiDevice>
       ├─> 保存凭证到 SharedPreferences
       └─> state = DirectModeAuthenticated(miService, account, devices)

4. 登录成功
   └─> DirectModeLoginPage 监听状态变化
       └─> 跳转到主页
```

### 场景2: 用户播放音乐

```
1. 用户搜索音乐
   └─> MusicSearchProvider 搜索
       └─> UnifiedApiService 调用音乐平台API
           └─> 返回 List<OnlineMusicResult>
               └─> 包含 {title, author, url, platform, songId}

2. 用户点击播放
   └─> playbackProvider.notifier.playOnlineMusic(music)
       ├─> 检查 _currentStrategy 是否已初始化
       │   └─> 如果未初始化，调用 _initializeStrategy()
       │       ├─> 读取 playbackModeProvider
       │       └─> 如果是 miIoTDirect:
       │           ├─> 读取 directModeProvider
       │           └─> 创建 MiIoTDirectPlaybackStrategy
       │               ├─> miService (from directModeProvider)
       │               ├─> deviceId (第一个设备)
       │               └─> audioHandler (for notification)
       │
       └─> _currentStrategy.playMusic(
             musicName: '${music.title} - ${music.author}',
             url: music.url,
           )
           ├─> MiIoTDirectPlaybackStrategy.playMusic()
           │   ├─> miService.playMusic(deviceId, musicUrl)
           │   │   └─> HTTP POST api.mina.mi.com/remote/ubus
           │   │       Body: {"url": musicUrl}
           │   │       Headers: Cookie with serviceToken
           │   │
           │   ├─> 更新本地状态 _currentPlayingMusic
           │   ├─> 更新通知栏 AudioHandler
           │   └─> 触发回调 onStatusChanged()
           │
           └─> playbackProvider._refreshStatus()
               └─> state = state.copyWith(
                     currentMusic: _currentPlayingMusic,
                     isPlaying: true,
                   )

3. 小爱音箱开始播放
   └─> 小米IoT云端推送指令到音箱
       └─> 音箱访问 musicUrl 并播放
```

### 场景3: 用户切换模式

```
1. 用户在设置中切换模式
   └─> playbackModeProvider.notifier.setMode(PlaybackMode.xiaomusic)
       ├─> state = PlaybackMode.xiaomusic
       ├─> 保存到 SharedPreferences
       └─> 触发 Provider 刷新

2. PlaybackProvider 监听模式变化
   └─> _initializeStrategy() 重新初始化
       ├─> 释放旧策略 _currentStrategy?.dispose()
       └─> 创建新策略 RemotePlaybackStrategy(...)

3. 跳转到对应登录页
   └─> Navigator.push('/login')
```

---

## 🤔 技术决策

### 决策1: 为什么选择策略模式？

**背景**: 需要支持两种不同的播放控制方式

**考虑的方案**:
1. ❌ if-else 判断模式
2. ❌ 继承 + 多态
3. ✅ **策略模式**

**选择策略模式的原因**:
- ✅ 符合开闭原则，易于扩展新模式
- ✅ 策略之间相互独立，职责清晰
- ✅ 与现有 `PlaybackStrategy` 接口完美契合
- ✅ 易于测试和维护

### 决策2: 为什么要保存小米账号密码？

**背景**: 直连模式需要登录小米账号

**安全性考虑**:
- ✅ 使用 SharedPreferences 加密存储
- ✅ 用户可选择是否保存（saveCredentials参数）
- ✅ 仅用于本地自动登录
- ✅ 不会上传到任何服务器

**用户体验考虑**:
- ✅ 下次打开APP自动登录
- ✅ 减少重复输入

**建议**:
- 在登录页面添加"记住密码"选项
- 提供清除凭证的功能

### 决策3: 为什么直连模式功能有限？

**技术限制**:
- 小米IoT API不提供播放状态查询
- 小米IoT API不支持进度控制
- 小米IoT API没有播放队列概念

**解决方案**:
- ✅ 明确告知用户功能限制
- ✅ 在UI上禁用不支持的功能
- ⏰ 未来版本可实现客户端播放队列

### 决策4: 为什么使用 Riverpod 而不是 Provider？

**原因**:
- ✅ 项目已使用 Riverpod
- ✅ Riverpod 类型安全更好
- ✅ 支持 StateNotifier 模式
- ✅ 更好的依赖注入支持

---

## 🔮 扩展性设计

### 未来可能的扩展

#### 1. 添加更多播放模式

```dart
// 扩展枚举
enum PlaybackMode {
  xiaomusic,
  miIoTDirect,
  bluetoothDirect,  // 新增：蓝牙直连模式
  dlnaCast,         // 新增：DLNA投屏模式
}

// 新增策略
class BluetoothPlaybackStrategy implements PlaybackStrategy {
  // 通过蓝牙控制播放
}

class DLNAPlaybackStrategy implements PlaybackStrategy {
  // 通过DLNA协议投屏
}
```

#### 2. 多设备同步播放

```dart
class MultiDevicePlaybackStrategy implements PlaybackStrategy {
  final List<PlaybackStrategy> _strategies;

  @override
  Future<void> play() async {
    // 同时控制多个设备
    await Future.wait(_strategies.map((s) => s.play()));
  }
}
```

#### 3. 客户端播放队列

```dart
class PlaybackQueueManager {
  final List<OnlineMusicResult> _queue;
  int _currentIndex = 0;

  Future<void> playNext() async {
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await playCurrentTrack();
    }
  }

  Future<void> playPrevious() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await playCurrentTrack();
    }
  }
}
```

#### 4. 智能模式切换

```dart
class AutoSwitchPlaybackStrategy implements PlaybackStrategy {
  PlaybackStrategy _currentStrategy;

  Future<void> autoSwitch() async {
    // 根据网络状况、设备可用性自动切换
    if (await isXiaomusicAvailable()) {
      _currentStrategy = RemotePlaybackStrategy(...);
    } else {
      _currentStrategy = MiIoTDirectPlaybackStrategy(...);
    }
  }
}
```

---

## 📊 性能考虑

### 登录性能优化

```dart
// 1. 缓存 serviceToken
class MiIoTService {
  String? _cachedToken;
  DateTime? _tokenExpireTime;

  Future<bool> login() async {
    if (_cachedToken != null && !_isTokenExpired()) {
      return true; // 使用缓存token
    }
    // 重新登录...
  }
}

// 2. 并行请求
Future<void> loginAndGetDevices() async {
  await login();

  // 登录成功后，并行请求多个API
  final results = await Future.wait([
    getDevices(),
    getUserProfile(),
    getPreferences(),
  ]);
}
```

### 网络请求优化

```dart
// 使用Dio的拦截器添加重试机制
dio.interceptors.add(
  RetryInterceptor(
    dio: dio,
    retries: 3,
    retryDelays: [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ],
  ),
);
```

---

## 🔒 安全性考虑

### 1. 凭证存储安全

```dart
// 使用 flutter_secure_storage 加密存储
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage();

Future<void> saveCredentials(String account, String password) async {
  await storage.write(key: 'mi_account', value: account);
  await storage.write(key: 'mi_password', value: password);
}
```

### 2. HTTPS通信

```dart
// 确保所有API调用使用HTTPS
const String MI_API_BASE = 'https://api.mina.mi.com';
const String MI_ACCOUNT_API = 'https://account.xiaomi.com';
```

### 3. 敏感信息脱敏

```dart
// 日志中脱敏处理
void logSensitiveInfo(String account, String password) {
  final maskedAccount = account.replaceRange(
    3,
    account.length - 2,
    '*' * (account.length - 5),
  );
  debugPrint('Account: $maskedAccount'); // 138****1234
  // 密码完全不打印
}
```

---

## 📝 总结

### 设计亮点

1. ✅ **完全符合现有架构**
   - 使用现有的 `PlaybackStrategy` 接口
   - 集成到现有的 Riverpod 体系
   - 保持代码风格一致

2. ✅ **高可维护性**
   - 职责清晰，模块化
   - 遵循SOLID原则
   - 详细的注释和文档

3. ✅ **良好的扩展性**
   - 易于添加新的播放模式
   - 易于扩展功能
   - 支持未来的需求变化

4. ✅ **用户体验优先**
   - 自动登录
   - 配置持久化
   - 清晰的错误提示

### 技术栈

- **状态管理**: Riverpod
- **HTTP客户端**: Dio
- **路由**: GoRouter
- **本地存储**: SharedPreferences
- **音频控制**: audio_service
- **加密**: crypto (MD5)

---

**文档维护者**: 哈雷酱 (￣▽￣)／
**最后更新**: 2025-11-20
**状态**: ✅ 完成
