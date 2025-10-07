import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_router.dart';
import 'presentation/providers/js_proxy_provider.dart';
import 'data/services/audio_handler_service.dart';
import 'data/services/local_playback_strategy.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // warm-up by touching singleton instance
    // ignore: unnecessary_statements
    DefaultCacheManager();
  } catch (_) {}

  // 预初始化全局 AudioService（单例）
  try {
    debugPrint('🎵 [Main] 开始初始化 AudioService...');
    final player = AudioPlayer();
    final handler = await AudioService.init(
      builder: () => AudioHandlerService(player: player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.xiaomi.music.channel.audio',
        androidNotificationChannelName: 'HMusic',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: true,
      ),
    );
    if (handler is AudioHandlerService) {
      LocalPlaybackStrategy.sharedAudioHandler = handler;
      debugPrint('✅ [Main] AudioService 初始化成功');
    } else {
      debugPrint('❌ [Main] AudioService 类型不匹配: ${handler.runtimeType}');
    }
  } catch (e) {
    debugPrint('❌ [Main] AudioService 初始化失败: $e');
  }

  // Android 13+ 请求通知权限
  try {
    await Permission.notification.request();
  } catch (_) {}
  
  // ✅ 在APP启动时就开始初始化JS代理服务（不阻塞UI）
  // 读取jsProxyProvider以触发其初始化与自动脚本加载
  // 注意：ProviderScope要在runApp后才可用，这里用WidgetsBinding后帧回调触发
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      // 使用一个临时的ProviderScope上下文从根部读取并触发
      // 实际上在MyApp里更安全：在builder中读取一次
    } catch (_) {}
  });

  // 禁用Flutter调试边框和调试信息
  debugPaintSizeEnabled = false;
  debugRepaintRainbowEnabled = false;
  debugPaintLayerBordersEnabled = false;

  // 配置系统UI样式，适配小米澎湃OS 2.0
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // 启用边缘到边缘显示，沉浸顶部与底部小白条
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );

  // 添加全局错误处理
  FlutterError.onError = (FlutterErrorDetails details) {
    final errorString = details.exception.toString();

    // 过滤掉已知的Flutter问题和非关键错误
    if (errorString.contains('mouse_tracker.dart') ||
        errorString.contains('_debugDuringDeviceUpdate') ||
        errorString.contains(
          'Cannot hit test a render box that has never been laid out',
        ) ||
        errorString.contains('Cannot hit test a render box with no size') ||
        errorString.contains('RenderBox was not laid out') ||
        errorString.contains('_RenderDeferredLayoutBox') ||
        errorString.contains('!_debugDoingThisLayout') ||
        errorString.contains('DropdownButtonFormField') &&
            errorString.contains('performLayout') ||
        errorString.contains('RenderSemanticsAnnotations') &&
            errorString.contains('size: MISSING')) {
      // 忽略这些已知的Flutter Web问题和布局问题
      return;
    }

    // 其他错误正常处理
    FlutterError.presentError(details);
  };

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = const Color(0xFF21B0A5);

    final lightScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: seed,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      primary: seed,
    );

    // 在应用构建阶段预热JS代理（读取provider以触发初始化和自动加载）
    ref.read(jsProxyProvider);

    return MaterialApp.router(
      title: 'HMusic',
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: lightScheme.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          contentTextStyle: const TextStyle(color: Colors.white),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          contentTextStyle: const TextStyle(color: Colors.white),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      routerConfig: ref.read(appRouterProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // 确保在Material应用级别也禁用调试边框
        return MediaQuery(data: MediaQuery.of(context), child: child!);
      },
    );
  }
}
