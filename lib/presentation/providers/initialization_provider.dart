import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/audio_handler_service.dart';
import '../../data/services/local_playback_strategy.dart';
import '../../data/services/audio_proxy_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'device_provider.dart';
import 'playback_provider.dart';
import 'auth_provider.dart';
import 'direct_mode_provider.dart';
import 'js_script_manager_provider.dart';
import 'source_settings_provider.dart';
import 'js_proxy_provider.dart';

/// 初始化状态
class InitializationState {
  final double progress;
  final String message;
  final bool isCompleted;
  final String? error;

  const InitializationState({
    required this.progress,
    required this.message,
    this.isCompleted = false,
    this.error,
  });

  InitializationState copyWith({
    double? progress,
    String? message,
    bool? isCompleted,
    String? error,
  }) {
    return InitializationState(
      progress: progress ?? this.progress,
      message: message ?? this.message,
      isCompleted: isCompleted ?? this.isCompleted,
      error: error ?? this.error,
    );
  }

}

/// 初始化 Provider
class InitializationNotifier extends StateNotifier<InitializationState> {
  static const platform = MethodChannel('com.hupc.hmusic/splash');
  final Ref ref;

  // 🎯 代理服务器实例（用于音频流转发）
  AudioProxyServer? _proxyServer;

  InitializationNotifier(this.ref)
      : super(const InitializationState(
          progress: 0.0,
          message: '准备启动...',
        ));

  /// 执行完整的初始化流程
  Future<void> initialize() async {
    try {
      // 步骤 1: 检查基础环境
      state = state.copyWith(progress: 0.1, message: '检查环境...');
      await Future.delayed(const Duration(milliseconds: 200));

      // 步骤 2: 加载本地配置
      state = state.copyWith(progress: 0.2, message: '加载配置...');
      await _writeLeanCloudConfig();
      await Future.delayed(const Duration(milliseconds: 200));

      // 步骤 3: 初始化音频服务（真实操作）
      state = state.copyWith(progress: 0.35, message: '初始化音频服务...');
      await _initializeAudioService();

      // 步骤 3.5: 🎯 初始化代理服务器（关键！）
      state = state.copyWith(progress: 0.42, message: '启动音频代理服务器...');
      await _initializeProxyServer();

      // 步骤 4: 请求权限
      state = state.copyWith(progress: 0.5, message: '请求必要权限...');
      await _requestPermissions();

      // 步骤 5: 加载设备列表和播放状态
      state = state.copyWith(progress: 0.65, message: '加载设备列表...');
      await _loadDevicesAndPlayback();

      // 步骤 6: 连接服务
      state = state.copyWith(progress: 0.85, message: '连接服务...');
      await Future.delayed(const Duration(milliseconds: 300));

      // 步骤 7: 准备就绪
      state = state.copyWith(progress: 1.0, message: '准备就绪...', isCompleted: true);
      await Future.delayed(const Duration(milliseconds: 200));

      // 通知原生层隐藏启动屏
      await _hideSplashScreen();
    } catch (e) {
      debugPrint('❌ [Initialization] 初始化失败: $e');
      state = state.copyWith(
        progress: 1.0,
        message: '初始化完成',
        isCompleted: true,
        error: e.toString(),
      );

      // 即使失败也要隐藏启动屏
      await _hideSplashScreen();
    }
  }

  Future<void> _writeLeanCloudConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lc_base_url', 'https://nu0cttse.lc-cn-n1-shared.com');
      await prefs.setString('lc_app_id', 'nu0CtTsesxoThR70g4Vn9Ypk-gzGzoHsz');
      await prefs.setString('lc_app_key', 'WNNq0Z9pluoS8CRnrqu822xl');
    } catch (e) {
      debugPrint('⚠️ [Initialization] 写入 LeanCloud 配置失败: $e');
    }
  }

  /// 隐藏原生启动屏
  Future<void> _hideSplashScreen() async {
    try {
      await platform.invokeMethod('hideSplash');
      debugPrint('✅ [Initialization] 已通知原生层隐藏启动屏');
    } catch (e) {
      debugPrint('⚠️ [Initialization] 隐藏启动屏失败: $e');
    }
  }

  /// 初始化音频服务
  Future<void> _initializeAudioService() async {
    try {
      debugPrint('🎵 [Initialization] 开始初始化 AudioService...');
      final player = AudioPlayer();
      final handler = await AudioService.init(
        builder: () => AudioHandlerService(player: player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.xiaomi.music.channel.audio',
          androidNotificationChannelName: 'HMusic',
          androidNotificationOngoing: false,
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: false,
        ),
      );

      if (handler is AudioHandlerService) {
        LocalPlaybackStrategy.sharedAudioHandler = handler;
        debugPrint('✅ [Initialization] AudioService 初始化成功');
      } else {
        debugPrint(
          '❌ [Initialization] AudioService 类型不匹配: ${handler.runtimeType}',
        );
      }
    } catch (e) {
      debugPrint('❌ [Initialization] AudioService 初始化失败: $e');
      rethrow;
    }
  }

  /// 🎯 初始化代理服务器（用于音频流转发）
  /// 这是解决小爱音箱播放CDN音频的关键！
  Future<void> _initializeProxyServer() async {
    try {
      debugPrint('🌐 [Initialization] 开始初始化音频代理服务器...');

      // 创建代理服务器实例
      _proxyServer = AudioProxyServer();

      // 启动代理服务器（默认端口 8090）
      final success = await _proxyServer!.start(port: 8090);

      if (success) {
        debugPrint('✅ [Initialization] 代理服务器启动成功: ${_proxyServer!.serverUrl}');
        // 🎯 不要在这里设置到 DirectModeProvider，等后续流程中设置
      } else {
        debugPrint('❌ [Initialization] 代理服务器启动失败');
        _proxyServer = null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [Initialization] 初始化代理服务器异常: $e');
      debugPrint('❌ [Initialization] 堆栈跟踪: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      _proxyServer = null;
      // 代理服务器失败不影响应用启动，只是直连模式可能无法播放
    }
  }

  /// 请求必要权限
  Future<void> _requestPermissions() async {
    try {
      debugPrint('📱 [Initialization] 开始请求权限...');

      // iOS平台：网络权限已在AuthWrapper中提前触发，这里不再重复

      // 请求通知权限
      debugPrint('📱 [Initialization] 请求通知权限...');
      final notificationStatus = await Permission.notification.request();
      debugPrint('📱 [Initialization] 通知权限状态: $notificationStatus');

      // iOS 14+ 本地网络权限会在首次访问时自动弹出
      // 不需要手动请求
      debugPrint('📱 [Initialization] iOS 本地网络权限将在首次网络访问时自动弹出');

      // 检查当前权限状态
      final notification = await Permission.notification.status;
      debugPrint('📱 [Initialization] 最终权限状态:');
      debugPrint('   - 通知: $notification');

    } catch (e, stackTrace) {
      debugPrint('⚠️ [Initialization] 权限请求失败: $e');
      debugPrint('⚠️ [Initialization] 堆栈跟踪: $stackTrace');
      // 权限失败不影响继续
    }
  }

  /// 加载设备列表和播放状态
  Future<void> _loadDevicesAndPlayback() async {
    try {
      debugPrint('🔧 [Initialization] 开始加载设备列表和播放状态...');

      // 🎯 预加载JS脚本（避免搜索时的竞态条件）
      await _preloadJSScripts();

      // 🆕 检查播放模式
      final playbackMode = ref.read(playbackModeProvider);
      debugPrint('🔧 [Initialization] 当前播放模式: $playbackMode');

      if (playbackMode == PlaybackMode.miIoTDirect) {
        // 直连模式 - 会自动尝试登录（如果有保存的凭证）
        debugPrint('🔧 [Initialization] 初始化直连模式');

        // 🎯 读取当前状态（不监听变化，避免在 StateNotifier 中使用 watch）
        ref.read(directModeProvider);

        // 🎯 等待一下让静默登录完成（增加到1秒，确保登录流程完成）
        await Future.delayed(const Duration(milliseconds: 1000));

        // 🎯 设置代理服务器（无论是否登录成功都设置，方便后续手动登录时使用）
        if (_proxyServer != null && _proxyServer!.isRunning) {
          try {
            final directModeNotifier = ref.read(directModeProvider.notifier);
            directModeNotifier.setProxyServer(_proxyServer);
            debugPrint('✅ [Initialization] 已为直连模式设置代理服务器');
          } catch (e) {
            debugPrint('⚠️ [Initialization] 设置代理服务器失败: $e');
            // 失败不影响继续
          }
        }

        // 🎯 初始化 PlaybackProvider（直连模式也需要）
        await ref.read(playbackProvider.notifier).ensureInitialized();
      } else {
        // xiaomusic模式（保持原有逻辑）
        debugPrint('🔧 [Initialization] 初始化xiaomusic模式');

        // 检查是否已登录
        final authState = ref.read(authProvider);
        if (authState is! AuthAuthenticated) {
          debugPrint('⚠️ [Initialization] 用户未登录，跳过加载设备');
          return;
        }

        // 初始化 PlaybackProvider
        await ref.read(playbackProvider.notifier).ensureInitialized();
      }

      debugPrint('✅ [Initialization] 设备和播放状态加载完成');
    } catch (e, stackTrace) {
      debugPrint('❌ [Initialization] 加载设备和播放状态失败: $e');
      debugPrint('❌ [Initialization] 堆栈跟踪: $stackTrace');
      // 失败不影响继续，用户可以在首页重试
    }
  }

  /// 🎯 预加载JS脚本（避免搜索时的竞态条件）
  Future<void> _preloadJSScripts() async {
    try {
      debugPrint('🎯 [Initialization] 开始预加载JS脚本...');

      // 1. 等待JS脚本管理器初始化完成
      final scripts = ref.read(jsScriptManagerProvider);
      debugPrint('🎯 [Initialization] 脚本管理器已加载: ${scripts.length} 个脚本');

      if (scripts.isEmpty) {
        debugPrint('🎯 [Initialization] 没有JS脚本，跳过预加载');
        return;
      }

      // 2. 检查音源设置，确认是否需要JS音源
      final settings = ref.read(sourceSettingsProvider);
      if (settings.primarySource != 'js_external') {
        debugPrint('🎯 [Initialization] 当前不是JS音源模式，跳过预加载');
        return;
      }

      // 3. 获取选中的脚本
      final manager = ref.read(jsScriptManagerProvider.notifier);
      final selectedScript = manager.selectedScript;

      if (selectedScript == null) {
        debugPrint('🎯 [Initialization] 没有选中的JS脚本，跳过预加载');
        return;
      }

      debugPrint('🎯 [Initialization] 选中脚本: ${selectedScript.name}');

      // 4. 等待JS代理服务初始化完成
      final jsProxyState = ref.read(jsProxyProvider);
      if (!jsProxyState.isInitialized) {
        debugPrint('🎯 [Initialization] 等待JS代理服务初始化...');

        // 等待最多3秒
        int waitCount = 0;
        const maxWait = 30; // 3秒
        while (!jsProxyState.isInitialized && waitCount < maxWait) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitCount++;

          // 重新检查状态
          final currentState = ref.read(jsProxyProvider);
          if (currentState.isInitialized) break;
        }

        if (!jsProxyState.isInitialized) {
          debugPrint('⚠️ [Initialization] JS代理服务初始化超时，跳过预加载');
          return;
        }

        debugPrint('✅ [Initialization] JS代理服务已初始化');
      }

      // 5. 预加载选中的JS脚本
      final jsProxyNotifier = ref.read(jsProxyProvider.notifier);

      // 检查是否已经加载了脚本
      if (jsProxyState.currentScript != null) {
        debugPrint('✅ [Initialization] JS脚本已预加载: ${jsProxyState.currentScript}');
        return;
      }

      debugPrint('🎯 [Initialization] 开始预加载JS脚本: ${selectedScript.name}');

      final success = await jsProxyNotifier.loadScriptByScript(selectedScript);

      if (success) {
        debugPrint('✅ [Initialization] JS脚本预加载成功: ${selectedScript.name}');
      } else {
        debugPrint('❌ [Initialization] JS脚本预加载失败: ${selectedScript.name}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [Initialization] JS脚本预加载异常: $e');
      debugPrint('❌ [Initialization] 堆栈跟踪: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      // 预加载失败不影响应用启动，只记录日志
    }
  }

  /// 清理资源（应用关闭时调用）
  @override
  void dispose() {
    debugPrint('🔧 [Initialization] 开始清理资源...');

    // 停止代理服务器
    if (_proxyServer != null) {
      _proxyServer!.stop();
      debugPrint('✅ [Initialization] 代理服务器已停止');
    }

    super.dispose();
  }
}

/// 初始化状态 Provider
final initializationProvider =
    StateNotifierProvider<InitializationNotifier, InitializationState>(
  (ref) => InitializationNotifier(ref),
);
