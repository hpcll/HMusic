import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/playing_music.dart';
import '../../data/models/online_music_result.dart';
import '../../data/models/device.dart';
import '../../data/models/music.dart';
import '../../data/services/native_music_search_service.dart';
import '../../data/services/playback_strategy.dart';
import '../../data/services/local_playback_strategy.dart';
import '../../data/services/remote_playback_strategy.dart';
import '../../data/services/album_cover_service.dart';
import '../../data/services/mi_iot_direct_playback_strategy.dart'; // 🎯 直连模式策略
import '../../data/services/music_api_service.dart'; // 🎯 音乐API服务
import '../../data/services/direct_mode_favorite_service.dart'; // 🎯 直连模式收藏服务
import '../../data/services/direct_mode_playlist_service.dart'; // 🎯 直连模式歌单服务
import '../../core/network/dio_client.dart'; // 🎯 HTTP客户端
import '../../core/constants/app_constants.dart'; // 🎯 应用常量
import 'dio_provider.dart';
import 'device_provider.dart';
import 'music_library_provider.dart';
import 'direct_mode_provider.dart'; // 🎯 直连模式Provider
import 'playback_queue_provider.dart'; // 🎯 播放队列Provider
import 'lyric_provider.dart'; // 🎯 歌词Provider
import 'js_proxy_provider.dart'; // 🎯 QuickJS代理
import 'js_source_provider.dart'; // 🎯 WebView JS 和 LocalJS 解析（两个都在这里）
import '../../data/models/playlist_item.dart'; // 🎯 播放列表项模型
import '../../data/models/playlist_queue.dart'; // 🎯 播放队列模型

// 用于区分"未传入参数"和"传入 null"
const _undefined = Object();

enum PlayMode {
  loop, // 全部循环
  single, // 单曲循环
  random, // 随机播放
  sequence, // 顺序播放
  singlePlay, // 单曲播放
}

extension PlayModeExtension on PlayMode {
  String get displayName {
    switch (this) {
      case PlayMode.loop:
        return '全部循环';
      case PlayMode.single:
        return '单曲循环';
      case PlayMode.random:
        return '随机播放';
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.singlePlay:
        return '单曲播放';
    }
  }

  String get command {
    switch (this) {
      case PlayMode.loop:
        return '全部循环';
      case PlayMode.single:
        return '单曲循环';
      case PlayMode.random:
        return '随机播放';
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.singlePlay:
        return '单曲播放';
    }
  }

  IconData get icon {
    switch (this) {
      case PlayMode.loop:
        return Icons.repeat;
      case PlayMode.single:
        return Icons.repeat_one;
      case PlayMode.random:
        return Icons.shuffle;
      case PlayMode.sequence:
        return Icons.reorder;
      case PlayMode.singlePlay:
        return Icons.looks_one;
    }
  }
}

class PlaybackState {
  final PlayingMusic? currentMusic;
  final int volume;
  final bool isLoading;
  final String? error;
  final PlayMode playMode;
  final bool hasLoaded; // whether initial fetch attempted
  final String? albumCoverUrl; // ✨ 当前播放歌曲的专辑封面图 URL
  final int timerMinutes; // ⏰ 定时关机分钟数（0 表示未设置）
  final bool isFavorite; // ⭐ 当前歌曲是否已收藏
  final List<String> currentPlaylistSongs; // 🎵 当前播放列表的所有歌曲
  final bool isLocalMode; // 🎵 是否为本地播放模式（用于判断进度条是否可拖动）

  const PlaybackState({
    this.currentMusic,
    this.volume = 0, // Initial UI shows volume at 0 before server data arrives
    this.isLoading = false,
    this.error,
    this.playMode = PlayMode.loop, // 默认全部循环
    this.hasLoaded = false,
    this.albumCoverUrl,
    this.timerMinutes = 0, // 默认未设置定时
    this.isFavorite = false, // 默认未收藏
    this.currentPlaylistSongs = const [], // 默认空列表
    this.isLocalMode = false, // 默认非本地播放
  });

  PlaybackState copyWith({
    PlayingMusic? currentMusic,
    int? volume,
    bool? isLoading,
    String? error,
    PlayMode? playMode,
    bool? hasLoaded,
    Object? albumCoverUrl = _undefined,
    int? timerMinutes,
    bool? isFavorite,
    List<String>? currentPlaylistSongs,
    bool? isLocalMode,
  }) {
    return PlaybackState(
      currentMusic: currentMusic ?? this.currentMusic,
      volume: volume ?? this.volume,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      playMode: playMode ?? this.playMode,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      albumCoverUrl:
          albumCoverUrl == _undefined
              ? this.albumCoverUrl
              : albumCoverUrl as String?,
      timerMinutes: timerMinutes ?? this.timerMinutes,
      isFavorite: isFavorite ?? this.isFavorite,
      currentPlaylistSongs: currentPlaylistSongs ?? this.currentPlaylistSongs,
      isLocalMode: isLocalMode ?? this.isLocalMode,
    );
  }
}

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  final Ref ref;
  bool _isInitialized = false;
  Timer? _statusRefreshTimer;
  Timer? _localProgressTimer;
  DateTime? _lastUpdateTime;
  DateTime? _lastProgressUpdate; // 上次UI进度更新时间
  DateTime? _lastRefreshTime; // 上次状态刷新时间
  // 保存服务器最后返回的原始进度，用于本地预测基准
  int? _lastServerOffset;

  // 保护期：设备切换后在该时间窗内忽略非当前设备的远端更新
  DateTime? _deviceSwitchProtectionUntil;

  // 🎯 乐观更新保护期：在播放/暂停操作后的短时间内忽略远程状态的 isPlaying 更新
  DateTime? _optimisticUpdateProtectionUntil;

  // 🖼️ 封面图自动搜索相关
  final _searchService = NativeMusicSearchService();
  AlbumCoverService? _albumCoverService; // 🆕 新的封面服务
  final Map<String, String> _coverCache = {}; // 歌曲名 -> 封面URL 的缓存
  String? _lastCoverSearchSong; // 上次搜索封面的歌曲名（用于防止重复搜索）
  String? _searchingCoverForSong; // 🔧 正在搜索封面的歌曲名（防止重复搜索）
  static const String _coverCacheKey = 'album_cover_cache';
  static const int _maxCacheSize = 200;
  static const String _localPlaybackKey = 'local_playback_state';
  static const String _localPlaybackUrlKey = 'local_playback_url';
  static const String _localPlaybackCoverKey = 'local_playback_cover';
  static const String _directModePlaybackKey = 'direct_mode_playback_state'; // 🆕 直连模式专用
  static const String _directModePlaybackCoverKey = 'direct_mode_playback_cover'; // 🆕 直连模式专用

  // 🎵 播放历史记录（用于随机播放的"上一首"功能）
  final List<String> _playHistory = []; // 保存最近播放过的歌曲名
  static const int _maxHistorySize = 50; // 最多保留50首历史记录

  // 🔧 缓存的播放状态（待策略初始化后恢复）
  PlayingMusic? _cachedPlayingMusic;
  String? _cachedMusicUrl;
  String? _cachedCoverUrl;
  int? _cachedOffset;

  // 🎵 播放策略（本地播放或远程控制）
  PlaybackStrategy? _currentStrategy;
  String? _currentDeviceId; // 当前使用的设备ID

  Timer? _timerCountdown; // ⏰ APP本地定时器（直连模式用）

  PlaybackNotifier(this.ref)
    : super(const PlaybackState(isLoading: false, hasLoaded: false)) {
    // 禁用自动初始化，避免在未登录时进行网络请求
    // 需要用户手动触发初始化
    debugPrint('PlaybackProvider: 自动初始化已禁用，等待用户手动触发');
    // 🖼️ 异步加载封面图缓存
    _loadCoverCache();
    _listenToDeviceChanges();
    // 🔧 不要在构造函数中恢复播放数据，避免在设备确定前显示数据
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    _localProgressTimer?.cancel();
    _timerCountdown?.cancel(); // ⏰ 清理定时器
    _currentStrategy?.dispose();
    _albumCoverService?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_isInitialized) {
      debugPrint('🔧 [PlaybackProvider] 已经初始化过，跳过');
      return;
    }
    _isInitialized = true;

    try {
      debugPrint('🔧 [PlaybackProvider] ========== 开始初始化 ==========');

      // 🎯 检查当前播放模式
      final playbackMode = ref.read(playbackModeProvider);
      debugPrint('🔧 [PlaybackProvider] 当前播放模式: ${playbackMode.displayName}');

      if (playbackMode == PlaybackMode.miIoTDirect) {
        // 🎯 直连模式：从 DirectModeProvider 获取设备并初始化策略
        final directState = ref.read(directModeProvider);
        debugPrint('🔧 [PlaybackProvider] 直连模式状态类型: ${directState.runtimeType}');

        if (directState is DirectModeAuthenticated) {
          debugPrint('🔧 [PlaybackProvider] ✅ 直连模式已登录');
          debugPrint('🔧 [PlaybackProvider] 设备数量: ${directState.devices.length}');
          debugPrint('🔧 [PlaybackProvider] 播放设备类型: ${directState.playbackDeviceType}');

          // 🎵 无论是本地播放还是小爱音箱播放，都初始化策略
          debugPrint('🔧 [PlaybackProvider] 🎯 开始初始化直连模式播放策略');
          await _switchToDirectModeStrategy(directState);
          debugPrint('🔧 [PlaybackProvider] 策略初始化结果: ${_currentStrategy != null ? "成功" : "失败"}');
        } else if (directState is DirectModeInitial) {
          debugPrint('⚠️ [PlaybackProvider] ❌ 直连模式未登录（DirectModeInitial）');
          debugPrint('⚠️ [PlaybackProvider] 提示：请先登录小米账号');
        } else if (directState is DirectModeLoading) {
          debugPrint('⚠️ [PlaybackProvider] 🔄 直连模式正在登录中（DirectModeLoading）');
        } else if (directState is DirectModeError) {
          debugPrint('⚠️ [PlaybackProvider] ❌ 直连模式登录失败（DirectModeError）');
          debugPrint('⚠️ [PlaybackProvider] 错误信息: ${(directState as DirectModeError).message}');
        } else {
          debugPrint('⚠️ [PlaybackProvider] ❓ 未知的直连模式状态: ${directState.runtimeType}');
        }
      } else {
        // 🎯 xiaomusic 模式：从 DeviceProvider 获取设备并初始化策略
        debugPrint('🔧 [PlaybackProvider] xiaomusic 模式：开始加载设备列表');

        // 1. 加载设备列表
        await ref.read(deviceProvider.notifier).loadDevices();

        // 2. 获取当前选中的设备并初始化策略
        final deviceState = ref.read(deviceProvider);
        debugPrint('🔧 [PlaybackProvider] 设备列表加载完成: ${deviceState.devices.length} 个设备');
        debugPrint('🔧 [PlaybackProvider] 当前选中设备ID: ${deviceState.selectedDeviceId ?? "null"}');

        if (deviceState.selectedDeviceId != null &&
            deviceState.devices.isNotEmpty) {
          debugPrint('🔧 [PlaybackProvider] 🎯 开始初始化播放策略');
          await _switchStrategy(
            deviceState.selectedDeviceId!,
            deviceState.devices,
          );
          debugPrint('🔧 [PlaybackProvider] 策略初始化结果: ${_currentStrategy != null ? "成功" : "失败"}');
        } else {
          debugPrint('⚠️ [PlaybackProvider] ❌ 无设备或未选中设备，跳过策略初始化');
          if (deviceState.devices.isEmpty) {
            debugPrint('⚠️ [PlaybackProvider] 提示：未找到设备，请检查服务器配置');
          } else {
            debugPrint('⚠️ [PlaybackProvider] 提示：请选择一个播放设备');
          }
        }

        // 3. 刷新播放状态（仅远程模式需要）
        // 🔧 优化：异步刷新状态，不阻塞初始化流程，让首页更快显示
        if (_currentStrategy != null && !_currentStrategy!.isLocalMode) {
          debugPrint('🔧 [PlaybackProvider] 异步刷新远程播放状态（不阻塞初始化）');
          // ignore: unawaited_futures
          refreshStatus().catchError((e) {
            debugPrint('⚠️ [PlaybackProvider] 异步刷新状态失败: $e');
          });
        }
      }

      debugPrint('✅ [PlaybackProvider] ========== 初始化完成 ==========');
      debugPrint('✅ [PlaybackProvider] 当前策略: ${_currentStrategy != null ? (_currentStrategy!.isLocalMode ? "本地播放" : "远程控制") : "未初始化"}');
    } catch (e, stackTrace) {
      // 初始化失败，设置错误状态但不抛出异常
      debugPrint('❌ [PlaybackProvider] ========== 初始化失败 ==========');
      debugPrint('❌ [PlaybackProvider] 错误: $e');
      debugPrint('❌ [PlaybackProvider] 堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: '初始化失败: ${e.toString()}',
      );
    }
  }

  // 公共方法，允许手动触发初始化
  Future<void> ensureInitialized() async {
    await _initialize();
  }

  // 🎵 监听设备变化，自动切换播放策略
  void _listenToDeviceChanges() {
    // 🎯 监听 xiaomusic 模式的设备变化
    ref.listen<DeviceState>(deviceProvider, (previous, next) {
      final playbackMode = ref.read(playbackModeProvider);
      if (playbackMode != PlaybackMode.xiaomusic) {
        return; // 非 xiaomusic 模式时忽略
      }

      final newDeviceId = next.selectedDeviceId;

      // 🔧 如果正在初始化，忽略设备变化（避免重复切换）
      if (_isInitialized == false) {
        debugPrint('🎵 [PlaybackProvider] 正在初始化，忽略设备变化');
        return;
      }

      // 🔧 如果设备列表为空，忽略设备变化（设备还未加载完成）
      if (next.devices.isEmpty) {
        debugPrint('🎵 [PlaybackProvider] 设备列表为空，忽略设备变化');
        return;
      }

      // 设备ID变化时切换策略
      if (newDeviceId != _currentDeviceId && newDeviceId != null) {
        debugPrint(
          '🎵 [PlaybackProvider] 检测到xiaomusic设备切换: $_currentDeviceId -> $newDeviceId',
        );
        _switchStrategy(newDeviceId, next.devices);
      }
    });

    // 🎯 监听直连模式的设备变化
    ref.listen<DirectModeState>(directModeProvider, (previous, next) {
      final playbackMode = ref.read(playbackModeProvider);
      if (playbackMode != PlaybackMode.miIoTDirect) {
        return; // 非直连模式时忽略
      }

      if (next is DirectModeAuthenticated && previous is DirectModeAuthenticated) {
        // 🎵 检查播放设备类型是否变化
        if (next.playbackDeviceType != previous.playbackDeviceType) {
          debugPrint(
            '🎵 [PlaybackProvider] 检测到直连模式播放设备切换: ${previous.playbackDeviceType} -> ${next.playbackDeviceType}',
          );
          _currentDeviceId = null; // 重置设备ID，准备切换策略
          _switchToDirectModeStrategy(next);
        }
      } else if (next is DirectModeAuthenticated && previous is! DirectModeAuthenticated) {
        // 从未登录变为已登录，初始化播放策略
        debugPrint('🎵 [PlaybackProvider] 检测到直连模式登录成功，初始化播放策略');
        _switchToDirectModeStrategy(next);
      }
    });

    // 🎯 监听播放模式切换
    ref.listen<PlaybackMode>(playbackModeProvider, (previous, next) {
      if (previous != next) {
        debugPrint('🎵 [PlaybackProvider] 检测到播放模式切换: $previous -> $next');

        // 🎯 模式切换时停止当前播放并清空状态
        // 这样可以避免切换后显示错误的歌曲信息
        _handleModeSwitch();

        _currentDeviceId = null; // 重置设备ID，准备切换策略
        _currentStrategy?.dispose();
        _currentStrategy = null;

        // 🎯 关键修复：根据新模式重新初始化策略
        _reinitializeForNewMode(next);
      }
    });
  }

  /// 🎯 处理模式切换：停止播放但保留目标模式的状态
  void _handleModeSwitch() {
    debugPrint('🔄 [PlaybackProvider] 模式切换，停止当前播放');

    // 1. 尝试停止当前策略的播放（如果有的话）
    try {
      _currentStrategy?.pause();
    } catch (e) {
      debugPrint('⚠️ [PlaybackProvider] 停止播放失败（忽略）: $e');
    }

    // 2. 停止所有定时器
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = null;
    _localProgressTimer?.cancel();
    _localProgressTimer = null;

    // 3. 清空进度预测状态
    _lastServerOffset = null;
    _lastUpdateTime = null;
    _lastProgressUpdate = null;

    // 🎯 注意：不清空 UI 状态！
    // 目标模式会恢复它自己保存的状态，显示该模式之前播放的歌曲（暂停状态）

    debugPrint('✅ [PlaybackProvider] 已停止播放，准备切换模式');
  }

  /// 🎯 模式切换后重新初始化策略
  Future<void> _reinitializeForNewMode(PlaybackMode newMode) async {
    debugPrint('🎵 [PlaybackProvider] 为新模式重新初始化策略: $newMode');

    if (newMode == PlaybackMode.miIoTDirect) {
      // 直连模式：检查是否已登录，然后初始化策略
      final directState = ref.read(directModeProvider);
      if (directState is DirectModeAuthenticated) {
        debugPrint('🎵 [PlaybackProvider] 直连模式已登录，初始化直连策略');
        await _switchToDirectModeStrategy(directState);
      } else {
        debugPrint('⚠️ [PlaybackProvider] 直连模式未登录，等待登录后初始化');
      }
    } else {
      // xiaomusic 模式：检查设备，然后初始化策略
      final deviceState = ref.read(deviceProvider);
      if (deviceState.selectedDeviceId != null) {
        debugPrint('🎵 [PlaybackProvider] xiaomusic 模式有设备，初始化远程策略');
        await _switchStrategy(deviceState.selectedDeviceId!, deviceState.devices);
      } else {
        debugPrint('⚠️ [PlaybackProvider] xiaomusic 模式无设备，等待选择设备后初始化');
      }
    }
  }

  // 🎯 切换到直连模式播放策略
  Future<void> _switchToDirectModeStrategy(DirectModeAuthenticated directState) async {
    try {
      final playbackDeviceType = directState.playbackDeviceType;

      debugPrint('🎵 [PlaybackProvider] ========== 切换到直连模式策略 ==========');
      debugPrint('🎵 [PlaybackProvider] 播放设备类型: $playbackDeviceType');

      // 释放旧策略
      if (_currentStrategy != null) {
        debugPrint('🎵 [PlaybackProvider] 释放旧策略');
        await _currentStrategy!.dispose();
      }

      // 🎯 根据播放设备类型创建对应的策略
      if (playbackDeviceType == 'local') {
        // 🎵 本地播放模式
        debugPrint('🎵 [PlaybackProvider] ========== 本地播放模式 ==========');
        _deviceSwitchProtectionUntil = DateTime.now().add(const Duration(milliseconds: 1500));
        debugPrint('🎵 [PlaybackProvider] 创建本地播放策略');

        // 🎯 尝试获取 MusicApiService（用于搜索音乐，可选）
        MusicApiService? apiService = ref.read(apiServiceProvider);

        // 🎯 如果 apiServiceProvider 为 null（直连模式下未登录 xiaomusic）
        // 尝试从 SharedPreferences 读取保存的服务器配置并创建临时 MusicApiService
        if (apiService == null) {
          debugPrint('⚠️ [PlaybackProvider] apiServiceProvider 为 null，尝试从本地配置创建');

          try {
            final prefs = await SharedPreferences.getInstance();
            final serverUrl = prefs.getString(AppConstants.prefsServerUrl);
            final username = prefs.getString(AppConstants.prefsUsername);
            final password = prefs.getString(AppConstants.prefsPassword);

            if (serverUrl != null && username != null && password != null) {
              debugPrint('✅ [PlaybackProvider] 找到保存的服务器配置: $serverUrl');

              // 创建临时的 DioClient 和 MusicApiService
              final tempClient = DioClient(
                baseUrl: serverUrl,
                username: username,
                password: password,
              );
              apiService = MusicApiService(tempClient);

              debugPrint('✅ [PlaybackProvider] 成功创建临时 MusicApiService');
            } else {
              debugPrint('⚠️ [PlaybackProvider] 未找到服务器配置，使用完全独立模式');
              // 🎯 完全独立模式：不依赖 xiaomusic 服务器
              // apiService 保持为 null，LocalPlaybackStrategy 会处理这种情况
            }
          } catch (e) {
            debugPrint('⚠️ [PlaybackProvider] 创建临时 MusicApiService 失败: $e，使用完全独立模式');
            // 🎯 失败时也使用完全独立模式
            apiService = null;
          }
        }

        // 🎯 创建本地播放策略（apiService 可以为 null，支持完全独立模式）
        final localStrategy = LocalPlaybackStrategy(apiService: apiService);
        _currentStrategy = localStrategy;
        _currentDeviceId = 'local';

        try {
          await LocalPlaybackStrategy.handlerReady.timeout(const Duration(seconds: 2));
        } catch (_) {}

        // 🎵 监听本地播放器状态流
        localStrategy.statusStream.listen((status) async {
          debugPrint('🎵 [PlaybackProvider] 收到本地播放状态更新');
          state = state.copyWith(
            currentMusic: status,
            hasLoaded: true,
            isLoading: false,
            isLocalMode: true, // 🎵 本地播放模式
          );
          await _saveLocalPlayback(status);
          localStrategy.refreshNotification();

          // 🖼️ 本地模式自动搜索封面图
          if (status.curMusic.isNotEmpty && _lastCoverSearchSong != status.curMusic) {
            debugPrint('🖼️ [PlaybackProvider-本地Stream] 歌曲切换,清除旧封面: $_lastCoverSearchSong -> ${status.curMusic}');
            state = state.copyWith(albumCoverUrl: null);
            _lastCoverSearchSong = status.curMusic;
            debugPrint('🖼️ [PlaybackProvider-本地Stream] ✅ 触发封面自动搜索: ${status.curMusic}');
            _autoFetchAlbumCover(status.curMusic).catchError((e) {
              debugPrint('🖼️ [AutoCover] 异步搜索封面失败: $e');
            });
          }
        });

        // 🔧 停止所有远程模式的定时器（本地模式不需要）
        _statusRefreshTimer?.cancel();
        _statusRefreshTimer = null;
        _localProgressTimer?.cancel();
        _localProgressTimer = null;

        // 🔧 清除远程模式的进度预测状态
        _lastServerOffset = null;
        _lastUpdateTime = null;
        _lastProgressUpdate = null;

        debugPrint('✅ [PlaybackProvider] 已清理远程模式的定时器和状态');

        // 更新状态
        state = state.copyWith(
          hasLoaded: true,
          isLoading: false,
          isLocalMode: true, // 本地播放
        );

        debugPrint('✅ [PlaybackProvider] 本地播放模式切换完成');

        // 💾 本地播放的状态恢复会通过 statusStream.listen 自动处理，无需手动恢复
      } else {
        // 🎵 小爱音箱播放模式（MiIoTDirectPlaybackStrategy）
        final deviceId = playbackDeviceType;

        // 找到选中的设备
        final device = directState.devices.firstWhere(
          (d) => d.deviceId == deviceId,
          orElse: () => throw Exception('设备不存在: $deviceId'),
        );

        debugPrint('🎵 [PlaybackProvider] ========== 小爱音箱播放模式 ==========');
        debugPrint('🎵 [PlaybackProvider] 设备: ${device.name} ($deviceId)');

        debugPrint('🎵 [PlaybackProvider] 创建直连模式策略实例');

        // 🔧 创建直连模式策略（在构造函数中直接传入回调，避免 NULL 问题）
        // 🎯 skipRestore: false（默认值）- 恢复该模式之前保存的状态（暂停状态）
        final directStrategy = MiIoTDirectPlaybackStrategy(
          miService: directState.miService,
          deviceId: deviceId,
          deviceName: device.name,
          audioHandler: LocalPlaybackStrategy.sharedAudioHandler,
          // 🎯 不设置 skipRestore，使用默认值 false，恢复之前保存的状态
          // 🔧 直接在构造时设置状态变化回调，确保轮询启动前回调已就绪
          onStatusChanged: () async {
            debugPrint('🔔 [PlaybackProvider] 直连模式状态变化');
            await refreshStatus(silent: true);

            // 💾 保存直连模式播放状态（每次状态变化都保存）
            if (state.currentMusic != null && state.currentMusic!.curMusic.isNotEmpty) {
              await _saveDirectModePlayback(state.currentMusic!);
            }
          },
          // 🔧 直接在构造时设置获取音乐URL的回调
          onGetMusicUrl: (musicName) async {
            try {
              debugPrint('🔍 [PlaybackProvider] 获取音乐URL: $musicName');

              // 🎯 尝试获取 MusicApiService（用于搜索音乐，可选）
              MusicApiService? apiService = ref.read(apiServiceProvider);

              // 🎯 如果 apiServiceProvider 为 null（直连模式下未登录 xiaomusic）
              // 尝试从 SharedPreferences 读取保存的服务器配置并创建临时 MusicApiService
              if (apiService == null) {
                debugPrint('⚠️ [PlaybackProvider-MiIoT] apiServiceProvider 为 null，尝试从本地配置创建');

                try {
                  final prefs = await SharedPreferences.getInstance();
                  final serverUrl = prefs.getString(AppConstants.prefsServerUrl);
                  final username = prefs.getString(AppConstants.prefsUsername);
                  final password = prefs.getString(AppConstants.prefsPassword);

                  if (serverUrl != null && username != null && password != null) {
                    debugPrint('✅ [PlaybackProvider-MiIoT] 找到保存的服务器配置: $serverUrl');

                    // 创建临时的 DioClient 和 MusicApiService
                    final tempClient = DioClient(
                      baseUrl: serverUrl,
                      username: username,
                      password: password,
                    );
                    apiService = MusicApiService(tempClient);

                    debugPrint('✅ [PlaybackProvider-MiIoT] 成功创建临时 MusicApiService');
                  } else {
                    debugPrint('⚠️ [PlaybackProvider-MiIoT] 未找到服务器配置，完全独立模式');
                    // 🎯 完全独立模式：返回 null，由调用方处理
                    // 直连模式播放在线音乐时会直接传入 URL，不需要通过这个回调获取
                    return null;
                  }
                } catch (e) {
                  debugPrint('⚠️ [PlaybackProvider-MiIoT] 创建临时 MusicApiService 失败: $e，完全独立模式');
                  return null;
                }
              }

              // 🎯 如果有 apiService，尝试从服务器获取音乐 URL
              if (apiService != null) {
                final musicInfo = await apiService.getMusicInfo(musicName);
                final url = musicInfo['url']?.toString();
                debugPrint('✅ [PlaybackProvider-MiIoT] 从服务器获取到URL: $url');
                return url;
              }

              // 🎯 完全独立模式：返回 null
              debugPrint('⚠️ [PlaybackProvider-MiIoT] 完全独立模式，无法从服务器获取URL');
              return null;
            } catch (e) {
              debugPrint('❌ [PlaybackProvider] 获取音乐URL失败: $e');
              return null;
            }
          },
        );

        debugPrint('✅ [PlaybackProvider] 直连模式策略实例已创建（回调已同步设置）');

        // 🎵 设置播放列表（从音乐库获取）
        try {
          final libraryState = ref.read(musicLibraryProvider);
          debugPrint('🎵 [PlaybackProvider] 音乐库歌曲数量: ${libraryState.musicList.length}');

          if (libraryState.musicList.isNotEmpty) {
            int startIndex = 0;
            if (state.currentMusic != null) {
              final idx = libraryState.musicList.indexWhere(
                (m) => m.name == state.currentMusic!.curMusic,
              );
              if (idx >= 0) {
                startIndex = idx;
                debugPrint('🎵 [PlaybackProvider] 找到当前播放歌曲索引: $startIndex');
              }
            }
            directStrategy.setPlaylist(libraryState.musicList, startIndex: startIndex);
            debugPrint('✅ [PlaybackProvider] 已设置直连播放列表: ${libraryState.musicList.length} 首');
          } else {
            debugPrint('⚠️ [PlaybackProvider] 音乐库为空，暂不设置播放列表');
          }
        } catch (e) {
          debugPrint('❌ [PlaybackProvider] 设置播放列表失败: $e');
        }

        _currentStrategy = directStrategy;
        _currentDeviceId = deviceId;

        debugPrint('✅ [PlaybackProvider] 策略对象已赋值: ${_currentStrategy != null}');

        // 更新状态
        state = state.copyWith(
          hasLoaded: true,
          isLoading: false,
          isLocalMode: false, // 直连模式不是本地播放
        );

        debugPrint('✅ [PlaybackProvider] 直连模式策略切换完成');
        debugPrint('✅ [PlaybackProvider] 当前策略是否为null: ${_currentStrategy == null}');

        // 🔊 获取并显示真实音量
        try {
          final volume = await directStrategy.getVolume();
          state = state.copyWith(volume: volume);
          debugPrint('🔊 [PlaybackProvider] 音量已更新到UI: $volume');
        } catch (e) {
          debugPrint('❌ [PlaybackProvider] 获取音量失败: $e');
        }

        // 🎯 策略类会自动恢复之前保存的播放状态（暂停状态）
        // 用户切换到直连模式后，可以看到之前播放的歌曲，点击播放即可继续
        debugPrint('✅ [PlaybackProvider] 直连模式初始化完成');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [PlaybackProvider] 切换直连模式策略失败: $e');
      debugPrint('❌ [PlaybackProvider] 堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}');
    }
  }

  // 🎵 切换播放策略
  Future<void> _switchStrategy(String deviceId, List<Device> devices) async {
    try {
      debugPrint('🎵 [PlaybackProvider] ========== 开始切换播放策略 ==========');
      debugPrint('🎵 [PlaybackProvider] 目标设备ID: $deviceId');
      debugPrint('🎵 [PlaybackProvider] 设备列表: ${devices.map((d) => '${d.name}(${d.id})').join(', ')}');

      // 🔧 智能判断是否需要清空UI状态
      // 如果是首次初始化（_currentDeviceId == null），保留缓存数据，避免闪烁
      // 如果是真正的设备切换，才清空数据
      final isFirstInit = (_currentDeviceId == null);
      if (isFirstInit) {
        debugPrint('🎵 [PlaybackProvider] 首次初始化，保留缓存数据');
        // 只标记为未加载，但不清空数据
        state = state.copyWith(hasLoaded: false);
      } else {
        debugPrint('🎵 [PlaybackProvider] 设备切换，清空UI状态');
        state = state.copyWith(
          currentMusic: null,
          albumCoverUrl: null,
          hasLoaded: false,
        );
      }

      // 🔧 直接用设备ID判断，不依赖设备列表（更可靠）
      final isLocalMode = (deviceId == 'local_device');
      debugPrint('🎵 [PlaybackProvider] 目标设备是否为本地: $isLocalMode (ID: $deviceId)');

      // 查找设备信息（仅用于显示名称）
      final device = devices.firstWhere(
        (d) => d.id == deviceId,
        orElse: () {
          debugPrint('⚠️ [PlaybackProvider] 未在列表中找到设备ID: $deviceId');
          return Device.localDevice;
        },
      );

      debugPrint('🎵 [PlaybackProvider] 设备名称: ${device.name}');

      // 保存当前播放状态（用于切换后恢复）
      final currentMusic = state.currentMusic;
      final currentProgress = currentMusic?.offset ?? 0;
      final wasPlaying = currentMusic?.isPlaying ?? false;

      // 释放旧策略
      if (_currentStrategy != null) {
        debugPrint('🎵 [PlaybackProvider] 释放旧策略');
        await _currentStrategy!.dispose();
      }

      // 创建新策略
      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) {
        debugPrint('❌ [PlaybackProvider] API服务未初始化');
        return;
      }

      // 🔧 使用直接判断的 isLocalMode，而不是 device.isLocalDevice
      if (isLocalMode) {
        debugPrint('🎵 [PlaybackProvider] ========== 本地播放模式 ==========');
        _deviceSwitchProtectionUntil = DateTime.now().add(const Duration(milliseconds: 1500));
        debugPrint('🎵 [PlaybackProvider] 切换到本地播放模式');

        final localStrategy = LocalPlaybackStrategy(apiService: apiService);
        _currentStrategy = localStrategy;

        try {
          await LocalPlaybackStrategy.handlerReady.timeout(const Duration(seconds: 2));
        } catch (_) {}

        // 🎵 监听本地播放器状态流
        localStrategy.statusStream.listen((status) async {
          debugPrint('🎵 [PlaybackProvider] 收到本地播放状态更新');
          state = state.copyWith(
            currentMusic: status,
            hasLoaded: true,
            isLoading: false,
            isLocalMode: true, // 🎵 本地播放模式
          );
          await _saveLocalPlayback(status);
          localStrategy.refreshNotification();

          // 🖼️ 本地模式自动搜索封面图
          // 🔧 修复: 当歌曲切换时,主动更新封面
          if (status.curMusic.isNotEmpty && _lastCoverSearchSong != status.curMusic) {
            debugPrint('🖼️ [PlaybackProvider-本地Stream] 歌曲切换,清除旧封面: $_lastCoverSearchSong -> ${status.curMusic}');

            // 🔧 先清除旧封面,避免显示上一首歌的封面
            state = state.copyWith(albumCoverUrl: null);

            _lastCoverSearchSong = status.curMusic; // 记录本次搜索歌曲

            debugPrint('🖼️ [PlaybackProvider-本地Stream] ✅ 触发封面自动搜索: ${status.curMusic}');
            _autoFetchAlbumCover(status.curMusic).catchError((e) {
              debugPrint('🖼️ [AutoCover] 异步搜索封面失败: $e');
            });
          }
        });

        // 🔧 停止所有远程模式的定时器（本地模式不需要）
        _statusRefreshTimer?.cancel();
        _statusRefreshTimer = null;
        _localProgressTimer?.cancel();
        _localProgressTimer = null;

        // 🔧 清除远程模式的进度预测状态
        _lastServerOffset = null;
        _lastUpdateTime = null;
        _lastProgressUpdate = null;

        debugPrint('✅ [PlaybackProvider] 已清理远程模式的定时器和状态');

        // 🔧 先清除远程播放的封面图
        state = state.copyWith(albumCoverUrl: null);
        debugPrint('🖼️ [PlaybackProvider] 已清除远程播放封面图');

        // 🔧 从 SharedPreferences 重新加载缓存数据（因为从播放设备切换回来时内存缓存可能已清空）
        try {
          final prefs = await SharedPreferences.getInstance();
          final cachedUrl = prefs.getString(_localPlaybackUrlKey);
          final cachedCover = prefs.getString(_localPlaybackCoverKey);
          final jsonStr = prefs.getString(_localPlaybackKey);

          PlayingMusic? cachedMusic;
          int cachedOffset = 0;

          if (jsonStr != null && jsonStr.isNotEmpty) {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            cachedMusic = PlayingMusic(
              ret: data['ret'] as String? ?? 'OK',
              curMusic: data['curMusic'] as String? ?? '',
              curPlaylist: (data['curPlaylist'] as String?) ?? '本地播放',
              isPlaying: false, // 恢复时总是暂停状态
              offset: data['offset'] as int? ?? 0,
              duration: data['duration'] as int? ?? 0,
            );
            cachedOffset = cachedMusic.offset;
          }

          // 🔧 恢复缓存的播放状态（如果有）
          if (cachedUrl != null && cachedMusic != null && cachedUrl.isNotEmpty) {
            debugPrint('🔧 [PlaybackProvider] 恢复本地播放缓存');
            debugPrint('   - 歌曲: ${cachedMusic.curMusic}');
            debugPrint('   - URL: $cachedUrl');
            debugPrint('   - 进度: ${cachedOffset}s / ${cachedMusic.duration}s');

            await localStrategy.prepareFromCache(
              url: cachedUrl,
              name: cachedMusic.curMusic,
              offset: cachedOffset,
            );

            // 🎯 立即更新 UI 状态,避免等待 statusStream
            state = state.copyWith(
              currentMusic: cachedMusic,
              hasLoaded: true,
              isLoading: false,
              isLocalMode: true, // 🎵 本地播放模式
            );
            debugPrint('✅ [PlaybackProvider] UI 状态已更新');
            if (_currentStrategy is LocalPlaybackStrategy) {
              (_currentStrategy as LocalPlaybackStrategy).refreshNotification();
            }

            if (cachedCover != null && cachedCover.isNotEmpty) {
              updateAlbumCover(cachedCover);
              debugPrint('✅ [PlaybackProvider] 封面已恢复');
            }

            // 🔊 恢复音量状态到UI
            try {
              final volume = await localStrategy.getVolume();
              state = state.copyWith(volume: volume);
              debugPrint('🔊 [PlaybackProvider] 音量已恢复到UI: $volume');
            } catch (e) {
              debugPrint('❌ [PlaybackProvider] 恢复音量失败: $e');
            }

            // 🔧 立即刷新通知栏,确保显示本地播放状态
            if (_currentStrategy is LocalPlaybackStrategy) {
              (_currentStrategy as LocalPlaybackStrategy).refreshNotification();
            }
          } else {
            debugPrint('⚠️ [PlaybackProvider] 无本地播放缓存可恢复');
            debugPrint('   - cachedUrl: ${cachedUrl ?? "null"}');
            debugPrint('   - cachedMusic: ${cachedMusic?.curMusic ?? "null"}');

            // 🔧 即使没有缓存,也要清空通知栏避免显示远程播放信息
            if (_currentStrategy is LocalPlaybackStrategy) {
              final audioHandler = LocalPlaybackStrategy.sharedAudioHandler;
              if (audioHandler != null) {
                await audioHandler.setMediaItem(
                  title: '本机播放',
                  artist: '本机播放',
                  album: '本地播放',
                );
                debugPrint('✅ [PlaybackProvider] 已清空通知栏,显示本地播放');
              }
            }
          }
        } catch (e) {
          debugPrint('❌ [PlaybackProvider] 加载本地播放缓存失败: $e');
        }

        // 恢复本地播放列表
        try {
          final libraryState = ref.read(musicLibraryProvider);
          if (libraryState.musicList.isNotEmpty) {
            int startIndex = 0;
            if (state.currentMusic != null) {
              final idx = libraryState.musicList.indexWhere((m) => m.name == state.currentMusic!.curMusic);
              if (idx >= 0) startIndex = idx;
            }
            localStrategy.setPlaylist(libraryState.musicList, startIndex: startIndex);
            debugPrint('🎵 [PlaybackProvider] 已恢复本地播放列表: ${libraryState.musicList.length} 首');
          } else {
            debugPrint('⚠️ [PlaybackProvider] 音乐库为空，暂不设置本地播放列表');
          }
        } catch (e) {
          debugPrint('❌ [PlaybackProvider] 恢复本地播放列表失败: $e');
        }
      } else {
        debugPrint('🎵 [PlaybackProvider] ========== 远程控制模式 ==========');
        debugPrint('🎵 [PlaybackProvider] 切换到远程控制模式 (设备: ${device.name})');
        _deviceSwitchProtectionUntil = DateTime.now().add(const Duration(milliseconds: 1500));

        final remoteStrategy = RemotePlaybackStrategy(
          apiService: apiService,
          deviceId: deviceId,
          deviceName: device.name, // 🔧 传入设备名称
          audioHandler: LocalPlaybackStrategy.sharedAudioHandler, // 🔧 传入 AudioHandler
        );

        // 🔧 设置状态变化回调,远程操作后立即刷新 APP 状态
        remoteStrategy.onStatusChanged = () {
          debugPrint('🔔 [PlaybackProvider] 远程状态已变化,立即刷新 APP');
          // 🔧 重置防抖时间,允许立即刷新
          _lastRefreshTime = null;
          refreshStatus(silent: true);
        };

        _currentStrategy = remoteStrategy;

        // 启动状态刷新定时器
        _startStatusRefreshTimer();

        // 🔧 不要在这里清除封面图，让 refreshStatus() 来决定是否需要搜索封面
        // 避免重复清除导致封面闪烁
        debugPrint('🖼️ [PlaybackProvider] 保留当前封面，等待刷新远程设备状态');

        // 🔧 立即刷新一次状态，避免等待 5 秒才显示播放设备当前播放内容
        await refreshStatus();
        debugPrint('✅ [PlaybackProvider] 已立即刷新播放设备播放状态');

        // 🎵 远程播放模式：更新状态
        state = state.copyWith(isLocalMode: false);
      }

      _currentDeviceId = deviceId;

      // 🔄 可选：尝试在新设备上恢复播放
      // if (currentMusic != null && wasPlaying) {
      //   await _resumePlaybackAfterSwitch(currentMusic, currentProgress);
      // }

      debugPrint('✅ [PlaybackProvider] 策略切换完成');
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 切换策略失败: $e');
    }
  }

  // 🎵 启动状态刷新定时器（用于远程模式）
  void _startStatusRefreshTimer() {
    _statusRefreshTimer?.cancel();

    // 远程模式需要定期轮询状态
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshStatus(silent: true);
    });

    debugPrint('⏰ [PlaybackProvider] 启动状态刷新定时器');
  }

  // 设备加载由 deviceProvider 负责

  Future<void> refreshStatus({bool silent = false}) async {
    // 🎵 本地播放模式不需要从服务器刷新状态
    if (_currentStrategy != null && _currentStrategy!.isLocalMode) {
      debugPrint('🎵 [PlaybackProvider] 本地播放模式，跳过状态刷新');

      // 从本地播放器获取状态
      try {
        final status = await _currentStrategy!.getCurrentStatus();
        if (status != null) {
          state = state.copyWith(
            currentMusic: status,
            hasLoaded: true,
            isLoading: false,
          );

          // 🖼️ 本地模式也需要自动搜索封面图
          debugPrint('🖼️ [PlaybackProvider-本地] 检查是否需要搜索封面');
          debugPrint('🖼️ [PlaybackProvider-本地] currentMusic: ${status.curMusic}');
          debugPrint('🖼️ [PlaybackProvider-本地] albumCoverUrl: ${state.albumCoverUrl}');

          if (status.curMusic.isNotEmpty &&
              (state.albumCoverUrl == null || state.albumCoverUrl!.isEmpty)) {
            debugPrint('🖼️ [PlaybackProvider-本地] ✅ 触发封面自动搜索: ${status.curMusic}');
            _autoFetchAlbumCover(status.curMusic).catchError((e) {
              debugPrint('🖼️ [AutoCover] 异步搜索封面失败: $e');
            });
          } else {
            debugPrint('🖼️ [PlaybackProvider-本地] ℹ️ 不需要搜索封面（已有封面或无歌曲）');
          }
        }
      } catch (e) {
        debugPrint('❌ [PlaybackProvider] 获取本地播放状态失败: $e');
      }
      return;
    }

    // 🎯 直连模式：从策略获取状态（不依赖 xiaomusic API）
    if (_currentStrategy is MiIoTDirectPlaybackStrategy) {
      debugPrint('🎵 [PlaybackProvider] 直连模式，从策略获取状态');

      try {
        final status = await _currentStrategy!.getCurrentStatus();
        debugPrint('🎵 [PlaybackProvider] 直连模式状态: ${status?.curMusic}, 播放中=${status?.isPlaying}');

        if (status != null) {
          // 🎯 检测歌曲切换
          bool isSongChanged = false;
          if (state.currentMusic != null && status.curMusic.isNotEmpty) {
            if (state.currentMusic!.curMusic != status.curMusic) {
              isSongChanged = true;
              debugPrint('🎵 [PlaybackProvider] 直连模式检测到歌曲切换');
            }
          }

          // 🔧 更新进度预测基准值（用于本地平滑预测）
          final serverOffset = status.offset;
          if (_lastServerOffset != null) {
            final diff = (serverOffset - _lastServerOffset!).abs();
            if (diff > 3) {
              debugPrint('🔄 [直连模式] 检测到进度跳跃，差异: ${diff}秒，重新校准');
            }
          }
          _lastServerOffset = serverOffset;
          _lastUpdateTime = DateTime.now();

          state = state.copyWith(
            currentMusic: status,
            hasLoaded: true,
            isLoading: silent ? state.isLoading : false,
            albumCoverUrl: isSongChanged ? null : state.albumCoverUrl,
          );

          // 🖼️ 自动搜索封面图
          if (status.curMusic.isNotEmpty &&
              (state.albumCoverUrl == null || state.albumCoverUrl!.isEmpty)) {
            debugPrint('🖼️ [PlaybackProvider-直连] ✅ 触发封面自动搜索: ${status.curMusic}');
            _autoFetchAlbumCover(status.curMusic).catchError((e) {
              debugPrint('🖼️ [AutoCover] 异步搜索封面失败: $e');
            });
          }

          // 🔧 启动进度预测定时器（让进度条平滑显示）
          _startProgressTimer(status.isPlaying);
          debugPrint('✅ [PlaybackProvider] 直连模式已启动进度预测定时器');
        }
      } catch (e) {
        debugPrint('❌ [PlaybackProvider] 获取直连模式状态失败: $e');
      }

      return;
    }

    // 远程模式：从服务器获取状态
    // 🔧 再次检查策略类型，防止延迟任务在切换后仍执行
    if (_currentStrategy == null || _currentStrategy!.isLocalMode) {
      debugPrint('🎵 [PlaybackProvider] 当前非远程模式，跳过远程状态刷新');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) {
      if (state.isLoading) {
        state = state.copyWith(isLoading: false, hasLoaded: true);
      } else {
        state = state.copyWith(hasLoaded: true);
      }
      return;
    }

    // 防止过于频繁的刷新请求
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!).inMilliseconds < 500) {
      print('🎵 跳过过于频繁的状态刷新请求');
      return;
    }
    _lastRefreshTime = now;

    try {
      if (!silent) {
        state = state.copyWith(isLoading: true);
      }
      print('🎵 正在获取播放状态...');

      // 保护期过滤：如果处于保护期且当前策略为本地模式，直接忽略远端刷新
      if (_deviceSwitchProtectionUntil != null &&
          DateTime.now().isBefore(_deviceSwitchProtectionUntil!) &&
          (_currentStrategy?.isLocalMode ?? false)) {
        debugPrint('🛡️ [PlaybackProvider] 保护期内，忽略远端状态刷新');
        return;
      }

      // 🔧 使用策略的 getCurrentStatus 方法,这样会自动更新通知栏
      final currentMusic = await _currentStrategy?.getCurrentStatus();
      print(
        '🎵 解析后的播放状态: 音乐=${currentMusic?.curMusic}, 播放中=${currentMusic?.isPlaying}, 进度=${currentMusic?.offset}/${currentMusic?.duration}',
      );

      final volumeResponse = await apiService.getVolume(did: selectedDid);
      print('🎵 音量响应: $volumeResponse');

      final volume = volumeResponse['volume'] as int? ?? state.volume;

      // 获取当前播放列表
      List<String> playlistSongs = [];
      try {
        final playlistResponse = await apiService.getCurrentPlaylist(
          did: selectedDid,
        );
        print('🎵 播放列表API响应: $playlistResponse');

        // 检查响应是否为 Map 类型
        if (playlistResponse is Map<String, dynamic>) {
          if (playlistResponse['cur_playlist'] != null) {
            final songs = playlistResponse['cur_playlist'];
            if (songs is List) {
              playlistSongs = songs.map((s) => s.toString()).toList();
              print('🎵 当前播放列表有 ${playlistSongs.length} 首歌曲');
            }
          }
        } else {
          // 如果返回的是字符串（如 "临时搜索列表"），记录日志但不报错
          print('🎵 播放列表响应为字符串: $playlistResponse');
        }
      } catch (e) {
        print('🎵 获取播放列表失败: $e');
        // 即使失败也继续，保留原有列表
        playlistSongs = state.currentPlaylistSongs;
      }

      print('🎵 最终播放状态: ${currentMusic?.curMusic ?? "无"}');
      print('🎵 当前音量: $volume');

      // 🎯 检测歌曲切换
      bool isSongChanged = false;
      if (state.currentMusic == null && currentMusic != null) {
        // 首次加载歌曲（从无到有）
        // 🔧 但不清除封面，因为可能是初始化时已经有封面缓存
        isSongChanged = false; // 改为 false，避免清除已有的封面
        print('🎵 首次加载歌曲: "${currentMusic.curMusic}"（保留已有封面）');
      } else if (state.currentMusic != null && currentMusic != null) {
        final oldSongName = state.currentMusic!.curMusic;
        final newSongName = currentMusic.curMusic;
        if (oldSongName != newSongName) {
          isSongChanged = true;
          print('🎵 检测到歌曲切换: "$oldSongName" -> "$newSongName"');
        }
      }

      // 智能进度同步校准机制
      bool needsRecalibration = false;
      bool useSmoothing = false;

      if (isSongChanged) {
        // 🎯 歌曲切换：立即重置进度基准
        needsRecalibration = true;
        print('🔄 歌曲已切换，重置进度基准');
      } else if (state.currentMusic != null && currentMusic != null) {
        final localOffset = state.currentMusic!.offset;
        final serverOffset = currentMusic.offset;
        final offsetDiff = (serverOffset - localOffset).abs();

        // 智能校准策略：
        // - 差异 > 5秒：立即重新校准（可能是跳转或切歌）
        // - 差异 2-5秒：使用平滑过渡
        // - 差异 < 2秒：正常预测继续
        if (offsetDiff > 5) {
          needsRecalibration = true;
          print('🔄 检测到大幅进度跳跃，差异: ${offsetDiff}秒，立即重新校准');
        } else if (offsetDiff > 2) {
          useSmoothing = true;
          print('🔄 检测到中等进度差异: ${offsetDiff}秒，使用平滑过渡');
        } else if (offsetDiff > 0.5) {
          print('🔄 微调进度，差异: ${offsetDiff}秒');
        }
      }

      // 🎯 如果歌曲切换，清除旧的封面图和收藏状态
      // 🔧 在更新状态前再次检查，防止在异步等待期间策略已切换
      if (_currentStrategy == null || _currentStrategy!.isLocalMode) {
        debugPrint('🎵 [PlaybackProvider] 策略已切换到本地模式，放弃远程状态更新');
        return;
      }

      // 🛡️ 乐观更新保护：如果在保护期内，保留本地的 isPlaying 状态
      PlayingMusic? finalMusic = currentMusic;
      if (_optimisticUpdateProtectionUntil != null &&
          DateTime.now().isBefore(_optimisticUpdateProtectionUntil!)) {
        debugPrint('🛡️ [PlaybackProvider] 保护期内，保留本地 isPlaying 状态');
        if (currentMusic != null && state.currentMusic != null) {
          // 使用本地的 isPlaying 状态，其他字段使用远程状态
          finalMusic = PlayingMusic(
            ret: currentMusic.ret,
            curMusic: currentMusic.curMusic,
            curPlaylist: currentMusic.curPlaylist,
            isPlaying: state.currentMusic!.isPlaying, // 🛡️ 保留本地状态
            offset: currentMusic.offset,
            duration: currentMusic.duration,
          );
        }
      } else if (_optimisticUpdateProtectionUntil != null) {
        // 保护期已结束，清除标记
        _optimisticUpdateProtectionUntil = null;
        debugPrint('🛡️ [PlaybackProvider] 保护期结束');
      }

      // 🎯 检查收藏状态（如果歌曲切换了）
      bool isFavorite = state.isFavorite;
      if (isSongChanged && currentMusic != null) {
        final playbackMode = ref.read(playbackModeProvider);
        if (playbackMode == PlaybackMode.miIoTDirect) {
          // 直连模式：检查本地收藏
          final favoriteService = DirectModeFavoriteService();
          isFavorite = await favoriteService.isFavorite(currentMusic.curMusic);
          debugPrint('🎯 [收藏检查] 直连模式 - ${currentMusic.curMusic}: ${isFavorite ? "已收藏" : "未收藏"}');
        } else {
          // xiaomusic模式：重置为false（由服务器端管理）
          isFavorite = false;
        }
      }

      state = state.copyWith(
        currentMusic: finalMusic,
        volume: volume,
        error: null,
        isLoading: silent ? state.isLoading : false,
        hasLoaded: true,
        albumCoverUrl: isSongChanged ? null : state.albumCoverUrl,
        isFavorite: isFavorite,
        currentPlaylistSongs: playlistSongs,
      );

      // 智能更新预测基准
      if (needsRecalibration) {
        // 立即重新校准
        _lastServerOffset = currentMusic?.offset ?? 0;
        _lastUpdateTime = DateTime.now();
        print('⏰ 立即重新校准，基准进度: ${_lastServerOffset}秒');
      } else if (useSmoothing) {
        // 使用加权平均进行平滑过渡
        final serverOffset = currentMusic?.offset ?? 0;
        final currentBase = _lastServerOffset ?? 0;
        _lastServerOffset = (currentBase * 0.3 + serverOffset * 0.7).round();
        _lastUpdateTime = DateTime.now();
        print('🔄 平滑过渡到新进度: ${_lastServerOffset}秒');
      } else if (currentMusic != null) {
        // 正常更新，保持预测连续性
        final timeSinceLastUpdate =
            _lastUpdateTime != null
                ? DateTime.now().difference(_lastUpdateTime!).inSeconds
                : 0;

        // 只有当服务器进度合理时才更新基准
        final serverOffset = currentMusic.offset;
        final expectedOffset = (_lastServerOffset ?? 0) + timeSinceLastUpdate;

        if ((serverOffset - expectedOffset).abs() <= 3) {
          _lastServerOffset = serverOffset;
          _lastUpdateTime = DateTime.now();
        }
      }

      // 🖼️ 自动搜索封面图（适用于服务端本地歌曲）
      debugPrint('🖼️ [PlaybackProvider] 检查是否需要搜索封面');
      debugPrint('🖼️ [PlaybackProvider] currentMusic: ${currentMusic?.curMusic}');
      debugPrint('🖼️ [PlaybackProvider] albumCoverUrl: ${state.albumCoverUrl}');
      debugPrint('🖼️ [PlaybackProvider] isSongChanged: $isSongChanged');

      if (currentMusic != null &&
          (state.albumCoverUrl == null || state.albumCoverUrl!.isEmpty)) {
        debugPrint('🖼️ [PlaybackProvider] ✅ 触发封面自动搜索: ${currentMusic.curMusic}');
        // 异步搜索封面图，不阻塞主流程
        _autoFetchAlbumCover(currentMusic.curMusic).catchError((e) {
          print('🖼️ [AutoCover] 异步搜索封面失败: $e');
        });
      } else {
        debugPrint('🖼️ [PlaybackProvider] ℹ️ 不需要搜索封面（已有封面或无歌曲）');
      }

      // 🔧 只有 xiaomusic 远程模式需要启动进度定时器
      // - 本地模式：通过 statusStream 自动更新（不需要定时器）
      // - 直连模式：通过策略内部的 _pollPlayStatus() 轮询更新（不需要定时器）
      // - xiaomusic 远程模式：需要本地预测进度（需要定时器）
      if (_currentStrategy != null &&
          !_currentStrategy!.isLocalMode &&
          _currentStrategy is! MiIoTDirectPlaybackStrategy) {
        _startProgressTimer(currentMusic?.isPlaying ?? false);
        debugPrint('✅ [PlaybackProvider] xiaomusic远程模式已启动进度预测定时器');
      } else {
        debugPrint('ℹ️ [PlaybackProvider] 当前模式不需要进度预测定时器（${_currentStrategy?.runtimeType ?? "未初始化"}）');
      }

      // 保护期结束后清理标记
      if (_deviceSwitchProtectionUntil != null &&
          DateTime.now().isAfter(_deviceSwitchProtectionUntil!)) {
        _deviceSwitchProtectionUntil = null;
      }
    } catch (e) {
      print('🎵 获取播放状态失败: $e');

      String errorMessage = '获取播放状态失败';
      if (e.toString().contains('Did not exist')) {
        errorMessage = '设备不存在或离线';
        ref.read(deviceProvider.notifier).selectDevice('');
        state = state.copyWith(error: errorMessage);
      } else {
        state = state.copyWith(error: errorMessage);
      }
      state = state.copyWith(
        isLoading: silent ? state.isLoading : false,
        hasLoaded: true,
      );
    }
  }

  Future<void> shutdown() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      state = state.copyWith(isLoading: true);

      print('🎵 执行关机命令');

      await apiService.shutdown(did: selectedDid);

      // 关机后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 关机失败: $e');
      state = state.copyWith(isLoading: false, error: '关机失败: ${e.toString()}');
    }
  }

  Future<void> pauseMusic() async {
    // 🎵 使用策略模式（与 pause() 方法相同）
    await pause();
  }

  Future<void> resumeMusic() async {
    // 🎵 使用策略模式（与 play() 方法相同）
    await play();
  }

  // 🎵 内部实际的播放方法
  Future<void> play() async {
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化');
      debugPrint('❌ [PlaybackProvider] 提示：请检查是否已登录并选择设备');

      // 🎯 给用户友好的错误提示
      final playbackMode = ref.read(playbackModeProvider);
      if (playbackMode == PlaybackMode.miIoTDirect) {
        final directState = ref.read(directModeProvider);
        if (directState is! DirectModeAuthenticated) {
          state = state.copyWith(error: '请先登录小米账号（直连模式）');
        } else if (directState.playbackDeviceType.isEmpty) { // 🔧 修复：检查 playbackDeviceType
          state = state.copyWith(error: '请先选择播放设备（本地播放或小爱音箱）');
        } else {
          state = state.copyWith(error: '播放策略初始化失败，请尝试重新启动应用');
        }
      } else {
        final deviceState = ref.read(deviceProvider);
        if (deviceState.selectedDeviceId == null) {
          state = state.copyWith(error: '请先选择一个播放设备');
        } else {
          state = state.copyWith(error: '播放策略初始化失败，请检查服务器连接');
        }
      }
      return;
    }

    // 🎯 乐观更新：先更新本地UI状态
    if (state.currentMusic != null) {
      final updatedMusic = PlayingMusic(
        ret: state.currentMusic!.ret,
        curMusic: state.currentMusic!.curMusic,
        curPlaylist: state.currentMusic!.curPlaylist,
        isPlaying: true, // 立即显示为播放状态
        offset: state.currentMusic!.offset,
        duration: state.currentMusic!.duration,
      );
      state = state.copyWith(currentMusic: updatedMusic);

      // 🎯 设置乐观更新保护期（2秒内不接受远程状态的 isPlaying 更新）
      _optimisticUpdateProtectionUntil = DateTime.now().add(const Duration(seconds: 2));
      debugPrint('🛡️ [PlaybackProvider] 设置乐观更新保护期: 2秒');

      // 🔧 只有 xiaomusic 远程模式需要更新进度定时器
      // - 本地模式：通过statusStream自动更新（不需要）
      // - 直连模式：通过策略轮询更新（不需要）
      // - xiaomusic远程模式：需要本地预测进度
      if (!_currentStrategy!.isLocalMode && _currentStrategy is! MiIoTDirectPlaybackStrategy) {
        _lastServerOffset = state.currentMusic!.offset;
        _lastUpdateTime = DateTime.now();
        _startProgressTimer(true);
      }
    }

    try {
      debugPrint('🎵 [PlaybackProvider] 执行播放');
      await _currentStrategy!.play();

      // 🔄 远程模式需要延迟同步真实状态
      if (!_currentStrategy!.isLocalMode) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          refreshStatus(silent: true);
        });
      }
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 播放失败: $e');
      if (!_currentStrategy!.isLocalMode) {
        refreshStatus(silent: true);
      }
      state = state.copyWith(error: '播放失败: ${e.toString()}');
    }
  }

  // 🎵 内部实际的暂停方法
  Future<void> pause() async {
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化');
      debugPrint('❌ [PlaybackProvider] 提示：请检查是否已登录并选择设备');

      // 🎯 给用户友好的错误提示
      final playbackMode = ref.read(playbackModeProvider);
      if (playbackMode == PlaybackMode.miIoTDirect) {
        final directState = ref.read(directModeProvider);
        if (directState is! DirectModeAuthenticated) {
          state = state.copyWith(error: '请先登录小米账号（直连模式）');
        } else if (directState.playbackDeviceType.isEmpty) { // 🔧 修复：检查 playbackDeviceType
          state = state.copyWith(error: '请先选择播放设备（本地播放或小爱音箱）');
        } else {
          state = state.copyWith(error: '播放策略初始化失败，请尝试重新启动应用');
        }
      } else {
        final deviceState = ref.read(deviceProvider);
        if (deviceState.selectedDeviceId == null) {
          state = state.copyWith(error: '请先选择一个播放设备');
        } else {
          state = state.copyWith(error: '播放策略初始化失败，请检查服务器连接');
        }
      }
      return;
    }

    // 🎯 乐观更新：先更新本地UI状态
    if (state.currentMusic != null) {
      final updatedMusic = PlayingMusic(
        ret: state.currentMusic!.ret,
        curMusic: state.currentMusic!.curMusic,
        curPlaylist: state.currentMusic!.curPlaylist,
        isPlaying: false, // 立即显示为暂停状态
        offset: state.currentMusic!.offset,
        duration: state.currentMusic!.duration,
      );
      state = state.copyWith(currentMusic: updatedMusic);

      // 🎯 设置乐观更新保护期（2秒内不接受远程状态的 isPlaying 更新）
      _optimisticUpdateProtectionUntil = DateTime.now().add(const Duration(seconds: 2));
      debugPrint('🛡️ [PlaybackProvider] 设置乐观更新保护期: 2秒');

      // 🔧 只有 xiaomusic 远程模式需要更新进度定时器
      // - 本地模式：通过statusStream自动更新（不需要）
      // - 直连模式：通过策略轮询更新（不需要）
      if (!_currentStrategy!.isLocalMode && _currentStrategy is! MiIoTDirectPlaybackStrategy) {
        _startProgressTimer(false);
      }
    }

    try {
      debugPrint('🎵 [PlaybackProvider] 执行暂停');
      await _currentStrategy!.pause();

      // 🔄 远程模式需要延迟同步真实状态
      if (!_currentStrategy!.isLocalMode) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          refreshStatus(silent: true);
        });
      }
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 暂停失败: $e');
      if (!_currentStrategy!.isLocalMode) {
        refreshStatus(silent: true);
      }
      state = state.copyWith(error: '暂停失败: ${e.toString()}');
    }
  }

  Future<void> playPause() async {
    // 🎵 使用策略模式
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化');
      return;
    }

    try {
      final isPlaying = state.currentMusic?.isPlaying ?? false;
      debugPrint('🎵 执行播放控制命令: ${isPlaying ? "暂停" : "播放歌曲"}');

      // 🎯 立即乐观更新UI，提升响应性
      if (state.currentMusic != null) {
        final updatedMusic = PlayingMusic(
          ret: state.currentMusic!.ret,
          curMusic: state.currentMusic!.curMusic,
          curPlaylist: state.currentMusic!.curPlaylist,
          isPlaying: !isPlaying, // 切换播放状态
          offset: state.currentMusic!.offset,
          duration: state.currentMusic!.duration,
        );
        state = state.copyWith(currentMusic: updatedMusic, isLoading: false);

        // 🔧 只有 xiaomusic 远程模式需要更新进度定时器
        // - 本地模式：通过statusStream自动更新（不需要）
        // - 直连模式：通过策略轮询更新（不需要）
        if (!_currentStrategy!.isLocalMode && _currentStrategy is! MiIoTDirectPlaybackStrategy) {
          _startProgressTimer(!isPlaying);
          if (!isPlaying) {
            _lastServerOffset = state.currentMusic!.offset;
            _lastUpdateTime = DateTime.now();
          }
        }
      }

      // 异步执行实际命令（通过策略）
      if (isPlaying) {
        await _currentStrategy!.pause();
      } else {
        await _currentStrategy!.play();
      }

      // 🔄 远程模式需要延迟同步真实状态
      if (!_currentStrategy!.isLocalMode) {
        Future.delayed(
          const Duration(milliseconds: 1500),
          () => refreshStatus(silent: true),
        );
      }
    } catch (e) {
      print('🎵 播放控制失败: $e');
      // 如果请求失败，恢复原状态
      Future.delayed(
        const Duration(milliseconds: 500),
        () => refreshStatus(silent: true),
      );
      state = state.copyWith(
        isLoading: false,
        error: '播放控制失败: ${e.toString()}',
      );
    }
  }

  Future<void> previous() async {
    // 🎵 使用策略模式
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化');
      debugPrint('❌ [PlaybackProvider] 提示：请检查是否已登录并选择设备');

      // 🎯 给用户友好的错误提示
      final playbackMode = ref.read(playbackModeProvider);
      if (playbackMode == PlaybackMode.miIoTDirect) {
        state = state.copyWith(error: '请先选择小爱音箱设备（直连模式）');
      } else {
        state = state.copyWith(error: '请先选择播放设备');
      }
      return;
    }

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('🎵 执行上一首命令');

      // 🎯 根据播放模式执行不同逻辑
      switch (state.playMode) {
        case PlayMode.single:
          // 单曲循环：重新播放当前歌曲
          debugPrint('🎵 [播放模式] 单曲循环 - 重新播放当前歌曲');
          await _replayCurrentSong();
          break;

        case PlayMode.random:
          // 随机播放：从历史记录中返回上一首
          debugPrint('🎵 [播放模式] 随机播放 - 从历史记录返回');
          await _playPreviousFromHistory();
          break;

        default:
          // 其他模式：使用策略的正常逻辑
          debugPrint('🎵 [播放模式] ${state.playMode.displayName} - 使用策略逻辑');

          // 🎯 优先级1：直连模式 + 有播放队列 → 使用新队列逻辑
          final playbackMode = ref.read(playbackModeProvider);
          if (playbackMode == PlaybackMode.miIoTDirect) {
            final queueState = ref.read(playbackQueueProvider);
            if (queueState.queue != null && queueState.queue!.items.isNotEmpty) {
              debugPrint('🎵 [PlaybackProvider] 直连模式检测到播放队列');
              final prevItem = ref.read(playbackQueueProvider.notifier).previous();
              if (prevItem != null) {
                debugPrint('🎵 [PlaybackProvider] 使用队列播放上一首: ${prevItem.title}');
                await _playFromQueueItem(prevItem);

                // 等待播放状态更新
                await Future.delayed(const Duration(milliseconds: 1000));
                await refreshStatus();

                state = state.copyWith(isLoading: false);
                return; // ✅ 使用新逻辑成功，直接返回
              } else {
                debugPrint('⚠️ [PlaybackProvider] 队列已到开头（顺序播放模式）');
                state = state.copyWith(isLoading: false, error: '已是第一首');
                return;
              }
            } else {
              debugPrint('🎵 [PlaybackProvider] 直连模式无队列，使用旧逻辑');
            }
          }

          // 🎯 优先级2：使用旧的策略逻辑（xiaomusic/本地播放/旧逻辑）
          debugPrint('🎵 [PlaybackProvider] 使用策略模式播放（xiaomusic/本地/旧逻辑）');
          await _currentStrategy!.previous(); // ✅ xiaomusic 和本地播放完全不受影响

          // 等待命令执行后刷新状态
          await Future.delayed(const Duration(milliseconds: 1000));

          // 🔄 远程模式需要刷新状态，本地模式会自动更新
          if (!_currentStrategy!.isLocalMode) {
            await refreshStatus();
          }
          break;
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 上一首失败: $e');
      state = state.copyWith(isLoading: false, error: '上一首失败: ${e.toString()}');
    }
  }

  Future<void> next() async {
    // 🎵 使用策略模式
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化');
      debugPrint('❌ [PlaybackProvider] 提示：请检查是否已登录并选择设备');

      // 🎯 给用户友好的错误提示
      final playbackMode = ref.read(playbackModeProvider);
      if (playbackMode == PlaybackMode.miIoTDirect) {
        state = state.copyWith(error: '请先选择小爱音箱设备（直连模式）');
      } else {
        state = state.copyWith(error: '请先选择播放设备');
      }
      return;
    }

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('🎵 执行下一首命令');

      // 🎯 根据播放模式执行不同逻辑
      switch (state.playMode) {
        case PlayMode.single:
          // 单曲循环：重新播放当前歌曲
          debugPrint('🎵 [播放模式] 单曲循环 - 重新播放当前歌曲');
          await _replayCurrentSong();
          break;

        case PlayMode.random:
          // 随机播放：从歌单中随机选择下一首（排除当前）
          debugPrint('🎵 [播放模式] 随机播放 - 随机选择下一首');
          await _playRandomSong();
          break;

        default:
          // 其他模式：使用策略的正常逻辑
          debugPrint('🎵 [播放模式] ${state.playMode.displayName} - 使用策略逻辑');

          // 🎯 优先级1：直连模式 + 有播放队列 → 使用新队列逻辑
          final playbackMode = ref.read(playbackModeProvider);
          if (playbackMode == PlaybackMode.miIoTDirect) {
            final queueState = ref.read(playbackQueueProvider);
            if (queueState.queue != null && queueState.queue!.items.isNotEmpty) {
              debugPrint('🎵 [PlaybackProvider] 直连模式检测到播放队列');
              final nextItem = ref.read(playbackQueueProvider.notifier).next();
              if (nextItem != null) {
                debugPrint('🎵 [PlaybackProvider] 使用队列播放下一首: ${nextItem.title}');
                await _playFromQueueItem(nextItem);

                // 等待播放状态更新
                await Future.delayed(const Duration(milliseconds: 1000));
                await refreshStatus();

                state = state.copyWith(isLoading: false);
                return; // ✅ 使用新逻辑成功，直接返回
              } else {
                debugPrint('⚠️ [PlaybackProvider] 队列已到末尾（顺序播放模式）');
                state = state.copyWith(isLoading: false, error: '已是最后一首');
                return;
              }
            } else {
              debugPrint('🎵 [PlaybackProvider] 直连模式无队列，使用旧逻辑');
            }
          }

          // 🎯 优先级2：使用旧的策略逻辑（xiaomusic/本地播放/旧逻辑）
          debugPrint('🎵 [PlaybackProvider] 使用策略模式播放（xiaomusic/本地/旧逻辑）');
          await _currentStrategy!.next(); // ✅ xiaomusic 和本地播放完全不受影响

          // 等待命令执行后刷新状态
          await Future.delayed(const Duration(milliseconds: 1000));

          // 🔄 远程模式需要刷新状态，本地模式会自动更新
          if (!_currentStrategy!.isLocalMode) {
            await refreshStatus();
          }
          break;
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 下一首失败: $e');
      state = state.copyWith(isLoading: false, error: '下一首失败: ${e.toString()}');
    }
  }

  Future<void> setVolume(int volume) async {
    // 🎵 使用策略模式
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化（音量调节）');
      debugPrint('❌ [PlaybackProvider] 提示：音量调节需要先选择设备');

      // 🎯 静默失败，不弹出错误提示（避免拖动音量条时频繁报错）
      // 但仍然更新本地UI音量值
      state = state.copyWith(volume: volume);
      return;
    }

    try {
      await _currentStrategy!.setVolume(volume);
      state = state.copyWith(volume: volume);
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 设置音量失败: $e');
      // 音量设置失败时也不弹出错误，只记录日志
      // state = state.copyWith(error: e.toString());
    }
  }

  // 即时更新 UI 的本地音量值，不触发后端调用
  void setVolumeLocal(int volume) {
    state = state.copyWith(volume: volume);
  }

  Future<void> seekTo(int seconds) async {
    // 🎵 使用策略模式
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化');
      return;
    }

    try {
      // 🎯 乐观更新：先更新本地UI状态，提升响应性
      if (state.currentMusic != null) {
        final updatedMusic = PlayingMusic(
          ret: state.currentMusic!.ret,
          curMusic: state.currentMusic!.curMusic,
          curPlaylist: state.currentMusic!.curPlaylist,
          isPlaying: state.currentMusic!.isPlaying,
          offset: seconds, // 立即更新进度
          duration: state.currentMusic!.duration,
        );
        state = state.copyWith(currentMusic: updatedMusic);
      }

      await _currentStrategy!.seekTo(seconds);

      // 🔧 本地模式会通过 statusStream 自动更新，远程模式需要手动刷新
      if (!_currentStrategy!.isLocalMode) {
        await Future.delayed(const Duration(milliseconds: 500));
        await refreshStatus(silent: true);
      }
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 跳转失败: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> playMusic({
    required String deviceId,
    String? musicName,
    String? searchKey,
    String? url, // 新增：支持直接传入 URL（在线音乐）
    String? albumCoverUrl, // 🖼️ 新增：支持直接传入封面图URL（搜索音乐）
    List<Music>? playlist, // 🎵 新增：播放列表（用于本地播放上一曲/下一曲）
    int? startIndex, // 🎵 新增：开始播放的索引
  }) async {
    // 🎵 使用策略模式播放
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化，尝试切换设备');

      // 如果策略未初始化，尝试根据设备ID切换
      final deviceState = ref.read(deviceProvider);
      if (deviceState.devices.isNotEmpty) {
        await _switchStrategy(deviceId, deviceState.devices);
      } else {
        state = state.copyWith(error: '播放策略未初始化');
        return;
      }
    }

    try {
      debugPrint('🎵 [PlaybackProvider] 开始播放音乐: $musicName, 设备ID: $deviceId');

      // 🔧 修复：切歌时立即停止本地预测定时器，重置进度状态
      // 避免旧的预测定时器导致进度条跳动
      _localProgressTimer?.cancel();
      _localProgressTimer = null;
      _lastServerOffset = 0;
      _lastUpdateTime = DateTime.now();
      _lastProgressUpdate = null;

      // 🎯 乐观更新：立即更新UI显示歌曲信息，不等待音箱响应
      if (musicName != null && musicName.isNotEmpty) {
        final optimisticMusic = PlayingMusic(
          ret: 'OK',
          curMusic: musicName,
          curPlaylist: '',
          isPlaying: true, // 乐观地认为会播放成功
          duration: 0, // 时长暂时未知
          offset: 0, // 进度从0开始
        );

        state = state.copyWith(
          currentMusic: optimisticMusic,
          isLoading: true,
          error: null,
          albumCoverUrl: albumCoverUrl, // 如果有封面图，立即显示
        );
        debugPrint('✨ [PlaybackProvider] 乐观更新UI: $musicName');
      } else {
        state = state.copyWith(isLoading: true, error: null);
      }

      // 🖼️ 切歌时重置防抖标记，允许新歌曲搜索封面
      _lastCoverSearchSong = null;

      // 🎵 如果提供了播放列表，设置到策略中（本地和直连模式都支持）
      if (_currentStrategy != null && playlist != null && playlist.isNotEmpty) {
        debugPrint('🎵 [PlaybackProvider] 设置播放列表: ${playlist.length} 首歌曲');

        // 如果没有指定索引，尝试找到当前播放歌曲的索引
        int playIndex = startIndex ?? 0;
        if (musicName != null && musicName.isNotEmpty && startIndex == null) {
          final index = playlist.indexWhere((m) => m.name == musicName);
          if (index >= 0) {
            playIndex = index;
          }
        }

        if (_currentStrategy!.isLocalMode) {
          // 本地播放模式
          final localStrategy = _currentStrategy as LocalPlaybackStrategy;
          localStrategy.setPlaylist(playlist, startIndex: playIndex);
        } else if (_currentStrategy is MiIoTDirectPlaybackStrategy) {
          // 直连模式
          final directStrategy = _currentStrategy as MiIoTDirectPlaybackStrategy;
          directStrategy.setPlaylist(playlist, startIndex: playIndex);
        }

        debugPrint('🎵 [PlaybackProvider] 播放列表已设置，开始索引: $playIndex');
      }

      // 使用策略播放
      await _currentStrategy!.playMusic(musicName: musicName ?? '', url: url);

      debugPrint('✅ [PlaybackProvider] 播放请求成功');

      // 🖼️ 处理封面图（4种情况）
      if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
        // 情况1: 在线搜索音乐 - 直接使用搜索结果的封面图
        debugPrint('🖼️ [PlaybackProvider] 使用搜索结果的封面图: $albumCoverUrl');
        updateAlbumCover(albumCoverUrl);
      } else if (musicName != null && musicName.isNotEmpty) {
        // 情况2/3/4: 服务器音乐 / 本地音乐 / 直连模式 - 都需要自动搜索封面
        debugPrint('🖼️ [PlaybackProvider] 自动搜索封面: $musicName (当前策略: ${_currentStrategy?.runtimeType})');
        _autoFetchAlbumCover(musicName).catchError((e) {
          debugPrint('🖼️ [AutoCover] 搜索封面失败: $e');
        });
      }

      // 等待一下让播放状态更新
      await Future.delayed(const Duration(milliseconds: 1000));

      // 🔄 远程模式需要刷新状态，本地模式会自动更新
      if (_currentStrategy != null && !_currentStrategy!.isLocalMode) {
        await refreshStatus();
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 播放失败: $e');
      String errorMessage = '播放失败';

      if (e.toString().contains('Did not exist')) {
        errorMessage = '设备不存在或离线，请检查设备状态或重新选择设备';
      } else if (e.toString().contains('Connection')) {
        errorMessage = '网络连接失败，请检查服务器连接';
      } else {
        errorMessage = '播放失败: ${e.toString()}';
      }

      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  /// 播放在线搜索结果（新方法，支持多种格式）
  Future<void> playOnlineResult({
    required String deviceId,
    OnlineMusicResult? singleResult,
    List<OnlineMusicResult>? resultList,
    List<Map<String, dynamic>>? rawResults,
    String playlistName = "在线播放",
    Map<String, String>? defaultHeaders,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      state = state.copyWith(error: 'API 服务未初始化');
      return;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      String songInfo = "";
      if (singleResult != null) {
        songInfo = "${singleResult.title} - ${singleResult.author}";
      } else if (resultList != null && resultList.isNotEmpty) {
        songInfo = "${resultList.first.title} - ${resultList.first.author}";
      } else if (rawResults != null && rawResults.isNotEmpty) {
        final firstResult = rawResults.first;
        final title = firstResult['title'] ?? firstResult['name'] ?? '未知标题';
        final artist =
            firstResult['artist'] ?? firstResult['singer'] ?? '未知艺术家';
        songInfo = "$title - $artist";
      }

      print('🎵 开始播放在线搜索结果: $songInfo, 设备ID: $deviceId');

      await apiService.playOnlineSearchResult(
        did: deviceId,
        singleResult: singleResult,
        resultList: resultList,
        rawResults: rawResults,
        playlistName: playlistName,
        defaultHeaders: defaultHeaders,
      );

      print('🎵 在线播放请求成功');

      // 等待播放状态更新
      await Future.delayed(const Duration(milliseconds: 1500));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 在线播放失败: $e');
      String errorMessage = '在线播放失败';

      if (e.toString().contains('Did not exist')) {
        errorMessage = '设备不存在或离线，请检查设备状态或重新选择设备';
      } else if (e.toString().contains('Connection')) {
        errorMessage = '网络连接失败，请检查服务器连接';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = '音乐格式不支持，请尝试其他歌曲';
      } else {
        errorMessage = '在线播放失败: ${e.toString()}';
      }

      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  // 选设备交由 deviceProvider

  void _startProgressTimer(bool isPlaying) {
    _statusRefreshTimer?.cancel();
    _localProgressTimer?.cancel();

    if (isPlaying && state.currentMusic != null) {
      // 智能刷新策略：根据播放状态调整刷新频率
      final duration = state.currentMusic?.duration ?? 0;
      final refreshInterval = duration > 300 ? 8 : 5; // 长歌曲减少刷新频率

      _statusRefreshTimer = Timer.periodic(Duration(seconds: refreshInterval), (
        _,
      ) {
        refreshStatus(silent: true);
      });

      // 更平滑的本地进度更新
      _localProgressTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) {
        _updateLocalProgress();
      });

      print('⏰ 启动智能进度定时器，刷新间隔: ${refreshInterval}秒');
    } else {
      print('⏸️ 停止进度定时器');
    }
  }

  void _updateLocalProgress() {
    if (state.currentMusic == null ||
        !state.currentMusic!.isPlaying ||
        _lastUpdateTime == null ||
        _lastServerOffset == null) {
      return;
    }

    final now = DateTime.now();
    final elapsedSeconds =
        now.difference(_lastUpdateTime!).inMilliseconds / 1000.0;

    // 更精确的进度预测，支持小数秒
    final predictedOffset = (_lastServerOffset! + elapsedSeconds).clamp(
      0.0,
      double.infinity,
    );
    final duration = state.currentMusic!.duration;
    final currentOffset = state.currentMusic!.offset;

    // 智能更新策略：
    // 1. 确保进度不超过总时长
    // 2. 避免倒退（除非是合理的小幅调整）
    // 3. 限制更新频率避免UI抖动
    final newOffset = predictedOffset.floor();

    if (newOffset < duration &&
        (newOffset > currentOffset || (currentOffset - newOffset).abs() <= 1)) {
      // 避免频繁的微小更新
      if ((newOffset - currentOffset).abs() >= 1 ||
          now.difference(_lastProgressUpdate ?? DateTime(0)).inMilliseconds >=
              500) {
        final updatedMusic = PlayingMusic(
          ret: state.currentMusic!.ret,
          curMusic: state.currentMusic!.curMusic,
          curPlaylist: state.currentMusic!.curPlaylist,
          isPlaying: state.currentMusic!.isPlaying,
          offset: newOffset,
          duration: state.currentMusic!.duration,
        );

        state = state.copyWith(currentMusic: updatedMusic);
        _lastProgressUpdate = now;
      }
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 🖼️ 从本地存储加载播放缓存
  Future<void> _loadLocalPlayback() async {
    debugPrint('🔧 [PlaybackProvider] 开始加载播放缓存');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_localPlaybackKey);
      debugPrint('🔧 [PlaybackProvider] 缓存内容: ${jsonStr?.substring(0, jsonStr.length > 100 ? 100 : jsonStr.length) ?? "null"}');

      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('🔧 [PlaybackProvider] 没有播放缓存，跳过恢复');
        return;
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final pm = PlayingMusic(
        ret: data['ret'] as String? ?? 'OK',
        curMusic: data['curMusic'] as String? ?? '',
        curPlaylist: (data['curPlaylist'] as String?) ?? '',
        isPlaying: false, // 恢复时总是暂停状态
        offset: data['offset'] as int? ?? 0,
        duration: data['duration'] as int? ?? 0,
      );

      // 更新UI状态
      state = state.copyWith(
        currentMusic: pm,
        hasLoaded: true,
        isLoading: false,
      );

      // 🔧 保存到缓存变量，等待策略初始化后恢复
      _cachedPlayingMusic = pm;
      _cachedMusicUrl = prefs.getString(_localPlaybackUrlKey);
      _cachedCoverUrl = prefs.getString(_localPlaybackCoverKey);
      _cachedOffset = pm.offset;

      debugPrint('🔧 [PlaybackProvider] 已加载播放缓存，等待策略初始化后恢复');
      debugPrint('   - 歌曲名: ${pm.curMusic}');
      debugPrint('   - URL: ${_cachedMusicUrl ?? "未保存"}');
      debugPrint('   - 进度: ${pm.offset}s / ${pm.duration}s');
      debugPrint('   - 封面: ${_cachedCoverUrl ?? "未保存"}');
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 加载播放缓存失败: $e');
    }
  }

  Future<void> _saveLocalPlayback(PlayingMusic status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'ret': status.ret,
        'curMusic': status.curMusic,
        'curPlaylist': status.curPlaylist,
        'isPlaying': status.isPlaying,
        'offset': status.offset,
        'duration': status.duration,
      };
      await prefs.setString(_localPlaybackKey, jsonEncode(data));

      // 保存 URL
      final url = (_currentStrategy is LocalPlaybackStrategy)
          ? (_currentStrategy as LocalPlaybackStrategy).currentMusicUrl
          : null;

      debugPrint('💾 [PlaybackProvider] 保存播放缓存');
      debugPrint('   - 歌曲名: ${status.curMusic}');
      debugPrint('   - URL: ${url ?? "无"}');
      debugPrint('   - 进度: ${status.offset}s / ${status.duration}s');

      if (url != null && url.isNotEmpty) {
        await prefs.setString(_localPlaybackUrlKey, url);
        debugPrint('   - ✅ URL 已保存');
      } else {
        debugPrint('   - ⚠️ URL 为空，未保存');
      }

      if (state.albumCoverUrl != null && state.albumCoverUrl!.isNotEmpty) {
        await prefs.setString(_localPlaybackCoverKey, state.albumCoverUrl!);
        debugPrint('   - ✅ 封面已保存');
      }
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 保存播放缓存失败: $e');
    }
  }

  /// 💾 保存直连模式播放状态（专用于直连模式）
  Future<void> _saveDirectModePlayback(PlayingMusic status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'ret': status.ret,
        'curMusic': status.curMusic,
        'curPlaylist': status.curPlaylist,
        'isPlaying': status.isPlaying,
        'offset': status.offset,
        'duration': status.duration,
      };
      await prefs.setString(_directModePlaybackKey, jsonEncode(data));

      debugPrint('💾 [PlaybackProvider-DirectMode] 保存直连模式播放状态');
      debugPrint('   - 歌曲名: ${status.curMusic}');
      debugPrint('   - 播放状态: ${status.isPlaying ? "播放中" : "已暂停"}');
      debugPrint('   - 进度: ${status.offset}s / ${status.duration}s');

      // 保存封面图
      if (state.albumCoverUrl != null && state.albumCoverUrl!.isNotEmpty) {
        await prefs.setString(_directModePlaybackCoverKey, state.albumCoverUrl!);
        debugPrint('   - ✅ 封面已保存');
      }
    } catch (e) {
      debugPrint('❌ [PlaybackProvider-DirectMode] 保存播放状态失败: $e');
    }
  }

  /// 🔄 恢复直连模式播放状态（专用于直连模式）
  Future<void> _restoreDirectModePlayback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_directModePlaybackKey);

      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('⚠️ [PlaybackProvider-DirectMode] 没有缓存的播放状态');
        return;
      }

      debugPrint('🔄 [PlaybackProvider-DirectMode] 开始恢复播放状态');

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final cachedMusic = PlayingMusic(
        ret: data['ret'] as String? ?? 'OK',
        curMusic: data['curMusic'] as String? ?? '',
        curPlaylist: data['curPlaylist'] as String? ?? '直连播放',
        isPlaying: false, // 恢复时总是暂停状态
        offset: data['offset'] as int? ?? 0,
        duration: data['duration'] as int? ?? 0,
      );

      // 恢复封面图
      final cachedCover = prefs.getString(_directModePlaybackCoverKey);

      // 更新UI状态
      state = state.copyWith(
        currentMusic: cachedMusic,
        albumCoverUrl: cachedCover,
        hasLoaded: true,
        isLoading: false,
      );

      debugPrint('✅ [PlaybackProvider-DirectMode] 播放状态已恢复');
      debugPrint('   - 歌曲名: ${cachedMusic.curMusic}');
      debugPrint('   - 进度: ${cachedMusic.offset}s / ${cachedMusic.duration}s');
      debugPrint('   - 封面: ${cachedCover ?? "无"}');

      // 🎯 注意：不需要更新策略内部状态，因为轮询会自动更新
      // 只是恢复 UI 显示，让用户看到上次播放的内容
    } catch (e) {
      debugPrint('❌ [PlaybackProvider-DirectMode] 恢复播放状态失败: $e');
    }
  }

  void updateAlbumCover(String coverUrl) {
    if (coverUrl.isNotEmpty) {
      state = state.copyWith(albumCoverUrl: coverUrl);
      print('[Playback] 🖼️  封面图已更新: $coverUrl');

      // 🎵 根据策略类型更新通知栏封面
      if (_currentStrategy is LocalPlaybackStrategy) {
        // 本地播放模式
        (_currentStrategy as LocalPlaybackStrategy).setAlbumCover(coverUrl);
        (_currentStrategy as LocalPlaybackStrategy).refreshNotification();
      } else if (_currentStrategy is RemotePlaybackStrategy) {
        // xiaomusic 远程播放模式
        (_currentStrategy as RemotePlaybackStrategy).updateAlbumCover(coverUrl);
      } else if (_currentStrategy is MiIoTDirectPlaybackStrategy) {
        // 🎯 直连模式：也要更新封面图到策略，用于通知栏显示
        (_currentStrategy as MiIoTDirectPlaybackStrategy).setAlbumCover(coverUrl);
        debugPrint('🖼️ [PlaybackProvider] 直连模式封面图已传给策略: $coverUrl');
      }
    }
  }

  /// 🖼️ 从本地存储加载封面图缓存
  Future<void> _loadCoverCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_coverCacheKey);
      if (cacheJson != null && cacheJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(cacheJson);
        _coverCache.clear();

        // 🔧 加载时验证 URL，过滤掉无效的缓存
        int invalidCount = 0;
        decoded.forEach((key, value) {
          if (value is String) {
            if (_isValidCoverUrl(value)) {
              _coverCache[key] = value;
            } else {
              invalidCount++;
              debugPrint('⚠️ [CoverCache] 跳过无效缓存: $key -> $value');
            }
          }
        });

        print('🖼️ [CoverCache] 已加载 ${_coverCache.length} 条有效缓存');
        if (invalidCount > 0) {
          print('🖼️ [CoverCache] 过滤掉 $invalidCount 条无效缓存');
          // 立即保存清理后的缓存
          _saveCoverCache();
        }
      }
    } catch (e) {
      print('🖼️ [CoverCache] 加载缓存失败: $e');
    }
  }

  /// 🖼️ 保存封面图缓存到本地存储
  Future<void> _saveCoverCache() async {
    try {
      // 限制缓存大小，移除最早的条目
      if (_coverCache.length > _maxCacheSize) {
        final keysToRemove =
            _coverCache.keys.take(_coverCache.length - _maxCacheSize).toList();
        for (final key in keysToRemove) {
          _coverCache.remove(key);
        }
        print('🖼️ [CoverCache] 清理缓存，当前大小: ${_coverCache.length}');
      }

      final prefs = await SharedPreferences.getInstance();
      final cacheJson = jsonEncode(_coverCache);
      await prefs.setString(_coverCacheKey, cacheJson);
      print('🖼️ [CoverCache] 已保存 ${_coverCache.length} 条封面缓存');
    } catch (e) {
      print('🖼️ [CoverCache] 保存缓存失败: $e');
    }
  }

  /// 🔧 验证封面 URL 是否有效
  bool _isValidCoverUrl(String url) {
    if (url.isEmpty) return false;

    // 检查 QQ 音乐封面 URL
    // 格式：https://y.gtimg.cn/music/photo_new/T002R300x300M000{albumId}.jpg
    // 无效格式：https://y.gtimg.cn/music/photo_new/T002R300x300M000.jpg（缺少 albumId）
    if (url.contains('y.gtimg.cn/music/photo_new/T002R300x300M000')) {
      // 检查是否直接以 M000.jpg 结尾（说明缺少 albumId）
      if (url.endsWith('M000.jpg')) {
        debugPrint('⚠️ [CoverURL] QQ音乐封面URL缺少albumId: $url');
        return false;
      }
    }

    // 其他 URL 认为有效
    return true;
  }

  /// 🖼️ 自动搜索并获取歌曲封面图（新版：支持无服务器模式）
  Future<void> _autoFetchAlbumCover(String songName) async {
    // 🔧 防止重复搜索同一首歌
    if (_searchingCoverForSong == songName) {
      debugPrint('🖼️ [AutoCover] 已在搜索中，跳过: $songName');
      return;
    }

    // 🎯 先检查内存缓存
    if (_coverCache.containsKey(songName)) {
      final cachedUrl = _coverCache[songName]!;

      // 🔧 验证缓存的 URL 是否有效
      if (_isValidCoverUrl(cachedUrl)) {
        debugPrint('🖼️ [AutoCover] 从内存缓存加载封面: $songName');
        updateAlbumCover(cachedUrl);
        return;
      } else {
        debugPrint('⚠️ [AutoCover] 缓存的封面URL无效，重新获取: $cachedUrl');
        _coverCache.remove(songName); // 移除无效缓存
      }
    }

    // 🔧 标记开始搜索
    _searchingCoverForSong = songName;

    try {
      debugPrint('🖼️ [AutoCover] ========== 开始获取封面 ==========');
      debugPrint('🖼️ [AutoCover] 歌曲名称: "$songName"');

      final apiService = ref.read(apiServiceProvider);

      // 🎯 判断是否为直连模式（无服务器）
      if (apiService == null) {
        // 🚀 无服务器模式：直接刮削在线封面
        debugPrint('🔧 [AutoCover] 无服务器模式，直接刮削在线封面');
        final coverUrl = await _scrapeAlbumCoverDirectly(songName);

        if (coverUrl != null && coverUrl.isNotEmpty) {
          debugPrint('✅ [AutoCover] 在线刮削成功: $coverUrl');

          // 🎯 保存到内存缓存
          _coverCache[songName] = coverUrl;
          _saveCoverCache(); // 异步保存到本地，不阻塞主流程

          // 更新封面图
          updateAlbumCover(coverUrl);
          debugPrint('✅ [AutoCover] 封面图已更新到UI');
        } else {
          debugPrint('⚠️ [AutoCover] 在线刮削失败，未找到封面');
        }
        return;
      }

      // 🎯 有服务器模式：使用 AlbumCoverService（支持服务器查询和上传）
      // 🔧 初始化 AlbumCoverService（如果未初始化）
      if (_albumCoverService == null) {
        debugPrint('🔧 [AutoCover] 初始化 AlbumCoverService');
        final nativeSearch = ref.read(nativeMusicSearchServiceProvider);
        _albumCoverService = AlbumCoverService(
          musicApi: apiService,
          nativeSearch: nativeSearch,
        );
      }

      // 获取登录地址（用于URL替换）
      final loginBaseUrl = apiService.baseUrl;
      debugPrint('🖼️ [AutoCover] 登录地址: $loginBaseUrl');

      // 🚀 调用 AlbumCoverService 获取或刮削封面
      final coverUrl = await _albumCoverService!.getOrFetchAlbumCover(
        musicName: songName,
        loginBaseUrl: loginBaseUrl,
        autoScrape: true, // 允许自动刮削
      );

      if (coverUrl != null && coverUrl.isNotEmpty) {
        debugPrint('✅ [AutoCover] 获取封面成功: $coverUrl');

        // 🎯 保存到内存缓存
        _coverCache[songName] = coverUrl;
        _saveCoverCache(); // 异步保存到本地，不阻塞主流程

        // 更新封面图
        updateAlbumCover(coverUrl);
        debugPrint('✅ [AutoCover] 封面图已更新到UI');
      } else {
        debugPrint('⚠️ [AutoCover] 未找到封面（服务器无封面且在线刮削失败）');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [AutoCover] ========== 获取封面异常 ==========');
      debugPrint('❌ [AutoCover] 异常: $e');
      debugPrint(
        '❌ [AutoCover] 堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );
      // 静默失败，不影响播放
    } finally {
      // 🔧 搜索完成，清除标记
      if (_searchingCoverForSong == songName) {
        _searchingCoverForSong = null;
        debugPrint('🖼️ [AutoCover] 搜索完成，清除标记: $songName');
      }
    }
  }

  /// 🖼️ 直接刮削在线封面（无服务器模式专用）
  /// 从 "歌名 - 歌手" 格式解析，调用音乐平台搜索封面
  Future<String?> _scrapeAlbumCoverDirectly(String songName) async {
    try {
      debugPrint('🔍 [AutoCover] 直接刮削模式启动: $songName');

      // 解析歌曲名和歌手
      String searchQuery = songName;
      final parts = songName.split(' - ');
      if (parts.length >= 2) {
        final title = parts[0].trim();
        final artist = parts[1].trim();
        searchQuery = '$title $artist'; // QQ音乐搜索格式
        debugPrint('🔍 [AutoCover] 解析歌曲信息: 歌名="$title", 歌手="$artist"');
      }

      final nativeSearch = ref.read(nativeMusicSearchServiceProvider);

      // 🎯 策略1: 优先尝试 QQ 音乐（封面质量最佳）
      debugPrint('🔍 [AutoCover] 尝试 QQ 音乐搜索...');
      final qqResults = await nativeSearch.searchQQ(
        query: searchQuery,
        page: 1,
      );

      if (qqResults.isNotEmpty) {
        final firstResult = qqResults.first;
        if (firstResult.picture != null && firstResult.picture!.isNotEmpty) {
          final coverUrl = firstResult.picture!;
          if (_isValidCoverUrl(coverUrl)) {
            debugPrint('✅ [AutoCover] QQ音乐封面: $coverUrl');
            return coverUrl;
          }
        }
      }

      // 🎯 策略2: 回退到酷我音乐
      debugPrint('🔍 [AutoCover] QQ音乐未找到，尝试酷我音乐...');
      final kuwoResults = await nativeSearch.searchKuwo(
        query: searchQuery,
        page: 1,
      );

      if (kuwoResults.isNotEmpty) {
        final firstResult = kuwoResults.first;
        if (firstResult.picture != null && firstResult.picture!.isNotEmpty) {
          final coverUrl = firstResult.picture!;
          if (_isValidCoverUrl(coverUrl)) {
            debugPrint('✅ [AutoCover] 酷我音乐封面: $coverUrl');
            return coverUrl;
          }
        }
      }

      // 🎯 策略3: 最后尝试网易云音乐
      debugPrint('🔍 [AutoCover] 酷我音乐未找到，尝试网易云音乐...');
      final neteaseResults = await nativeSearch.searchNetease(
        query: searchQuery,
        page: 1,
      );

      if (neteaseResults.isNotEmpty) {
        final firstResult = neteaseResults.first;
        if (firstResult.picture != null && firstResult.picture!.isNotEmpty) {
          final coverUrl = firstResult.picture!;
          if (_isValidCoverUrl(coverUrl)) {
            debugPrint('✅ [AutoCover] 网易云音乐封面: $coverUrl');
            return coverUrl;
          }
        }
      }

      debugPrint('⚠️ [AutoCover] 所有音乐平台均未找到封面');
      return null;
    } catch (e) {
      debugPrint('❌ [AutoCover] 直接刮削异常: $e');
      return null;
    }
  }

  /// 🎵 切换播放模式
  Future<void> switchPlayMode(PlayMode newMode) async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️  未选择设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️  API服务未初始化');
      return;
    }

    try {
      debugPrint('🎵 切换播放模式: ${newMode.displayName} (${newMode.command})');
      await apiService.executeCommand(
        did: selectedDid,
        command: newMode.command,
      );

      // 更新本地状态
      state = state.copyWith(playMode: newMode);
      debugPrint('✅ 播放模式已切换: ${newMode.displayName}');
    } catch (e) {
      debugPrint('❌ 切换播放模式失败: $e');
      state = state.copyWith(error: '切换播放模式失败: ${e.toString()}');
    }
  }

  // ========================================
  // 🎵 歌单播放功能
  // ========================================

  /// 🎵 播放指定歌单
  Future<void> playPlaylist(String playlistName) async {
    if (playlistName.isEmpty) {
      debugPrint('⚠️ [播放歌单] 歌单名称为空');
      state = state.copyWith(error: '歌单名称不能为空');
      return;
    }

    debugPrint('🎵 [播放歌单] 准备播放歌单: $playlistName');

    // 🎯 判断当前播放模式
    final playbackMode = ref.read(playbackModeProvider);

    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 🎯 直连模式：使用本地歌单服务
      debugPrint('🎵 [播放歌单-直连] 使用本地歌单服务');
      await _playDirectModePlaylist(playlistName);
      return;
    }

    // 🎯 xiaomusic 模式：通过服务器命令播放歌单
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️ [播放歌单] 未选择设备');
      state = state.copyWith(error: '请先选择播放设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️ [播放歌单] API服务未初始化');
      state = state.copyWith(error: 'API服务未初始化');
      return;
    }

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('🎵 [播放歌单] 发送播放命令: 播放$playlistName');

      await apiService.executeCommand(
        did: selectedDid,
        command: '播放$playlistName',
      );

      // 等待播放开始
      await Future.delayed(const Duration(milliseconds: 1500));

      // 刷新状态获取歌单信息
      await refreshStatus();

      debugPrint('✅ [播放歌单] 歌单播放成功: $playlistName');
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('❌ [播放歌单] 播放失败: $e');
      state = state.copyWith(
        isLoading: false,
        error: '播放歌单失败: ${e.toString()}',
      );
    }
  }

  /// 🎵 播放歌单中的指定歌曲
  Future<void> playSongFromPlaylist(String songName, String playlistName) async {
    if (songName.isEmpty) {
      debugPrint('⚠️ [播放歌曲] 歌曲名称为空');
      state = state.copyWith(error: '歌曲名称不能为空');
      return;
    }

    debugPrint('🎵 [播放歌曲] 准备播放: $songName (来自歌单: $playlistName)');

    try {
      state = state.copyWith(isLoading: true);

      // 先播放歌单（确保切换到正确的歌单）
      if (playlistName.isNotEmpty) {
        await playPlaylist(playlistName);
        // 等待歌单切换完成
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 然后播放指定歌曲
      final selectedDid = ref.read(deviceProvider).selectedDeviceId;
      if (selectedDid != null) {
        await playMusic(deviceId: selectedDid, musicName: songName);
      } else {
        // 直连模式或其他情况
        await playMusic(deviceId: '', musicName: songName);
      }

      debugPrint('✅ [播放歌曲] 歌曲播放成功: $songName');
    } catch (e) {
      debugPrint('❌ [播放歌曲] 播放失败: $e');
      state = state.copyWith(
        isLoading: false,
        error: '播放失败: ${e.toString()}',
      );
    }
  }

  // ========================================
  // ⭐ 收藏功能
  // ========================================

  /// ⭐💔 切换收藏状态（支持双模式）
  Future<void> toggleFavorites() async {
    final playbackMode = ref.read(playbackModeProvider);

    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 🎯 直连模式：使用本地收藏服务
      await _toggleDirectModeFavorite();
    } else {
      // 🎯 xiaomusic模式：使用服务器端收藏
      if (state.isFavorite) {
        await removeFromFavorites();
      } else {
        await addToFavorites();
      }
    }
  }

  /// 🎯 直连模式收藏切换（本地存储）
  Future<void> _toggleDirectModeFavorite() async {
    if (state.currentMusic == null || state.currentMusic!.curMusic.isEmpty) {
      debugPrint('⚠️ [直连收藏] 当前没有播放歌曲');
      state = state.copyWith(error: '当前没有播放歌曲');
      return;
    }

    final songName = state.currentMusic!.curMusic;
    final albumCoverUrl = state.albumCoverUrl;

    try {
      // 使用本地收藏服务
      final favoriteService = DirectModeFavoriteService();

      if (state.isFavorite) {
        // 取消收藏
        debugPrint('💔 [直连收藏] 取消收藏: $songName');
        final success = await favoriteService.removeFavorite(songName);
        if (success) {
          state = state.copyWith(isFavorite: false);
          debugPrint('✅ [直连收藏] 已取消收藏');
        } else {
          state = state.copyWith(error: '取消收藏失败');
        }
      } else {
        // 添加收藏
        debugPrint('⭐ [直连收藏] 添加收藏: $songName');
        final success = await favoriteService.addFavorite(
          songName,
          albumCoverUrl: albumCoverUrl,
        );
        if (success) {
          state = state.copyWith(isFavorite: true);
          debugPrint('✅ [直连收藏] 已添加收藏');
        } else {
          state = state.copyWith(error: '添加收藏失败');
        }
      }
    } catch (e) {
      debugPrint('❌ [直连收藏] 操作失败: $e');
      state = state.copyWith(error: '收藏操作失败: ${e.toString()}');
    }
  }

  /// ⭐ 加入收藏（xiaomusic模式）
  Future<void> addToFavorites() async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️  未选择设备');
      state = state.copyWith(error: '未选择设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️  API服务未初始化');
      state = state.copyWith(error: 'API服务未初始化');
      return;
    }

    if (state.currentMusic == null) {
      debugPrint('⚠️  当前没有播放歌曲');
      state = state.copyWith(error: '当前没有播放歌曲');
      return;
    }

    try {
      debugPrint('⭐ 加入收藏: ${state.currentMusic!.curMusic}');
      await apiService.executeCommand(did: selectedDid, command: '加入收藏');
      state = state.copyWith(isFavorite: true);
      debugPrint('✅ 已加入收藏');
    } catch (e) {
      debugPrint('❌ 加入收藏失败: $e');
      state = state.copyWith(error: '加入收藏失败: ${e.toString()}');
    }
  }

  /// 💔 取消收藏
  Future<void> removeFromFavorites() async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️  未选择设备');
      state = state.copyWith(error: '未选择设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️  API服务未初始化');
      state = state.copyWith(error: 'API服务未初始化');
      return;
    }

    if (state.currentMusic == null) {
      debugPrint('⚠️  当前没有播放歌曲');
      state = state.copyWith(error: '当前没有播放歌曲');
      return;
    }

    try {
      debugPrint('💔 取消收藏: ${state.currentMusic!.curMusic}');
      await apiService.executeCommand(did: selectedDid, command: '取消收藏');
      state = state.copyWith(isFavorite: false);
      debugPrint('✅ 已取消收藏');
    } catch (e) {
      debugPrint('❌ 取消收藏失败: $e');
      state = state.copyWith(error: '取消收藏失败: ${e.toString()}');
    }
  }

  /// ⏰ 设置定时关机
  Future<void> setTimer() async {
    // 循环增加定时：0 -> 10 -> 15 -> 20 -> ... -> 60 -> 0
    int nextMinutes;
    if (state.timerMinutes == 0) {
      nextMinutes = 10; // 初始为 10 分钟
    } else if (state.timerMinutes >= 60) {
      nextMinutes = 0; // 达到 60 分钟后归零（取消定时）
    } else {
      nextMinutes = state.timerMinutes + 5; // 每次增加 5 分钟
    }

    // 🎯 判断当前播放模式
    final playbackMode = ref.read(playbackModeProvider);

    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 🎯 直连模式：使用APP本地定时器
      debugPrint('⏰ [DirectMode] 设置APP本地定时: $nextMinutes 分钟');

      _timerCountdown?.cancel();

      if (nextMinutes > 0) {
        _timerCountdown = Timer(Duration(minutes: nextMinutes), () async {
          debugPrint('⏰ [DirectMode] 定时到达，停止播放');
          await pause();
          state = state.copyWith(timerMinutes: 0);
        });
        state = state.copyWith(timerMinutes: nextMinutes);
        debugPrint('✅ [DirectMode] APP本地定时已设置: $nextMinutes 分钟');
      } else {
        state = state.copyWith(timerMinutes: 0);
        debugPrint('✅ [DirectMode] 已取消定时');
      }
    } else {
      // 🎯 xiaomusic模式：使用服务器端定时
      final selectedDid = ref.read(deviceProvider).selectedDeviceId;
      if (selectedDid == null) {
        debugPrint('⚠️  未选择设备');
        state = state.copyWith(error: '未选择设备');
        return;
      }

      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) {
        debugPrint('⚠️  API服务未初始化');
        state = state.copyWith(error: 'API服务未初始化');
        return;
      }

      try {
        if (nextMinutes == 0) {
          // 取消定时：发送关机命令（实际上是取消定时）
          debugPrint('⏰ 取消定时关机');
          // 某些服务器可能需要特殊命令来取消，这里先不发送命令
          state = state.copyWith(timerMinutes: 0);
        } else {
          debugPrint('⏰ 设置定时关机: $nextMinutes 分钟');
          await apiService.executeCommand(
            did: selectedDid,
            command: '$nextMinutes分钟后关机',
          );
          state = state.copyWith(timerMinutes: nextMinutes);
          debugPrint('✅ 定时关机已设置: $nextMinutes 分钟');
        }
      } catch (e) {
        debugPrint('❌ 设置定时关机失败: $e');
        state = state.copyWith(error: '设置定时关机失败: ${e.toString()}');
      }
    }
  }

  /// ⏰ 快速取消定时（长按）
  void cancelTimer() {
    debugPrint('⏰ 快速取消定时关机');
    _timerCountdown?.cancel(); // 取消APP本地定时器
    state = state.copyWith(timerMinutes: 0);
  }

  /// ⏰ 设置指定分钟数的定时关机（用于弹窗选择器）
  Future<void> setTimerMinutes(int minutes) async {
    if (minutes < 0) {
      debugPrint('⚠️ 定时分钟数不能为负数');
      return;
    }

    debugPrint('⏰ 设置定时关机: $minutes 分钟');

    // 🎯 判断当前播放模式
    final playbackMode = ref.read(playbackModeProvider);

    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 🎯 直连模式：使用APP本地定时器
      debugPrint('⏰ [DirectMode] 设置APP本地定时: $minutes 分钟');

      _timerCountdown?.cancel();

      if (minutes > 0) {
        _timerCountdown = Timer(Duration(minutes: minutes), () async {
          debugPrint('⏰ [DirectMode] 定时到达，停止播放');
          await pause();
          state = state.copyWith(timerMinutes: 0);
        });
        state = state.copyWith(timerMinutes: minutes);
        debugPrint('✅ [DirectMode] APP本地定时已设置: $minutes 分钟');
      } else {
        state = state.copyWith(timerMinutes: 0);
        debugPrint('✅ [DirectMode] 已取消定时');
      }
    } else {
      // 🎯 xiaomusic模式：使用服务器端定时
      final selectedDid = ref.read(deviceProvider).selectedDeviceId;
      if (selectedDid == null) {
        debugPrint('⚠️ 未选择设备');
        state = state.copyWith(error: '未选择设备');
        return;
      }

      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) {
        debugPrint('⚠️ API服务未初始化');
        state = state.copyWith(error: 'API服务未初始化');
        return;
      }

      try {
        if (minutes > 0) {
          debugPrint('⏰ [XiaoMusic] 设置服务器端定时: $minutes 分钟');
          await apiService.executeCommand(
            did: selectedDid,
            command: '定时关机$minutes分钟',
          );
          state = state.copyWith(timerMinutes: minutes);
          debugPrint('✅ [XiaoMusic] 服务器端定时已设置: $minutes 分钟');
        } else {
          debugPrint('⏰ [XiaoMusic] 取消服务器端定时');
          await apiService.executeCommand(
            did: selectedDid,
            command: '取消定时关机',
          );
          state = state.copyWith(timerMinutes: 0);
          debugPrint('✅ [XiaoMusic] 已取消定时');
        }
      } catch (e) {
        debugPrint('❌ 设置定时关机失败: $e');
        state = state.copyWith(error: '设置定时关机失败: ${e.toString()}');
      }
    }
  }

  // ========================================
  // 🎵 播放模式辅助方法
  // ========================================

  /// 🔁 重新播放当前歌曲（单曲循环）
  Future<void> _replayCurrentSong() async {
    final currentSong = state.currentMusic?.curMusic;
    if (currentSong == null || currentSong.isEmpty) {
      debugPrint('⚠️ [播放模式] 当前没有播放歌曲');
      state = state.copyWith(isLoading: false, error: '当前没有播放歌曲');
      return;
    }

    debugPrint('🔁 [播放模式] 重新播放: $currentSong');

    try {
      // 根据不同播放模式重新播放
      final playbackMode = ref.read(playbackModeProvider);

      if (playbackMode == PlaybackMode.miIoTDirect) {
        // 直连模式：直接调用播放方法
        await _currentStrategy!.play();
      } else {
        // xiaomusic模式：使用策略播放当前歌曲
        await _currentStrategy!.play();
      }

      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('❌ [播放模式] 重新播放失败: $e');
      state = state.copyWith(isLoading: false, error: '重新播放失败: $e');
    }
  }

  /// 🎲 随机播放下一首歌曲
  Future<void> _playRandomSong() async {
    final playlist = state.currentPlaylistSongs;
    final currentSong = state.currentMusic?.curMusic;

    if (playlist.isEmpty) {
      debugPrint('⚠️ [播放模式] 当前歌单为空');
      state = state.copyWith(isLoading: false, error: '当前歌单为空');
      return;
    }

    // 从歌单中随机选择一首（排除当前播放的歌曲）
    final availableSongs = playlist.where((song) => song != currentSong).toList();

    if (availableSongs.isEmpty) {
      // 歌单只有一首歌，重新播放当前歌曲
      debugPrint('🎲 [播放模式] 歌单只有一首歌，重新播放');
      await _replayCurrentSong();
      return;
    }

    // 随机选择
    final random = DateTime.now().millisecondsSinceEpoch % availableSongs.length;
    final nextSong = availableSongs[random];

    debugPrint('🎲 [播放模式] 随机选择: $nextSong (歌单共${playlist.length}首，可选${availableSongs.length}首)');

    // 添加当前歌曲到历史记录
    if (currentSong != null && currentSong.isNotEmpty) {
      _addToHistory(currentSong);
    }

    try {
      // 播放选中的歌曲
      await playMusic(
        deviceId: _currentDeviceId ?? '',
        musicName: nextSong,
      );
    } catch (e) {
      debugPrint('❌ [播放模式] 随机播放失败: $e');
      state = state.copyWith(isLoading: false, error: '随机播放失败: $e');
    }
  }

  /// ⏮️ 从历史记录播放上一首（随机模式）
  Future<void> _playPreviousFromHistory() async {
    if (_playHistory.isEmpty) {
      debugPrint('⚠️ [播放模式] 没有播放历史记录');
      state = state.copyWith(isLoading: false, error: '没有播放历史');
      return;
    }

    // 从历史记录中取出最后一首
    final previousSong = _playHistory.removeLast();
    debugPrint('⏮️ [播放模式] 从历史返回: $previousSong (剩余历史${_playHistory.length}首)');

    try {
      await playMusic(
        deviceId: _currentDeviceId ?? '',
        musicName: previousSong,
      );
    } catch (e) {
      debugPrint('❌ [播放模式] 播放历史歌曲失败: $e');
      state = state.copyWith(isLoading: false, error: '播放失败: $e');
    }
  }

  /// 📝 添加歌曲到播放历史
  void _addToHistory(String songName) {
    if (songName.isEmpty) return;

    // 避免重复添加相同的歌曲（如果最后一首就是当前歌曲）
    if (_playHistory.isNotEmpty && _playHistory.last == songName) {
      return;
    }

    _playHistory.add(songName);

    // 限制历史记录大小
    if (_playHistory.length > _maxHistorySize) {
      _playHistory.removeAt(0); // 移除最旧的记录
    }

    debugPrint('📝 [播放历史] 添加: $songName (历史记录: ${_playHistory.length}首)');
  }

  // ========================================
  // 🎯 播放队列支持（仅直连模式使用）
  // ========================================

  /// 🎵 使用公用JS服务解析音乐URL
  ///
  /// 这是一个公用方法，不依赖xiaomusic服务器
  /// 支持所有模式使用（本地/xiaomusic/直连）
  Future<String?> _resolveUrlByJS({
    required String platform,
    required String songId,
    String quality = '320k',
  }) async {
    try {
      debugPrint('🔍 [JS解析] 开始解析: platform=$platform, songId=$songId, quality=$quality');

      // 优先级1：QuickJS代理解析
      try {
        final jsProxyState = ref.read(jsProxyProvider);
        if (jsProxyState.isInitialized && jsProxyState.currentScript != null) {
          debugPrint('🔍 [JS解析] 尝试使用QuickJS...');
          final jsProxy = ref.read(jsProxyProvider.notifier);
          final mapped = _mapPlatformName(platform);
          final url = await jsProxy.getMusicUrl(
            source: mapped,
            songId: songId,
            quality: quality,
            musicInfo: {'songmid': songId, 'hash': songId},
          );
          if (url != null && url.isNotEmpty) {
            debugPrint('✅ [JS解析] QuickJS成功: ${url.substring(0, url.length > 80 ? 80 : url.length)}...');
            return url;
          }
          debugPrint('⚠️ [JS解析] QuickJS返回空URL');
        }
      } catch (e) {
        debugPrint('⚠️ [JS解析] QuickJS失败: $e');
      }

      // 优先级2：WebView JS解析
      try {
        debugPrint('🔍 [JS解析] 尝试使用WebView JS...');
        final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
        if (webSvc != null) {
          final url = await webSvc.resolveMusicUrl(
            platform: platform,
            songId: songId,
            quality: quality,
          );
          if (url != null && url.isNotEmpty) {
            debugPrint('✅ [JS解析] WebView成功: ${url.substring(0, url.length > 80 ? 80 : url.length)}...');
            return url;
          }
          debugPrint('⚠️ [JS解析] WebView返回空URL');
        }
      } catch (e) {
        debugPrint('⚠️ [JS解析] WebView失败: $e');
      }

      // 优先级3：内置LocalJS解析
      try {
        debugPrint('🔍 [JS解析] 尝试使用LocalJS...');
        final jsSvc = await ref.read(jsSourceServiceProvider.future);
        if (jsSvc != null && jsSvc.isReady) {
          final mapped = _mapPlatformName(platform);
          final js = """
            (function(){
              try{
                if (!lx || !lx.EVENT_NAMES) return '';
                function mapPlat(p){
                  p=(p||'').toLowerCase();
                  if(p==='qq'||p==='tencent') return 'tx';
                  if(p==='netease'||p==='163') return 'wy';
                  if(p==='kuwo') return 'kw';
                  if(p==='kugou') return 'kg';
                  if(p==='migu') return 'mg';
                  return p;
                }
                var payload = {
                  action: 'musicUrl',
                  source: mapPlat('$platform'),
                  info: { type: '$quality', musicInfo: { songmid: '$songId', hash: '$songId' } }
                };
                var res = lx.emit(lx.EVENT_NAMES.request, payload);
                if (res && typeof res.then === 'function') return '';
                if (typeof res === 'string') return res;
                if (res && res.url) return res.url;
                return '';
              }catch(e){ return '' }
            })()
          """;
          final url = jsSvc.evaluateToString(js);
          if (url.isNotEmpty) {
            debugPrint('✅ [JS解析] LocalJS成功: ${url.substring(0, url.length > 80 ? 80 : url.length)}...');
            return url;
          }
          debugPrint('⚠️ [JS解析] LocalJS返回空URL');
        }
      } catch (e) {
        debugPrint('⚠️ [JS解析] LocalJS失败: $e');
      }

      debugPrint('❌ [JS解析] 所有解析方式均失败');
      return null;
    } catch (e) {
      debugPrint('❌ [JS解析] 异常: $e');
      return null;
    }
  }

  /// 映射平台名称（用于JS解析）
  String _mapPlatformName(String platform) {
    final p = platform.toLowerCase();
    if (p == 'qq' || p == 'tencent') return 'tx';
    if (p == 'netease' || p == '163') return 'wy';
    if (p == 'kuwo') return 'kw';
    if (p == 'kugou') return 'kg';
    if (p == 'migu') return 'mg';
    return p;
  }

  /// 🎵 从播放队列播放指定索引的歌曲
  ///
  /// 公共方法，供外部调用（如歌单详情页）
  /// [deviceId] 设备ID（直连模式需要）
  /// [index] 队列中的歌曲索引
  Future<void> playFromQueue({
    required String deviceId,
    required int index,
  }) async {
    try {
      debugPrint('🎵 [PlaybackProvider] playFromQueue 开始, index=$index');

      // 获取当前队列
      final queueState = ref.read(playbackQueueProvider);
      if (queueState.queue == null || queueState.queue!.items.isEmpty) {
        throw Exception('播放队列为空');
      }

      final items = queueState.queue!.items;
      if (index < 0 || index >= items.length) {
        throw Exception('索引越界: $index (队列长度: ${items.length})');
      }

      // 设置当前索引
      ref.read(playbackQueueProvider.notifier).jumpToIndex(index);

      // 获取要播放的歌曲
      final item = items[index];
      debugPrint('🎵 [PlaybackProvider] 播放队列歌曲: ${item.title}');

      // 调用内部播放方法
      await _playFromQueueItem(item);

      // 刷新播放状态
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      debugPrint('✅ [PlaybackProvider] playFromQueue 完成');
    } catch (e, stackTrace) {
      debugPrint('❌ [PlaybackProvider] playFromQueue 失败: $e');
      debugPrint('❌ 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      state = state.copyWith(error: '从队列播放失败: ${e.toString()}');
      rethrow;
    }
  }

  /// 🎵 从播放队列播放指定项目
  ///
  /// 仅在直连模式使用，支持在线音乐、本地音乐、服务器音乐
  Future<void> _playFromQueueItem(PlaylistItem item) async {
    try {
      debugPrint('🎵 [队列播放] 开始播放: ${item.title} - ${item.artist}');
      debugPrint('🎵 [队列播放] 来源类型: ${item.sourceType}');

      String? url;

      // 根据来源类型获取播放URL
      if (item.isOnline) {
        // 在线音乐：使用公用的JS解析服务
        if (item.platform == null || item.songId == null) {
          throw Exception('在线音乐缺少platform或songId');
        }
        debugPrint('🎵 [队列播放] 在线音乐，使用JS解析: ${item.platform}/${item.songId}');
        url = await _resolveUrlByJS(
          platform: item.platform!,
          songId: item.songId!,
          quality: '320k',
        );
      } else if (item.isLocal) {
        // 本地音乐：直接使用文件路径
        url = item.localPath;
        debugPrint('🎵 [队列播放] 本地音乐: $url');
      } else if (item.isServer) {
        // 服务器音乐：调用xiaomusic服务器API
        final apiService = ref.read(apiServiceProvider);
        if (apiService != null) {
          debugPrint('🎵 [队列播放] 服务器音乐，查询xiaomusic API');
          final musicInfo = await apiService.getMusicInfo(item.displayName);
          url = musicInfo['url']?.toString();
        } else {
          throw Exception('服务器音乐但API服务不可用');
        }
      }

      if (url == null || url.isEmpty) {
        throw Exception('无法获取播放URL');
      }

      debugPrint('✅ [队列播放] URL获取成功');

      // 使用策略播放
      await _currentStrategy!.playMusic(
        musicName: item.displayName,
        url: url,
      );

      debugPrint('✅ [队列播放] 播放命令已发送');

      // 更新UI状态（使用缓存的封面和歌词）
      if (item.coverUrl != null && item.coverUrl!.isNotEmpty) {
        debugPrint('🖼️ [队列播放] 使用缓存的封面图');
        updateAlbumCover(item.coverUrl!);
      } else {
        // 如果队列没有封面，自动搜索并缓存
        debugPrint('🖼️ [队列播放] 封面未缓存，开始搜索');
        _autoFetchAlbumCover(item.displayName).then((coverUrl) {
          // 搜索成功后缓存到队列
          if (state.albumCoverUrl != null && state.albumCoverUrl!.isNotEmpty) {
            ref.read(playbackQueueProvider.notifier).updateCurrentCover(state.albumCoverUrl!);
            debugPrint('✅ [队列播放] 封面已缓存到队列');
          }
        }).catchError((e) {
          debugPrint('⚠️ [队列播放] 封面搜索失败: $e');
        });
      }

      // 🔧 歌词处理：LyricProvider 会自动监听 currentMusic 变化并获取歌词
      // 如果队列中有缓存的歌词，之后获取时会自动使用缓存
      if (item.lrc != null && item.lrc!.isNotEmpty) {
        debugPrint('📝 [队列播放] 队列中已有歌词缓存');
        // 注：LyricProvider 会自动处理歌词获取，这里只是记录日志
      } else {
        debugPrint('📝 [队列播放] 歌词未缓存，LyricProvider 会自动获取');
      }

      debugPrint('✅ [队列播放] 播放成功');
    } catch (e, stackTrace) {
      debugPrint('❌ [队列播放] 播放失败: $e');
      debugPrint('❌ [队列播放] 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      state = state.copyWith(error: '队列播放失败: ${e.toString()}');
      rethrow;
    }
  }

  /// 🎵 播放直连模式本地歌单
  ///
  /// 从本地存储读取歌单并播放第一首歌曲
  Future<void> _playDirectModePlaylist(String playlistName) async {
    try {
      state = state.copyWith(isLoading: true);
      debugPrint('🎵 [直连歌单] 开始播放本地歌单: $playlistName');

      // 🎯 获取本地歌单服务
      final playlistService = DirectModePlaylistService();

      // 🎯 查找歌单
      final playlist = await playlistService.getPlaylistByName(playlistName);

      if (playlist == null) {
        debugPrint('⚠️ [直连歌单] 歌单不存在: $playlistName');
        state = state.copyWith(
          isLoading: false,
          error: '歌单不存在: $playlistName',
        );
        return;
      }

      if (playlist.songs.isEmpty) {
        debugPrint('⚠️ [直连歌单] 歌单为空: $playlistName');
        state = state.copyWith(
          isLoading: false,
          error: '歌单 "$playlistName" 中没有歌曲',
        );
        return;
      }

      debugPrint('✅ [直连歌单] 找到歌单: ${playlist.name}, 共 ${playlist.songs.length} 首歌');

      // 🎯 播放第一首歌曲
      final firstSong = playlist.songs.first;
      debugPrint('🎵 [直连歌单] 播放第一首: $firstSong');

      // 🎯 检查策略是否已初始化
      if (_currentStrategy == null) {
        debugPrint('❌ [直连歌单] 播放策略未初始化');
        state = state.copyWith(
          isLoading: false,
          error: '播放策略未初始化，请检查设备连接',
        );
        return;
      }

      // 🎵 更新当前播放列表信息（用于UI显示）
      state = state.copyWith(
        currentPlaylistSongs: playlist.songs,
      );

      // 🎯 播放第一首歌曲
      await playMusic(
        deviceId: _currentDeviceId ?? 'direct',
        musicName: firstSong,
      );

      debugPrint('✅ [直连歌单] 歌单播放成功: $playlistName');
      state = state.copyWith(isLoading: false);
    } catch (e, stackTrace) {
      debugPrint('❌ [直连歌单] 播放失败: $e');
      debugPrint('❌ [直连歌单] 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      state = state.copyWith(
        isLoading: false,
        error: '播放歌单失败: ${e.toString()}',
      );
    }
  }
}

final playbackProvider = StateNotifierProvider<PlaybackNotifier, PlaybackState>(
  (ref) {
    return PlaybackNotifier(ref);
  },
);
