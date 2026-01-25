# HMusic 双模式开发任务清单

> 本文档记录HMusic双模式功能的开发进度和待办事项
>
> **目标**: 让HMusic同时支持xiaomusic服务端模式和小米IoT直连模式，服务更多用户

## 📊 总体进度

- [x] 架构设计完成
- [x] 核心代码编写完成
- [ ] 集成到现有项目（进行中）
- [ ] 测试验证
- [ ] 文档完善
- [ ] 发布新版本

---

## ✅ 已完成的工作

### 1. 核心服务层 (100%)

#### ✅ 小米IoT直连服务 (`mi_iot_service.dart`)
- [x] 小米账号登录实现
- [x] 设备列表获取
- [x] 播放音乐 API
- [x] 暂停/继续/停止控制
- [x] Cookie认证管理
- [x] 错误处理和日志

**文件位置**: `lib/data/services/mi_iot_service.dart`

**核心功能**:
```dart
// 登录
Future<bool> login(String account, String password)

// 获取设备
Future<List<MiDevice>> getDevices()

// 播放音乐
Future<bool> playMusic({
  required String deviceId,
  required String musicUrl,
  bool compatMode = false,
})

// 控制
Future<bool> pause(String deviceId)
Future<bool> resume(String deviceId)
Future<bool> stop(String deviceId)
```

#### ✅ 直连播放策略 (`mi_iot_direct_playback_strategy.dart`)
- [x] 实现 `PlaybackStrategy` 接口（符合现有架构）
- [x] 播放音乐功能
- [x] 暂停/继续功能
- [x] 通知栏控制集成
- [x] AudioHandler 集成
- [x] 状态管理和回调

**文件位置**: `lib/data/services/mi_iot_direct_playback_strategy.dart`

**已实现接口**:
```dart
✅ Future<void> playMusic({required String musicName, String? url, ...})
✅ Future<void> play()
✅ Future<void> pause()
✅ Future<PlayingMusic?> getCurrentStatus()
⚠️ Future<void> next() // 暂不支持
⚠️ Future<void> previous() // 暂不支持
⚠️ Future<void> seekTo(int seconds) // 暂不支持
⚠️ Future<void> setVolume(int volume) // 暂不支持
```

### 2. Provider层 (100%)

#### ✅ 直连模式配置管理 (`direct_mode_provider.dart`)
- [x] `DirectModeNotifier` - 管理直连登录状态
- [x] `PlaybackModeNotifier` - 管理模式选择
- [x] 自动加载保存的凭证
- [x] 静默登录功能
- [x] 设备列表刷新
- [x] 配置持久化（SharedPreferences）

**文件位置**: `lib/presentation/providers/direct_mode_provider.dart`

**状态类型**:
```dart
DirectModeInitial - 未登录
DirectModeLoading - 登录中
DirectModeAuthenticated - 已登录（包含设备列表）
DirectModeError - 登录失败
```

**Provider定义**:
```dart
final directModeProvider = StateNotifierProvider<DirectModeNotifier, DirectModeState>
final playbackModeProvider = StateNotifierProvider<PlaybackModeNotifier, PlaybackMode>
```

### 3. UI层 (100%)

#### ✅ 模式选择页面 (`playback_mode_selection_page.dart`)
- [x] 精美的卡片式布局
- [x] xiaomusic模式卡片
- [x] 直连模式卡片
- [x] 功能特性说明
- [x] 导航跳转

**文件位置**: `lib/presentation/pages/playback_mode_selection_page.dart`

#### ✅ 直连登录页面 (`direct_mode_login_page.dart`)
- [x] 表单验证
- [x] 密码显示/隐藏
- [x] 加载状态显示
- [x] 错误提示
- [x] 登录成功自动跳转
- [x] 模式切换按钮

**文件位置**: `lib/presentation/pages/direct_mode_login_page.dart`

### 4. 文档 (100%)

#### ✅ 集成指南 (`INTEGRATION_GUIDE.md`)
- [x] 完整集成步骤
- [x] 代码示例
- [x] 架构图
- [x] 注意事项
- [x] 测试建议

**文件位置**: `INTEGRATION_GUIDE.md`

---

## 🚧 进行中的工作

### 1. 集成到现有项目 (30%)

需要修改以下文件来完成集成：

#### 📝 `lib/app_router.dart`
**状态**: ⏳ 待修改

**需要做的**:
```dart
// 在 routes 中添加两个新路由
GoRoute(
  path: '/mode_selection',
  builder: (context, state) => const PlaybackModeSelectionPage(),
),
GoRoute(
  path: '/direct_login',
  builder: (context, state) => const DirectModeLoginPage(),
),
```

**原因**: 让新页面可以通过路由访问

---

#### 📝 `lib/presentation/pages/login_page.dart`
**状态**: ⏳ 待修改

**需要做的**:
在登录表单底部添加模式选择入口：

```dart
// 在 ElevatedButton（登录按钮）下方添加
const SizedBox(height: 16),

TextButton(
  onPressed: () {
    context.go('/mode_selection');
  },
  child: const Text('选择其他登录方式'),
),
```

**位置**: 大约在第300-350行之间（登录按钮附近）

**原因**: 让用户可以选择使用哪种模式

---

#### 📝 `lib/presentation/providers/playback_provider.dart`
**状态**: ⏳ 待修改（最重要！）

**需要做的**:

1. **添加导入**:
```dart
import 'direct_mode_provider.dart';
import '../../data/services/mi_iot_direct_playback_strategy.dart';
```

2. **在 `PlaybackNotifier` 类中添加字段**:
```dart
class PlaybackNotifier extends StateNotifier<PlaybackState> {
  // ... 现有代码 ...

  PlaybackStrategy? _currentStrategy; // 当前使用的策略

  // ... 其他代码 ...
}
```

3. **添加策略初始化方法**:
```dart
/// 根据当前模式初始化播放策略
Future<void> _initializeStrategy() async {
  final playbackMode = ref.read(playbackModeProvider);

  if (playbackMode == PlaybackMode.miIoTDirect) {
    // ========== 直连模式 ==========
    final directState = ref.read(directModeProvider);

    if (directState is! DirectModeAuthenticated) {
      debugPrint('⚠️ [Playback] 直连模式未登录');
      return;
    }

    if (directState.devices.isEmpty) {
      debugPrint('⚠️ [Playback] 没有可用设备');
      return;
    }

    // 使用第一个设备（或让用户选择）
    final device = directState.devices.first;

    // 获取 AudioHandler
    final audioHandler = ref.read(audioHandlerProvider);

    // 创建直连策略
    _currentStrategy = MiIoTDirectPlaybackStrategy(
      miService: directState.miService,
      deviceId: device.deviceId,
      deviceName: device.name,
      audioHandler: audioHandler,
    );

    // 设置状态变化回调
    (_currentStrategy as MiIoTDirectPlaybackStrategy).onStatusChanged = () {
      _refreshStatus();
    };

    debugPrint('✅ [Playback] 直连模式策略已初始化');

  } else {
    // ========== xiaomusic模式（保持原有逻辑）==========
    final device = ref.read(deviceProvider);
    if (device == null) {
      debugPrint('⚠️ [Playback] 未选择设备');
      return;
    }

    final dioClient = ref.read(dioClientProvider);
    final apiService = MusicApiService(dioClient);
    final audioHandler = ref.read(audioHandlerProvider);

    _currentStrategy = RemotePlaybackStrategy(
      apiService: apiService,
      deviceId: device.did,
      deviceName: device.name,
      audioHandler: audioHandler,
    );

    (_currentStrategy as RemotePlaybackStrategy).onStatusChanged = () {
      _refreshStatus();
    };

    debugPrint('✅ [Playback] xiaomusic模式策略已初始化');
  }
}
```

4. **修改播放音乐方法**:
```dart
/// 播放在线音乐
Future<void> playOnlineMusic(OnlineMusicResult music) async {
  // 确保策略已初始化
  if (_currentStrategy == null) {
    await _initializeStrategy();
  }

  if (_currentStrategy == null) {
    state = state.copyWith(error: '播放器未初始化');
    return;
  }

  state = state.copyWith(isLoading: true, error: null);

  try {
    // 调用策略播放
    await _currentStrategy!.playMusic(
      musicName: '${music.title} - ${music.author}',
      url: music.url,
      platform: music.platform,
      songId: music.songId,
    );

    // 更新状态
    await _refreshStatus();

  } catch (e) {
    debugPrint('❌ [Playback] 播放失败: $e');
    state = state.copyWith(
      isLoading: false,
      error: '播放失败: $e',
    );
  }
}
```

5. **修改控制方法**:
```dart
/// 播放/继续
Future<void> play() async {
  if (_currentStrategy == null) {
    await _initializeStrategy();
  }
  await _currentStrategy?.play();
  await _refreshStatus();
}

/// 暂停
Future<void> pause() async {
  await _currentStrategy?.pause();
  await _refreshStatus();
}

/// 上一曲
Future<void> previous() async {
  await _currentStrategy?.previous();
  await _refreshStatus();
}

/// 下一曲
Future<void> next() async {
  await _currentStrategy?.next();
  await _refreshStatus();
}
```

**为什么要这样改**:
- 让PlaybackProvider支持两种策略
- 根据用户选择的模式自动使用对应的策略
- 保持原有xiaomusic模式的功能不变

---

#### 📝 `lib/presentation/providers/initialization_provider.dart`
**状态**: ⏳ 待修改

**需要做的**:
```dart
import 'direct_mode_provider.dart';

final initializationProvider = FutureProvider<void>((ref) async {
  // 检查播放模式
  final playbackMode = ref.watch(playbackModeProvider);

  if (playbackMode == PlaybackMode.miIoTDirect) {
    // 直连模式 - 会自动尝试登录（如果有保存的凭证）
    debugPrint('🔧 [Init] 初始化直连模式');
    ref.watch(directModeProvider);
  } else {
    // xiaomusic模式（保持原有逻辑）
    debugPrint('🔧 [Init] 初始化xiaomusic模式');
    ref.watch(authProvider);
  }

  // 其他初始化逻辑...
});
```

**原因**: 让APP启动时根据模式进行相应的初始化

---

## 📋 待办事项（按优先级）

### 🔥 高优先级（必须完成）

- [ ] **修改 `app_router.dart`**
  - 添加两个新路由
  - 预计时间: 2分钟

- [ ] **修改 `login_page.dart`**
  - 添加模式选择入口
  - 预计时间: 2分钟

- [ ] **修改 `playback_provider.dart`** ⭐ 最重要
  - 实现策略模式支持
  - 预计时间: 15分钟

- [ ] **修改 `initialization_provider.dart`**
  - 添加模式检查
  - 预计时间: 3分钟

- [ ] **基础功能测试**
  - 测试直连模式登录
  - 测试播放音乐
  - 测试模式切换
  - 预计时间: 10分钟

### 🟡 中优先级（建议完成）

- [ ] **添加设置页面中的模式切换**
  - 在设置页面显示当前模式
  - 添加切换入口
  - 显示账号信息
  - 预计时间: 10分钟

- [ ] **优化直连模式功能**
  - 添加设备选择功能（如果有多个设备）
  - 添加音量控制支持
  - 预计时间: 20分钟

- [ ] **完善错误处理**
  - 网络错误提示
  - 登录失败引导
  - 预计时间: 10分钟

### 🟢 低优先级（可选）

- [ ] **实现直连模式的队列管理**
  - 上一曲/下一曲支持
  - 播放列表管理
  - 预计时间: 30分钟

- [ ] **添加直连模式的高级功能**
  - 进度拖动支持
  - 定时关机
  - 预计时间: 30分钟

- [ ] **直连模式播放手机本地音乐** 🆕
  - **原理**: 在手机上启动 HTTP 服务器，将本地文件暴露为 URL，让音箱播放
  - **实现方案**:
    1. 扩展 `AudioProxyServer`（`lib/data/services/audio_proxy_server.dart`）
       - 添加 `/local` 端点来服务本地文件
       - URL 格式: `http://192.168.x.x:8090/local?path=/storage/emulated/0/Music/song.mp3`
    2. 使用已有的 `NativeMusicSearchService` 扫描本地音乐
    3. 修改 `MiIoTDirectPlaybackStrategy.playMusic()` 支持本地文件路径
       - 检测是否为本地文件路径
       - 如果是，启动代理服务器并转换为 HTTP URL
       - 调用小米 IoT API 播放该 URL
  - **限制条件**:
    - ⚠️ 手机和音箱必须在同一 WiFi 网络
    - ⚠️ App 需保持前台/后台运行（服务器才能响应）
    - ⚠️ 需要存储权限访问本地文件
  - **现有基础**: `AudioProxyServer` 已有 HTTP 服务器、获取本机 IP、流式传输功能
  - **难点**: 后台保活（需要 foreground service）
  - 预计时间: 2-4小时

- [ ] **UI优化**
  - 添加加载动画
  - 优化错误提示样式
  - 预计时间: 15分钟

---

## 🧪 测试清单

### 基础功能测试

- [ ] **直连模式登录**
  - [ ] 输入正确的小米账号密码 → 登录成功
  - [ ] 输入错误的账号密码 → 显示错误提示
  - [ ] 检查设备列表是否正确显示
  - [ ] 退出登录 → 凭证被清除

- [ ] **播放功能**
  - [ ] 搜索音乐 → 点击播放 → 小爱音箱开始播放
  - [ ] 暂停 → 音箱暂停
  - [ ] 继续播放 → 音箱继续
  - [ ] 通知栏控制 → 正常工作

- [ ] **模式切换**
  - [ ] 从xiaomusic切换到直连 → 配置正确加载
  - [ ] 从直连切换到xiaomusic → 配置正确加载
  - [ ] 重启APP → 上次的模式被记住

### 兼容性测试

- [ ] **xiaomusic模式功能**
  - [ ] 所有原有功能正常工作
  - [ ] 本地音乐播放正常
  - [ ] 歌单功能正常

- [ ] **配置持久化**
  - [ ] 直连账号密码保存
  - [ ] 模式选择保存
  - [ ] 设备选择保存

---

## 🐛 已知问题

### 待解决

1. **直连模式功能限制**
   - 问题: 无法获取播放进度
   - 原因: 小米IoT API限制
   - 解决方案: 显示"直连模式不支持进度显示"

2. **直连模式无上一曲/下一曲**
   - 问题: 小米IoT API不支持
   - 原因: 需要APP维护播放队列
   - 解决方案: 后续版本实现客户端队列

### 已解决

- ✅ 架构冲突问题 → 使用现有PlaybackStrategy接口
- ✅ Provider集成问题 → 创建独立的directModeProvider
- ✅ 路由配置问题 → 使用GoRouter

---

## 📝 开发注意事项

### 代码规范

1. **导入顺序**:
   ```dart
   // Flutter SDK
   import 'package:flutter/material.dart';

   // 第三方包
   import 'package:flutter_riverpod/flutter_riverpod.dart';

   // 项目内部
   import '../providers/xxx.dart';
   ```

2. **命名规范**:
   - Provider: `xxxProvider`
   - Notifier: `XxxNotifier`
   - State: `XxxState`
   - Page: `XxxPage`

3. **日志规范**:
   ```dart
   debugPrint('✅ [模块] 成功信息');
   debugPrint('⚠️ [模块] 警告信息');
   debugPrint('❌ [模块] 错误信息');
   debugPrint('🔧 [模块] 调试信息');
   ```

### Git提交规范

建议的commit message格式:
```
feat: 添加直连模式登录功能
fix: 修复播放策略切换问题
docs: 更新集成指南文档
refactor: 重构PlaybackProvider策略选择
test: 添加直连模式测试用例
```

---

## 📚 相关文档

- `INTEGRATION_GUIDE.md` - 详细集成指南
- `ARCHITECTURE.md` - 架构设计文档（待创建）
- `DEVLOG.md` - 开发日志（待创建）
- `README.md` - 项目说明（需要更新）

---

## 🎯 下一步计划

### 近期 (本周)
1. 完成代码集成
2. 完成基础测试
3. 修复发现的问题

### 中期 (下周)
1. 优化用户体验
2. 完善文档
3. 添加设置页面功能

### 远期 (后续版本)
1. 实现直连模式高级功能
2. 优化性能
3. 添加更多音箱型号支持

---

**最后更新**: 2025-11-20
**维护者**: 哈雷酱 (￣▽￣)／
**状态**: 🚧 开发中
