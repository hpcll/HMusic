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
import '../../data/services/mi_hardware_detector.dart'; // 🎯 设备能力检测
import '../../data/services/music_api_service.dart'; // 🎯 音乐API服务
import '../../data/services/direct_mode_favorite_service.dart'; // 🎯 直连模式收藏服务
import '../../data/services/direct_mode_playlist_service.dart'; // 🎯 直连模式歌单服务
import '../../data/services/song_resolver_service.dart';
import '../../core/network/dio_client.dart'; // 🎯 HTTP客户端
import '../../core/constants/app_constants.dart'; // 🎯 应用常量
import 'dio_provider.dart';
import 'device_provider.dart';
import 'music_library_provider.dart';
import 'direct_mode_provider.dart'; // 🎯 直连模式Provider
import 'playback_queue_provider.dart'; // 🎯 播放队列Provider
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
  final bool seekEnabled; // 🎯 当前设备是否支持 seek（OH2P 等设备不支持，UI 应禁用进度条拖动）

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
    this.seekEnabled = true, // 默认支持 seek
  });

  PlaybackState copyWith({
    Object? currentMusic = _undefined, // 🔧 支持显式设置为 null
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
    bool? seekEnabled,
  }) {
    return PlaybackState(
      currentMusic:
          currentMusic == _undefined
              ? this.currentMusic
              : currentMusic as PlayingMusic?, // 🔧 支持显式设置为 null
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
      seekEnabled: seekEnabled ?? this.seekEnabled,
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
  bool _remoteRefreshInFlight = false; // 远程状态刷新并发锁
  // 保存服务器最后返回的原始进度，用于本地预测基准
  int? _lastServerOffset;

  // 保护期：设备切换后在该时间窗内忽略非当前设备的远端更新
  DateTime? _deviceSwitchProtectionUntil;

  // 🎯 乐观更新保护期：在播放/暂停操作后的短时间内忽略远程状态的 isPlaying 更新
  DateTime? _optimisticUpdateProtectionUntil;
  int _directSwitchSessionId = 0;
  DateTime? _directWarmupUntil;
  String? _directWarmupSong;

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
  static const String _remotePlaybackKey = 'remote_playback_state';
  static const String _remotePlaybackCoverKey = 'remote_playback_cover';
  static const String _remotePlaybackApiGroupKey = 'remote_playback_api_group';
  static const String _directModePlaybackKey =
      'direct_mode_playback_state'; // 🆕 直连模式专用
  static const String _directModePlaybackCoverKey =
      'direct_mode_playback_cover'; // 🆕 直连模式专用

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

  /// 获取当前播放队列的真实名称（歌单名/搜索结果名等）
  /// 优先级：playbackQueueProvider 队列名 > 当前 state 已有值 > fallback
  String _getCurrentQueueName({String fallback = ''}) {
    try {
      final queueState = ref.read(playbackQueueProvider);
      final queueName = queueState.queue?.queueName;
      if (queueName != null && queueName.isNotEmpty) {
        return queueName;
      }
    } catch (_) {}
    // 队列为空时（如重启后），保留 state 中已缓存恢复的歌单名
    final existing = state.currentMusic?.curPlaylist;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    return fallback;
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
        debugPrint(
          '🔧 [PlaybackProvider] 直连模式状态类型: ${directState.runtimeType}',
        );

        if (directState is DirectModeAuthenticated) {
          debugPrint('🔧 [PlaybackProvider] ✅ 直连模式已登录');
          debugPrint(
            '🔧 [PlaybackProvider] 设备数量: ${directState.devices.length}',
          );
          debugPrint(
            '🔧 [PlaybackProvider] 播放设备类型: ${directState.playbackDeviceType}',
          );

          // 🎵 无论是本地播放还是小爱音箱播放，都初始化策略
          debugPrint('🔧 [PlaybackProvider] 🎯 开始初始化直连模式播放策略');
          await _switchToDirectModeStrategy(directState);
          debugPrint(
            '🔧 [PlaybackProvider] 策略初始化结果: ${_currentStrategy != null ? "成功" : "失败"}',
          );
        } else if (directState is DirectModeInitial) {
          debugPrint('⚠️ [PlaybackProvider] ❌ 直连模式未登录（DirectModeInitial）');
          debugPrint('⚠️ [PlaybackProvider] 提示：请先登录小米账号');
        } else if (directState is DirectModeLoading) {
          debugPrint('⚠️ [PlaybackProvider] 🔄 直连模式正在登录中（DirectModeLoading）');
        } else if (directState is DirectModeError) {
          debugPrint('⚠️ [PlaybackProvider] ❌ 直连模式登录失败（DirectModeError）');
          debugPrint(
            '⚠️ [PlaybackProvider] 错误信息: ${(directState as DirectModeError).message}',
          );
        } else {
          debugPrint(
            '⚠️ [PlaybackProvider] ❓ 未知的直连模式状态: ${directState.runtimeType}',
          );
        }
      } else {
        // 🎯 xiaomusic 模式：从 DeviceProvider 获取设备并初始化策略
        debugPrint('🔧 [PlaybackProvider] xiaomusic 模式：开始加载设备列表');

        // 1. 加载设备列表
        await ref.read(deviceProvider.notifier).loadDevices();

        // 2. 获取当前选中的设备并初始化策略
        final deviceState = ref.read(deviceProvider);
        debugPrint(
          '🔧 [PlaybackProvider] 设备列表加载完成: ${deviceState.devices.length} 个设备',
        );
        debugPrint(
          '🔧 [PlaybackProvider] 当前选中设备ID: ${deviceState.selectedDeviceId ?? "null"}',
        );

        if (deviceState.selectedDeviceId != null &&
            deviceState.devices.isNotEmpty) {
          debugPrint('🔧 [PlaybackProvider] 🎯 开始初始化播放策略');
          await _switchStrategy(
            deviceState.selectedDeviceId!,
            deviceState.devices,
          );
          debugPrint(
            '🔧 [PlaybackProvider] 策略初始化结果: ${_currentStrategy != null ? "成功" : "失败"}',
          );
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
      debugPrint(
        '✅ [PlaybackProvider] 当前策略: ${_currentStrategy != null ? (_currentStrategy!.isLocalMode ? "本地播放" : "远程控制") : "未初始化"}',
      );
    } catch (e, stackTrace) {
      // 初始化失败，设置错误状态但不抛出异常
      debugPrint('❌ [PlaybackProvider] ========== 初始化失败 ==========');
      debugPrint('❌ [PlaybackProvider] 错误: $e');
      debugPrint(
        '❌ [PlaybackProvider] 堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );
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

      if (next is DirectModeAuthenticated &&
          previous is DirectModeAuthenticated) {
        // 🎵 检查播放设备类型是否变化
        if (next.playbackDeviceType != previous.playbackDeviceType) {
          debugPrint(
            '🎵 [PlaybackProvider] 检测到直连模式播放设备切换: ${previous.playbackDeviceType} -> ${next.playbackDeviceType}',
          );
          _currentDeviceId = null; // 重置设备ID，准备切换策略
          _switchToDirectModeStrategy(next);
        }
      } else if (next is DirectModeAuthenticated &&
          previous is! DirectModeAuthenticated) {
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
        await _switchStrategy(
          deviceState.selectedDeviceId!,
          deviceState.devices,
        );
      } else {
        debugPrint('⚠️ [PlaybackProvider] xiaomusic 模式无设备，等待选择设备后初始化');
      }
    }
  }

  // 🎯 切换到直连模式播放策略
  Future<void> _switchToDirectModeStrategy(
    DirectModeAuthenticated directState,
  ) async {
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
        _deviceSwitchProtectionUntil = DateTime.now().add(
          const Duration(milliseconds: 1500),
        );
        debugPrint('🎵 [PlaybackProvider] 创建本地播放策略');

        // 🎯 尝试获取 MusicApiService（用于搜索音乐，可选）
        MusicApiService? apiService = ref.read(apiServiceProvider);

        // 🎯 如果 apiServiceProvider 为 null（直连模式下未登录 xiaomusic）
        // 尝试从 SharedPreferences 读取保存的服务器配置并创建临时 MusicApiService
        if (apiService == null) {
          debugPrint(
            '⚠️ [PlaybackProvider] apiServiceProvider 为 null，尝试从本地配置创建',
          );

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
            debugPrint(
              '⚠️ [PlaybackProvider] 创建临时 MusicApiService 失败: $e，使用完全独立模式',
            );
            // 🎯 失败时也使用完全独立模式
            apiService = null;
          }
        }

        // 🎯 创建本地播放策略（apiService 可以为 null，支持完全独立模式）
        final localStrategy = LocalPlaybackStrategy(apiService: apiService);
        _currentStrategy = localStrategy;
        _currentDeviceId = 'local';

        try {
          await LocalPlaybackStrategy.handlerReady.timeout(
            const Duration(seconds: 2),
          );
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
          if (status.curMusic.isNotEmpty &&
              _lastCoverSearchSong != status.curMusic) {
            debugPrint(
              '🖼️ [PlaybackProvider-本地Stream] 歌曲切换,清除旧封面: $_lastCoverSearchSong -> ${status.curMusic}',
            );
            state = state.copyWith(albumCoverUrl: null);
            _lastCoverSearchSong = status.curMusic;
            debugPrint(
              '🖼️ [PlaybackProvider-本地Stream] ✅ 触发封面自动搜索: ${status.curMusic}',
            );
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

        // 更新状态 - 🔧 显式重置 currentMusic 为 null，避免显示旧模式的播放状态
        state = state.copyWith(
          hasLoaded: true,
          isLoading: false,
          isLocalMode: true, // 本地播放
          currentMusic: null, // 🔧 清除旧的播放状态
          albumCoverUrl: null, // 🔧 清除旧的封面
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
          onStatusChanged: (switchSessionId) async {
            if (switchSessionId != null &&
                switchSessionId != _directSwitchSessionId) {
              debugPrint(
                '⏭️ [PlaybackProvider] 忽略过期直连状态回调: session=$switchSessionId, current=$_directSwitchSessionId',
              );
              return;
            }
            debugPrint('🔔 [PlaybackProvider] 直连模式状态变化');
            await refreshStatus(
              silent: true,
              directSwitchSessionId: switchSessionId,
            );

            // 💾 保存直连模式播放状态（每次状态变化都保存）
            if (state.currentMusic != null &&
                state.currentMusic!.curMusic.isNotEmpty) {
              await _saveDirectModePlayback(state.currentMusic!);
            }
          },
          // 🎯 歌曲播放完成回调：自动播放下一首
          onSongComplete: () async {
            debugPrint('🎵 [PlaybackProvider] 直连模式歌曲播放完成，尝试播放下一首');
            await _handleDirectModeSongComplete();
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
                debugPrint(
                  '⚠️ [PlaybackProvider-MiIoT] apiServiceProvider 为 null，尝试从本地配置创建',
                );

                try {
                  final prefs = await SharedPreferences.getInstance();
                  final serverUrl = prefs.getString(
                    AppConstants.prefsServerUrl,
                  );
                  final username = prefs.getString(AppConstants.prefsUsername);
                  final password = prefs.getString(AppConstants.prefsPassword);

                  if (serverUrl != null &&
                      username != null &&
                      password != null) {
                    debugPrint(
                      '✅ [PlaybackProvider-MiIoT] 找到保存的服务器配置: $serverUrl',
                    );

                    // 创建临时的 DioClient 和 MusicApiService
                    final tempClient = DioClient(
                      baseUrl: serverUrl,
                      username: username,
                      password: password,
                    );
                    apiService = MusicApiService(tempClient);

                    debugPrint(
                      '✅ [PlaybackProvider-MiIoT] 成功创建临时 MusicApiService',
                    );
                  } else {
                    debugPrint('⚠️ [PlaybackProvider-MiIoT] 未找到服务器配置，完全独立模式');
                    // 🎯 完全独立模式：返回 null，由调用方处理
                    // 直连模式播放在线音乐时会直接传入 URL，不需要通过这个回调获取
                    return null;
                  }
                } catch (e) {
                  debugPrint(
                    '⚠️ [PlaybackProvider-MiIoT] 创建临时 MusicApiService 失败: $e，完全独立模式',
                  );
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
          debugPrint(
            '🎵 [PlaybackProvider] 音乐库歌曲数量: ${libraryState.musicList.length}',
          );

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
            directStrategy.setPlaylist(
              libraryState.musicList,
              startIndex: startIndex,
            );
            debugPrint(
              '✅ [PlaybackProvider] 已设置直连播放列表: ${libraryState.musicList.length} 首',
            );
          } else {
            debugPrint('⚠️ [PlaybackProvider] 音乐库为空，暂不设置播放列表');
          }
        } catch (e) {
          debugPrint('❌ [PlaybackProvider] 设置播放列表失败: $e');
        }

        _currentStrategy = directStrategy;
        _currentDeviceId = deviceId;

        // 🎯 Bug3 fix: 根据设备硬件能力设置 seekEnabled
        final deviceHardware = device.hardware;
        final seekSupported = deviceHardware.isEmpty || MiHardwareDetector.supportsSeek(deviceHardware);
        if (!seekSupported) {
          debugPrint('⚠️ [PlaybackProvider] 设备 $deviceHardware 不支持 seek，禁用进度条拖动');
        }
        state = state.copyWith(seekEnabled: seekSupported);

        // 🎯 覆盖 audioHandler 回调，让通知栏控制路由到 PlaybackProvider
        final audioHandler = LocalPlaybackStrategy.sharedAudioHandler;
        if (audioHandler != null) {
          audioHandler.onPlay = () {
            debugPrint('🎵 [通知栏] 触发播放 → PlaybackProvider（直连）');
            resumeMusic();
          };
          audioHandler.onPause = () {
            debugPrint('🎵 [通知栏] 触发暂停 → PlaybackProvider（直连）');
            pauseMusic();
          };
          audioHandler.onNext = () {
            debugPrint('🎵 [通知栏] 触发下一首 → PlaybackProvider（直连）');
            next();
          };
          audioHandler.onPrevious = () {
            debugPrint('🎵 [通知栏] 触发上一首 → PlaybackProvider（直连）');
            previous();
          };
        }

        debugPrint('✅ [PlaybackProvider] 策略对象已赋值: ${_currentStrategy != null}');

        // 更新状态
        state = state.copyWith(
          hasLoaded: true,
          isLoading: false,
          isLocalMode: false, // 直连模式不是本地播放
        );

        debugPrint('✅ [PlaybackProvider] 直连模式策略切换完成');
        debugPrint(
          '✅ [PlaybackProvider] 当前策略是否为null: ${_currentStrategy == null}',
        );

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
      debugPrint(
        '❌ [PlaybackProvider] 堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );
    }
  }

  // 🎵 切换播放策略
  Future<void> _switchStrategy(String deviceId, List<Device> devices) async {
    try {
      debugPrint('🎵 [PlaybackProvider] ========== 开始切换播放策略 ==========');
      debugPrint('🎵 [PlaybackProvider] 目标设备ID: $deviceId');
      debugPrint(
        '🎵 [PlaybackProvider] 设备列表: ${devices.map((d) => '${d.name}(${d.id})').join(', ')}',
      );

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
      debugPrint(
        '🎵 [PlaybackProvider] 目标设备是否为本地: $isLocalMode (ID: $deviceId)',
      );

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
        _deviceSwitchProtectionUntil = DateTime.now().add(
          const Duration(milliseconds: 1500),
        );
        debugPrint('🎵 [PlaybackProvider] 切换到本地播放模式');

        final localStrategy = LocalPlaybackStrategy(apiService: apiService);
        _currentStrategy = localStrategy;

        try {
          await LocalPlaybackStrategy.handlerReady.timeout(
            const Duration(seconds: 2),
          );
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
          if (status.curMusic.isNotEmpty &&
              _lastCoverSearchSong != status.curMusic) {
            debugPrint(
              '🖼️ [PlaybackProvider-本地Stream] 歌曲切换,清除旧封面: $_lastCoverSearchSong -> ${status.curMusic}',
            );

            // 🔧 先清除旧封面,避免显示上一首歌的封面
            state = state.copyWith(albumCoverUrl: null);

            _lastCoverSearchSong = status.curMusic; // 记录本次搜索歌曲

            debugPrint(
              '🖼️ [PlaybackProvider-本地Stream] ✅ 触发封面自动搜索: ${status.curMusic}',
            );
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
          if (cachedUrl != null &&
              cachedMusic != null &&
              cachedUrl.isNotEmpty) {
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

            // 🔧 修复：清除旧的播放状态，避免显示远程模式的数据
            state = state.copyWith(
              currentMusic: null,
              albumCoverUrl: null,
              hasLoaded: true,
              isLoading: false,
              isLocalMode: true,
            );
            debugPrint('✅ [PlaybackProvider] 已清除旧播放状态');

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
              final idx = libraryState.musicList.indexWhere(
                (m) => m.name == state.currentMusic!.curMusic,
              );
              if (idx >= 0) startIndex = idx;
            }
            localStrategy.setPlaylist(
              libraryState.musicList,
              startIndex: startIndex,
            );
            debugPrint(
              '🎵 [PlaybackProvider] 已恢复本地播放列表: ${libraryState.musicList.length} 首',
            );
          } else {
            debugPrint('⚠️ [PlaybackProvider] 音乐库为空，暂不设置本地播放列表');
          }
        } catch (e) {
          debugPrint('❌ [PlaybackProvider] 恢复本地播放列表失败: $e');
        }
      } else {
        debugPrint('🎵 [PlaybackProvider] ========== 远程控制模式 ==========');
        debugPrint('🎵 [PlaybackProvider] 切换到远程控制模式 (设备: ${device.name})');
        _deviceSwitchProtectionUntil = DateTime.now().add(
          const Duration(milliseconds: 1500),
        );

        final remoteStrategy = RemotePlaybackStrategy(
          apiService: apiService,
          deviceId: deviceId,
          deviceName: device.name, // 🔧 传入设备名称
          audioHandler:
              LocalPlaybackStrategy.sharedAudioHandler, // 🔧 传入 AudioHandler
        );

        try {
          final prefs = await SharedPreferences.getInstance();
          final cachedGroup = prefs.getString(
            _remotePlaybackApiGroupKeyFor(deviceId),
          );
          remoteStrategy.restoreActiveApiGroup(cachedGroup);
        } catch (_) {}

        // 🔧 设置状态变化回调,远程操作后立即刷新 APP 状态
        remoteStrategy.onStatusChanged = () {
          debugPrint('🔔 [PlaybackProvider] 远程状态已变化,立即刷新 APP');
          // 🔧 重置防抖时间,允许立即刷新
          _lastRefreshTime = null;
          refreshStatus(silent: true);
        };

        _currentStrategy = remoteStrategy;

        // 🎯 设置自动下一首热身保护期（10秒）
        // 启动后首次轮询 audio_id 可能与缓存不同，不应触发自动下一首
        _xiaomusicAutoNextWarmupUntil = DateTime.now().add(
          const Duration(seconds: 10),
        );
        _xiaomusicLastAudioId = null; // 重置，避免与缓存的旧值误匹配
        debugPrint('🛡️ [PlaybackProvider] 设置自动下一首热身保护期: 10秒');

        // 🎯 覆盖 audioHandler 回调，让通知栏控制路由到 PlaybackProvider
        // 这样通知栏的上下曲会经过播放队列逻辑（支持元歌单），
        // 暂停/播放也会经过乐观更新和保护期机制
        final audioHandler = LocalPlaybackStrategy.sharedAudioHandler;
        if (audioHandler != null) {
          audioHandler.onPlay = () {
            debugPrint('🎵 [通知栏] 触发播放 → PlaybackProvider');
            resumeMusic();
          };
          audioHandler.onPause = () {
            debugPrint('🎵 [通知栏] 触发暂停 → PlaybackProvider');
            pauseMusic();
          };
          audioHandler.onNext = () {
            debugPrint('🎵 [通知栏] 触发下一首 → PlaybackProvider');
            next();
          };
          audioHandler.onPrevious = () {
            debugPrint('🎵 [通知栏] 触发上一首 → PlaybackProvider');
            previous();
          };
        }

        // 先恢复远程缓存，避免首轮 getplayerstatus 为空标题导致 UI 闪空
        await _loadRemotePlayback(deviceId);

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

    // 远程模式需要定期轮询状态（3秒一次）
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshStatus(silent: true);
    });

    debugPrint('⏰ [PlaybackProvider] 启动状态刷新定时器');
  }

  // 设备加载由 deviceProvider 负责

  Future<void> refreshStatus({
    bool silent = false,
    int? directSwitchSessionId,
  }) async {
    // 🎵 本地播放模式不需要从服务器刷新状态
    if (_currentStrategy != null && _currentStrategy!.isLocalMode) {
      debugPrint('🎵 [PlaybackProvider] 本地播放模式，跳过状态刷新');

      // 从本地播放器获取状态
      try {
        var status = await _currentStrategy!.getCurrentStatus();
        if (status != null) {
          // 🎯 直连模式下策略偶发返回 duration=0，避免把进度条打回空白样式
          int effectiveDuration = status.duration;
          if (effectiveDuration <= 0) {
            final localMusic = state.currentMusic;
            if (localMusic != null &&
                localMusic.curMusic == status.curMusic &&
                localMusic.duration > 0) {
              effectiveDuration = localMusic.duration;
            } else {
              final queueDuration =
                  ref.read(playbackQueueProvider).queue?.currentItem?.duration ??
                  0;
              if (queueDuration > 0) {
                effectiveDuration = queueDuration;
              }
            }
          }
          if (effectiveDuration != status.duration) {
            status = PlayingMusic(
              ret: status.ret,
              curMusic: status.curMusic,
              curPlaylist: status.curPlaylist,
              isPlaying: status.isPlaying,
              offset: status.offset,
              duration: effectiveDuration,
            );
          }

          // 🎯 用真实队列名替换策略返回的模式描述
          final realQueueName = _getCurrentQueueName(
            fallback: status.curPlaylist,
          );
          if (realQueueName != status.curPlaylist) {
            status = PlayingMusic(
              ret: status.ret,
              curMusic: status.curMusic,
              curPlaylist: realQueueName,
              isPlaying: status.isPlaying,
              offset: status.offset,
              duration: status.duration,
            );
          }
          state = state.copyWith(
            currentMusic: status,
            hasLoaded: true,
            isLoading: false,
          );

          // 🖼️ 本地模式也需要自动搜索封面图
          debugPrint('🖼️ [PlaybackProvider-本地] 检查是否需要搜索封面');
          debugPrint(
            '🖼️ [PlaybackProvider-本地] currentMusic: ${status.curMusic}',
          );
          debugPrint(
            '🖼️ [PlaybackProvider-本地] albumCoverUrl: ${state.albumCoverUrl}',
          );

          if (status.curMusic.isNotEmpty &&
              (state.albumCoverUrl == null || state.albumCoverUrl!.isEmpty)) {
            debugPrint(
              '🖼️ [PlaybackProvider-本地] ✅ 触发封面自动搜索: ${status.curMusic}',
            );
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
        var status = await _currentStrategy!.getCurrentStatus();
        debugPrint(
          '🎵 [PlaybackProvider] 直连模式状态: ${status?.curMusic}, 播放中=${status?.isPlaying}',
        );

        if (status != null) {
          // 🎯 用真实队列名替换策略返回的模式描述
          final realQueueName = _getCurrentQueueName(
            fallback: status.curPlaylist,
          );
          if (realQueueName != status.curPlaylist) {
            status = PlayingMusic(
              ret: status.ret,
              curMusic: status.curMusic,
              curPlaylist: realQueueName,
              isPlaying: status.isPlaying,
              offset: status.offset,
              duration: status.duration,
            );
          }

          if (directSwitchSessionId != null &&
              directSwitchSessionId != _directSwitchSessionId) {
            debugPrint(
              '⏭️ [PlaybackProvider] 忽略过期直连状态: session=$directSwitchSessionId, current=$_directSwitchSessionId',
            );
            return;
          }

          // 🛡️ 直连模式保护期：乐观切歌后，忽略旧歌曲轮询回写
          final inProtection =
              _optimisticUpdateProtectionUntil != null &&
              DateTime.now().isBefore(_optimisticUpdateProtectionUntil!);
          if (inProtection &&
              state.currentMusic != null &&
              status.curMusic.trim().isNotEmpty &&
              state.currentMusic!.curMusic.trim().isNotEmpty &&
              status.curMusic != state.currentMusic!.curMusic) {
            debugPrint(
              '🛡️ [直连模式] 保护期内忽略旧歌曲状态: remote=${status.curMusic}, local=${state.currentMusic!.curMusic}',
            );
            return;
          }

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
          final isWarmup =
              _directWarmupUntil != null &&
              DateTime.now().isBefore(_directWarmupUntil!) &&
              _directWarmupSong != null &&
              status.curMusic == _directWarmupSong;

          if (isWarmup &&
              state.currentMusic != null &&
              status.curMusic == state.currentMusic!.curMusic &&
              serverOffset < state.currentMusic!.offset) {
            status = PlayingMusic(
              ret: status.ret,
              curMusic: status.curMusic,
              curPlaylist: status.curPlaylist,
              isPlaying: status.isPlaying,
              offset: state.currentMusic!.offset,
              duration: status.duration,
            );
          }

          if (_lastServerOffset != null) {
            final diff = (serverOffset - _lastServerOffset!).abs();
            if (diff > 3) {
              debugPrint('🔄 [直连模式] 检测到进度跳跃，差异: ${diff}秒，重新校准');
            }
          }
          _lastServerOffset = status.offset;
          _lastUpdateTime = DateTime.now();

          // 🎯 保留已有的有效 duration，避免策略返回的 0 覆盖乐观更新的值
          final existingDuration = state.currentMusic?.duration ?? 0;
          if (status.duration == 0 &&
              existingDuration > 0 &&
              status.curMusic == state.currentMusic?.curMusic) {
            status = PlayingMusic(
              ret: status.ret,
              curMusic: status.curMusic,
              curPlaylist: status.curPlaylist,
              isPlaying: status.isPlaying,
              offset: status.offset,
              duration: existingDuration,
            );
          }

          state = state.copyWith(
            currentMusic: status,
            hasLoaded: true,
            isLoading: silent ? state.isLoading : false,
            albumCoverUrl: isSongChanged ? null : state.albumCoverUrl,
          );

          // 🖼️ 自动搜索封面图
          if (status.curMusic.isNotEmpty &&
              (state.albumCoverUrl == null || state.albumCoverUrl!.isEmpty)) {
            debugPrint(
              '🖼️ [PlaybackProvider-直连] ✅ 触发封面自动搜索: ${status.curMusic}',
            );
            _autoFetchAlbumCover(status.curMusic).catchError((e) {
              debugPrint('🖼️ [AutoCover] 异步搜索封面失败: $e');
            });
          }

          final warmupReady =
              isWarmup &&
              status.offset >= 1 &&
              status.duration > 0 &&
              status.curMusic == _directWarmupSong;
          if (warmupReady) {
            _directWarmupUntil = null;
            _directWarmupSong = null;
            debugPrint('✅ [PlaybackProvider] 直连 warmup 结束，切换到常规进度预测');
          }

          final allowLocalPredict = !isWarmup || warmupReady;
          if (status.isPlaying && allowLocalPredict) {
            if (_localProgressTimer == null) {
              _startProgressTimer(true);
              debugPrint('✅ [PlaybackProvider] 直连模式已启动进度预测定时器');
            }
          } else {
            if (_localProgressTimer != null || _statusRefreshTimer != null) {
              _startProgressTimer(false);
              debugPrint('✅ [PlaybackProvider] 直连模式已停止进度预测定时器');
            }
          }
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

    if (_remoteRefreshInFlight) {
      debugPrint('🎵 [PlaybackProvider] 远程状态刷新进行中，跳过本次请求');
      return;
    }

    _lastRefreshTime = now;
    _remoteRefreshInFlight = true;

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
      final rawMusic = await _currentStrategy?.getCurrentStatus();
      final currentMusic = _sanitizeRemoteStatus(rawMusic);
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
      } else if (state.currentMusic != null &&
          currentMusic != null &&
          state.currentMusic!.duration > 0 &&
          currentMusic.duration > 0) {
        final oldSongName = state.currentMusic!.curMusic;
        final newSongName = currentMusic.curMusic;
        // 新接口可能短暂返回空标题，空标题不视为切歌，避免误重置进度
        if (newSongName.isNotEmpty && oldSongName != newSongName) {
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

      // 🛡️ 乐观更新保护：如果在保护期内，保留本地的歌曲名和播放状态
      // 这是为了防止定时器的 refreshStatus() 覆盖 playOnlineItem 的乐观更新
      PlayingMusic? finalMusic = currentMusic;

      // /getplayerstatus 某些阶段可能没有歌曲名，避免用空值覆盖当前歌曲
      if (finalMusic != null &&
          finalMusic.curMusic.trim().isEmpty &&
          state.currentMusic != null &&
          state.currentMusic!.curMusic.trim().isNotEmpty) {
        finalMusic = PlayingMusic(
          ret: finalMusic.ret,
          curMusic: state.currentMusic!.curMusic,
          curPlaylist:
              finalMusic.curPlaylist.isNotEmpty
                  ? finalMusic.curPlaylist
                  : state.currentMusic!.curPlaylist,
          isPlaying: finalMusic.isPlaying,
          offset: finalMusic.offset,
          duration:
              finalMusic.duration > 0
                  ? finalMusic.duration
                  : state.currentMusic!.duration,
        );
      }

      if (_optimisticUpdateProtectionUntil != null &&
          DateTime.now().isBefore(_optimisticUpdateProtectionUntil!)) {
        debugPrint('🛡️ [PlaybackProvider] 保护期内，保留本地歌曲名和播放状态');
        if (state.currentMusic != null) {
          final shouldUseServerProgress =
              currentMusic != null &&
              currentMusic.curMusic == state.currentMusic!.curMusic;
          // 🎯 保护期内保留本地歌曲名 + 播放状态
          // 仅当服务器歌曲名一致时才更新进度，避免旧歌覆盖
          // 🎯 但当本地 duration 为 0 时，允许用服务器的 duration（进度条需要 duration 才能显示）
          final localDuration = state.currentMusic!.duration;
          final serverDuration = currentMusic?.duration ?? 0;
          final bestDuration =
              shouldUseServerProgress
                  ? currentMusic!.duration
                  : (localDuration > 0 ? localDuration : serverDuration);
          final bestOffset =
              shouldUseServerProgress
                  ? currentMusic!.offset
                  : state.currentMusic!.offset;
          finalMusic = PlayingMusic(
            ret: currentMusic?.ret ?? state.currentMusic!.ret,
            curMusic: state.currentMusic!.curMusic, // 🛡️ 保留本地歌曲名
            curPlaylist: state.currentMusic!.curPlaylist, // 🛡️ 保留本地播放列表
            isPlaying: state.currentMusic!.isPlaying, // 🛡️ 保留本地播放状态
            offset: bestOffset,
            duration: bestDuration,
          );
          // 🎯 不触发歌曲切换检测
          isSongChanged = false;
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
          debugPrint(
            '🎯 [收藏检查] 直连模式 - ${currentMusic.curMusic}: ${isFavorite ? "已收藏" : "未收藏"}',
          );
        } else {
          // xiaomusic模式：重置为false（由服务器端管理）
          isFavorite = false;
        }
      }

      // 🎯 远程模式：用本地队列名覆盖服务器返回的歌单名（如 "全部"）
      // 服务器返回的 cur_playlist 是 xiaomusic 内部歌单名，
      // 而用户实际可能在从搜索结果/自定义歌单播放
      if (finalMusic != null) {
        final realQueueName = _getCurrentQueueName();
        // 🎯 当服务端返回 duration=0 时（playurl 场景），从 APP 队列获取 duration 作为 fallback
        int finalDuration = finalMusic.duration;
        if (finalDuration <= 0) {
          final queueState = ref.read(playbackQueueProvider);
          final queue = queueState.queue;
          if (queue != null) {
            final currentItem = queue.items.cast<PlaylistItem?>().firstWhere(
              (item) => item!.displayName == finalMusic?.curMusic,
              orElse: () => null,
            );
            if (currentItem != null && currentItem.duration > 0) {
              finalDuration = currentItem.duration;
              debugPrint(
                '🎯 [PlaybackProvider] 使用队列中的 duration 补充: ${finalDuration}秒',
              );
            }
          }
        }

        if (realQueueName.isNotEmpty &&
                realQueueName != finalMusic.curPlaylist ||
            finalDuration != finalMusic.duration) {
          finalMusic = PlayingMusic(
            ret: finalMusic.ret,
            curMusic: finalMusic.curMusic,
            curPlaylist:
                realQueueName.isNotEmpty
                    ? realQueueName
                    : finalMusic.curPlaylist,
            isPlaying: finalMusic.isPlaying,
            offset: finalMusic.offset,
            duration: finalDuration,
          );
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

      // 远程模式也持久化最后播放信息，供重启后恢复显示
      if (finalMusic != null && finalMusic.curMusic.trim().isNotEmpty) {
        await _saveRemotePlayback(finalMusic);
      }

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
      debugPrint(
        '🖼️ [PlaybackProvider] currentMusic: ${currentMusic?.curMusic}',
      );
      debugPrint(
        '🖼️ [PlaybackProvider] albumCoverUrl: ${state.albumCoverUrl}',
      );
      debugPrint('🖼️ [PlaybackProvider] isSongChanged: $isSongChanged');

      final coverSongName = (currentMusic?.curMusic ?? '').trim();
      if (coverSongName.isNotEmpty &&
          (state.albumCoverUrl == null || state.albumCoverUrl!.isEmpty)) {
        debugPrint('🖼️ [PlaybackProvider] ✅ 触发封面自动搜索: $coverSongName');
        // 异步搜索封面图，不阻塞主流程
        _autoFetchAlbumCover(coverSongName).catchError((e) {
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
        final canPredictProgress =
            currentMusic != null && currentMusic.isPlaying;
        // 🎯 不再要求 duration>0，playurl 场景也需要本地进度递增
        _startProgressTimer(canPredictProgress);
        debugPrint('✅ [PlaybackProvider] xiaomusic远程模式已启动进度预测定时器');

        // 🎯 xiaomusic 模式自动下一首检测
        // 当使用懒加载队列播放在线音乐时，服务端播完不会自动从 APP 队列取下一首
        // 需要 APP 端检测歌曲是否接近结尾并主动推送下一首
        await _checkXiaomusicAutoNext(currentMusic);
      } else {
        debugPrint(
          'ℹ️ [PlaybackProvider] 当前模式不需要进度预测定时器（${_currentStrategy?.runtimeType ?? "未初始化"}）',
        );
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
    } finally {
      _remoteRefreshInFlight = false;
    }
  }

  PlayingMusic? _sanitizeRemoteStatus(PlayingMusic? remote) {
    if (remote == null) return null;

    int safeDuration = remote.duration;
    int safeOffset = remote.offset;
    bool invalidOffset = false;

    final local = state.currentMusic;

    // 服务器偶发返回 duration=0，优先保留本地已知时长
    if (safeDuration <= 0 && local != null && local.duration > 0) {
      safeDuration = local.duration;
    } else if (safeDuration <= 0) {
      // 尝试使用队列中的时长兜底
      final queueState = ref.read(playbackQueueProvider);
      final queueDuration = queueState.queue?.currentItem?.duration ?? 0;
      if (queueDuration > 0) {
        safeDuration = queueDuration;
      }
    }

    // 过滤异常 offset（例如时间戳）
    if (safeDuration > 0 && safeOffset > safeDuration + 300) {
      invalidOffset = true;
    } else if (safeDuration == 0 && safeOffset > 36000) {
      invalidOffset = true;
    }

    if (invalidOffset) {
      debugPrint(
        '⚠️ [PlaybackProvider] 发现异常 offset=${remote.offset}, duration=${remote.duration}，使用本地进度兜底',
      );
      safeOffset = local?.offset ?? 0;
    }

    if (safeDuration != remote.duration || safeOffset != remote.offset) {
      return PlayingMusic(
        ret: remote.ret,
        isPlaying: remote.isPlaying,
        curMusic: remote.curMusic,
        curPlaylist: remote.curPlaylist,
        offset: safeOffset,
        duration: safeDuration,
      );
    }

    return remote;
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
        } else if (directState.playbackDeviceType.isEmpty) {
          // 🔧 修复：检查 playbackDeviceType
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
      _optimisticUpdateProtectionUntil = DateTime.now().add(
        const Duration(seconds: 2),
      );
      debugPrint('🛡️ [PlaybackProvider] 设置乐观更新保护期: 2秒');

      // 🎯 直连模式 resume：清除 warmup 保护，允许策略的预通知将进度立即归 0
      // warmup 是为「新歌切换」设计的，resume 不需要它，否则会拦截 serverOffset=0 的更新
      if (_currentStrategy is MiIoTDirectPlaybackStrategy) {
        _directWarmupUntil = null;
        _directWarmupSong = null;
        debugPrint('🎯 [PlaybackProvider] 直连模式 resume：已清除 warmup 保护');
      }

      // 🔧 只有 xiaomusic 远程模式需要更新进度定时器
      // - 本地模式：通过statusStream自动更新（不需要）
      // - 直连模式：通过策略轮询更新（不需要）
      // - xiaomusic远程模式：需要本地预测进度
      if (!_currentStrategy!.isLocalMode &&
          _currentStrategy is! MiIoTDirectPlaybackStrategy) {
        _lastServerOffset = state.currentMusic!.offset;
        _lastUpdateTime = DateTime.now();
        _startProgressTimer(true);
      }
    }

    try {
      // 🎯 playUrl 模式（元歌单）：「播放歌曲」会触发 xiaomusic 服务端歌单播放，
      // 无法恢复 playUrl 歌曲 → 必须重新推送 URL 播放当前队列歌曲
      if (_currentStrategy is RemotePlaybackStrategy) {
        final remoteStrategy = _currentStrategy as RemotePlaybackStrategy;
        if (remoteStrategy.activeApiGroupName == 'playurl') {
          final queueState = ref.read(playbackQueueProvider);
          final currentItem = queueState.queue?.currentItem;
          if (currentItem != null && currentItem.isOnline) {
            debugPrint(
              '🎵 [PlaybackProvider] playUrl 模式恢复播放 → 重新播放当前元歌单歌曲: ${currentItem.displayName}',
            );
            await _playNextItem(currentItem);

            // 🔄 静默刷新
            await Future.delayed(const Duration(milliseconds: 500));
            await refreshStatus(silent: true);
            return;
          }
        }
      }

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
        } else if (directState.playbackDeviceType.isEmpty) {
          // 🔧 修复：检查 playbackDeviceType
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
      _optimisticUpdateProtectionUntil = DateTime.now().add(
        const Duration(seconds: 2),
      );
      debugPrint('🛡️ [PlaybackProvider] 设置乐观更新保护期: 2秒');

      // 🔧 只有 xiaomusic 远程模式需要更新进度定时器
      // - 本地模式：通过statusStream自动更新（不需要）
      // - 直连模式：通过策略轮询更新（不需要）
      if (!_currentStrategy!.isLocalMode &&
          _currentStrategy is! MiIoTDirectPlaybackStrategy) {
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
        if (!_currentStrategy!.isLocalMode &&
            _currentStrategy is! MiIoTDirectPlaybackStrategy) {
          _startProgressTimer(!isPlaying);
          if (!isPlaying) {
            _lastServerOffset = state.currentMusic!.offset;
            _lastUpdateTime = DateTime.now();
          }
        }
      }

      // 异步执行实际命令（通过策略）
      if (isPlaying) {
        // 🎯 playUrl 模式（元歌单）：使用 stopDevice（无 TTS）暂停
        if (_currentStrategy is RemotePlaybackStrategy &&
            (_currentStrategy as RemotePlaybackStrategy).activeApiGroupName ==
                'playurl') {
          debugPrint('🎵 [PlaybackProvider] playUrl 模式暂停 → 通过策略处理');
        }
        await _currentStrategy!.pause();
      } else {
        // 🎯 playUrl 模式（元歌单）：重新播放当前歌曲代替「播放歌曲」命令
        if (_currentStrategy is RemotePlaybackStrategy) {
          final remoteStrategy = _currentStrategy as RemotePlaybackStrategy;
          if (remoteStrategy.activeApiGroupName == 'playurl') {
            final queueState = ref.read(playbackQueueProvider);
            final currentItem = queueState.queue?.currentItem;
            if (currentItem != null && currentItem.isOnline) {
              debugPrint(
                '🎵 [PlaybackProvider] playUrl 模式恢复播放 → 重新播放当前元歌单歌曲: ${currentItem.displayName}',
              );
              await _playNextItem(currentItem);

              // 🔄 静默刷新
              await Future.delayed(const Duration(milliseconds: 500));
              await refreshStatus(silent: true);
              return;
            }
          }
        }
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
      // 🎯 不再一开始就设置 isLoading: true，让 UI 立即响应
      debugPrint('🎵 执行上一首命令');

      // 🎯 优先级0：有 APP 端播放队列 → 统一走队列逻辑（不区分 single/random）
      {
        final queueState = ref.read(playbackQueueProvider);
        if (queueState.queue != null && queueState.queue!.items.isNotEmpty) {
          debugPrint('🎵 [previous] 检测到 APP 端队列，统一走队列逻辑');
          final playbackMode = ref.read(playbackModeProvider);

          // 🎯 保存当前状态用于失败回滚
          final oldMusic = state.currentMusic;
          final oldCoverUrl = state.albumCoverUrl;
          final oldQueueIndex = queueState.queue!.currentIndex;

          final prevItem = ref.read(playbackQueueProvider.notifier).previous();
          if (prevItem != null) {
            debugPrint('🎵 [previous] 队列上一首: ${prevItem.title}');

            if (playbackMode == PlaybackMode.miIoTDirect) {
              _applyOptimisticUpdate(prevItem);
              try {
                await _playFromQueueItem(prevItem);
              } catch (e) {
                // 🔄 播放失败，回滚 UI 和队列索引
                debugPrint('🔄 [previous] 播放失败，回滚到原来的歌');
                ref.read(playbackQueueProvider.notifier).jumpToIndex(oldQueueIndex);
                _optimisticUpdateProtectionUntil = null;
                state = state.copyWith(
                  currentMusic: oldMusic,
                  albumCoverUrl: oldCoverUrl,
                  error: '切歌失败: ${prevItem.title}',
                );
                return;
              }
            } else {
              await _playNextItem(prevItem);
            }

            await Future.delayed(const Duration(milliseconds: 500));
            await refreshStatus(silent: true);
            return;
          } else {
            debugPrint('⚠️ [previous] 队列已到开头（顺序播放模式）');
            state = state.copyWith(error: '已是第一首');
            return;
          }
        }
      }

      // 🎯 根据播放模式执行不同逻辑（无 APP 队列时走旧逻辑）
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
          // 其他模式：无 APP 队列时使用策略的正常逻辑
          debugPrint('🎵 [播放模式] ${state.playMode.displayName} - 无队列，使用策略逻辑');

          // 🎯 使用旧的策略逻辑（xiaomusic/本地播放/旧逻辑）
          debugPrint('🎵 [PlaybackProvider] 使用策略模式播放（xiaomusic/本地/旧逻辑）');
          await _currentStrategy!.previous(); // ✅ xiaomusic 和本地播放完全不受影响

          // 等待命令执行后刷新状态
          await Future.delayed(const Duration(milliseconds: 1000));

          // 🔄 远程模式需要刷新状态（静默刷新，避免二次 loading）
          if (!_currentStrategy!.isLocalMode) {
            await refreshStatus(silent: true);
          }
          break;
      }
    } catch (e) {
      print('🎵 上一首失败: $e');
      state = state.copyWith(error: '上一首失败: ${e.toString()}');
      // 🎯 失败恢复：清除保护期 + 刷新真实状态 + 重启定时器
      _optimisticUpdateProtectionUntil = null;
      _directWarmupUntil = null;
      _directWarmupSong = null;
      // 🔇 解除策略层切歌准备期，恢复轮询
      if (_currentStrategy is MiIoTDirectPlaybackStrategy) {
        (_currentStrategy as MiIoTDirectPlaybackStrategy).cancelSongSwitchPending();
      }
      await refreshStatus(silent: true);
    }
  }

  /// 🎯 立即乐观更新 UI（无转圈），用于 next/previous 队列播放
  void _applyOptimisticUpdate(PlaylistItem item) {
    // 设置保护期
    _optimisticUpdateProtectionUntil = DateTime.now().add(
      const Duration(seconds: 10),
    );
    _directSwitchSessionId += 1;
    _directWarmupUntil = DateTime.now().add(const Duration(seconds: 8));
    _directWarmupSong = item.displayName;
    debugPrint('🛡️ [_applyOptimisticUpdate] 设置乐观更新保护期: 10秒');

    // 🔇 通知策略层：切歌准备中，丢弃旧歌轮询结果
    if (_currentStrategy is MiIoTDirectPlaybackStrategy) {
      (_currentStrategy as MiIoTDirectPlaybackStrategy).prepareSongSwitch();
    }

    final optimisticMusic = PlayingMusic(
      ret: 'OK',
      curMusic: item.displayName,
      curPlaylist: _getCurrentQueueName(),
      isPlaying: true,
      duration: item.duration ?? 0,
      offset: 0,
    );
    state = state.copyWith(
      currentMusic: optimisticMusic,
      isLoading: false, // 🎯 立即显示播放状态，不转圈
      error: null,
      albumCoverUrl: item.coverUrl,
    );

    // 🎯 停止旧歌的定时器 + 重置预测基准
    // 但不启动新定时器 —— 等推送成功后由 onStatusChanged → refreshStatus 启动
    // 这样 URL 解析期间进度保持 0，推送成功后才开始计时
    _localProgressTimer?.cancel();
    _localProgressTimer = null;
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = null;
    _lastServerOffset = 0;
    _lastUpdateTime = DateTime.now();
    _lastProgressUpdate = null;

    debugPrint('✨ [_applyOptimisticUpdate] 乐观更新UI（无转圈）: ${item.displayName}');
    debugPrint('⏸️ [_applyOptimisticUpdate] 进度定时器已停止，warmup期间使用1s真实轮询');
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
      // 🎯 不再一开始就设置 isLoading: true，让 UI 立即响应
      debugPrint('🎵 执行下一首命令');

      // 🎯 优先级0：有 APP 端播放队列 → 统一走队列逻辑（不区分 single/random）
      {
        final queueState = ref.read(playbackQueueProvider);
        if (queueState.queue != null && queueState.queue!.items.isNotEmpty) {
          debugPrint('🎵 [next] 检测到 APP 端队列，统一走队列逻辑');
          final playbackMode = ref.read(playbackModeProvider);

          // 🎯 保存当前状态用于失败回滚
          final oldMusic = state.currentMusic;
          final oldCoverUrl = state.albumCoverUrl;
          final oldQueueIndex = queueState.queue!.currentIndex;

          final nextItem = ref.read(playbackQueueProvider.notifier).next();
          if (nextItem != null) {
            debugPrint('🎵 [next] 队列下一首: ${nextItem.title}');

            if (playbackMode == PlaybackMode.miIoTDirect) {
              _applyOptimisticUpdate(nextItem);
              try {
                await _playFromQueueItem(nextItem);
              } catch (e) {
                // 🔄 播放失败，回滚 UI 和队列索引
                debugPrint('🔄 [next] 播放失败，回滚到上一首');
                ref.read(playbackQueueProvider.notifier).jumpToIndex(oldQueueIndex);
                _optimisticUpdateProtectionUntil = null;
                state = state.copyWith(
                  currentMusic: oldMusic,
                  albumCoverUrl: oldCoverUrl,
                  error: '切歌失败: ${nextItem.title}',
                );
                return;
              }
            } else {
              await _playNextItem(nextItem);
            }

            await Future.delayed(const Duration(milliseconds: 500));
            await refreshStatus(silent: true);
            return;
          } else {
            debugPrint('⚠️ [next] 队列已到末尾（顺序播放模式）');
            state = state.copyWith(error: '已是最后一首');
            return;
          }
        }
      }

      // 🎯 根据播放模式执行不同逻辑（无 APP 队列时走旧逻辑）
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
          // 其他模式：无 APP 队列时使用策略的正常逻辑
          debugPrint('🎵 [播放模式] ${state.playMode.displayName} - 无队列，使用策略逻辑');

          // 🎯 使用旧的策略逻辑（xiaomusic/本地播放/旧逻辑）
          debugPrint('🎵 [PlaybackProvider] 使用策略模式播放（xiaomusic/本地/旧逻辑）');
          await _currentStrategy!.next(); // ✅ xiaomusic 和本地播放完全不受影响

          // 等待命令执行后刷新状态
          await Future.delayed(const Duration(milliseconds: 1000));

          // 🔄 远程模式需要刷新状态（静默刷新，避免二次 loading）
          if (!_currentStrategy!.isLocalMode) {
            await refreshStatus(silent: true);
          }
          break;
      }
    } catch (e) {
      print('🎵 下一首失败: $e');
      state = state.copyWith(error: '下一首失败: ${e.toString()}');
      // 🎯 失败恢复：清除保护期 + 刷新真实状态 + 重启定时器
      // 避免 _applyOptimisticUpdate 停掉定时器后，失败导致 UI 卡在"新歌 0 秒"
      _optimisticUpdateProtectionUntil = null;
      _directWarmupUntil = null;
      _directWarmupSong = null;
      // 🔇 解除策略层切歌准备期，恢复轮询
      if (_currentStrategy is MiIoTDirectPlaybackStrategy) {
        (_currentStrategy as MiIoTDirectPlaybackStrategy).cancelSongSwitchPending();
      }
      await refreshStatus(silent: true);
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
      // 🎯 立即更新本地预测基准，避免 250ms 定时器用旧值导致进度条回弹
      _lastServerOffset = seconds;
      _lastUpdateTime = DateTime.now();

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
    String? playlistName, // 🎵 新增：歌单名称（用于 UI 显示和 API 调用）
    int? duration, // 🎯 新增：歌曲时长（秒），用于乐观更新进度条
  }) async {
    // 🎵 使用策略模式播放
    if (_currentStrategy == null) {
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化，尝试切换设备');

      final playbackMode = ref.read(playbackModeProvider);

      if (playbackMode == PlaybackMode.miIoTDirect) {
        // 直连模式：优先使用直连策略初始化，避免误走远程设备列表
        final directState = ref.read(directModeProvider);
        if (directState is DirectModeAuthenticated &&
            directState.playbackDeviceType.isNotEmpty) {
          await _switchToDirectModeStrategy(directState);
        }
      } else {
        // xiaomusic 模式：根据设备ID切换远程策略
        final deviceState = ref.read(deviceProvider);
        if (deviceState.devices.isNotEmpty) {
          await _switchStrategy(deviceId, deviceState.devices);
        }
      }

      if (_currentStrategy == null) {
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
      // 🎯 检查是否在保护期内，如果是则不覆盖 playOnlineItem 的乐观更新
      final inProtectionPeriod =
          _optimisticUpdateProtectionUntil != null &&
          DateTime.now().isBefore(_optimisticUpdateProtectionUntil!);

      // 🎯 duration 提前计算，后续传给策略层使用
      int optimisticDuration = 0;

      if (musicName != null && musicName.isNotEmpty) {
        final existingMusic = state.currentMusic;
        final keepExistingDuration =
            inProtectionPeriod &&
            existingMusic != null &&
            existingMusic.curMusic == musicName &&
            existingMusic.duration > 0;

        // 🎯 duration 优先级：传入参数 > 保护期已有值 > 队列中的值 > 0
        if (duration != null && duration > 0) {
          optimisticDuration = duration;
        } else if (keepExistingDuration) {
          optimisticDuration = existingMusic.duration;
        } else {
          // 从队列中查找 duration
          final queueState = ref.read(playbackQueueProvider);
          final currentItem = queueState.queue?.currentItem;
          if (currentItem != null &&
              currentItem.duration > 0 &&
              currentItem.displayName == musicName) {
            optimisticDuration = currentItem.duration;
          }
        }

        final optimisticMusic = PlayingMusic(
          ret: 'OK',
          curMusic: musicName,
          curPlaylist: _getCurrentQueueName(),
          isPlaying: true, // 乐观地认为会播放成功
          duration: optimisticDuration,
          offset: 0, // 进度从0开始
        );

        state = state.copyWith(
          currentMusic: optimisticMusic,
          isLoading: inProtectionPeriod ? false : true, // 🎯 保护期内不设置 loading
          error: null,
          albumCoverUrl: albumCoverUrl, // 如果有封面图，立即显示
        );
        debugPrint(
          '✨ [PlaybackProvider] 乐观更新UI: $musicName (保护期: $inProtectionPeriod, duration: $optimisticDuration)',
        );
      } else {
        state = state.copyWith(
          isLoading: inProtectionPeriod ? false : true, // 🎯 保护期内不设置 loading
          error: null,
        );
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
          final directStrategy =
              _currentStrategy as MiIoTDirectPlaybackStrategy;
          directStrategy.setPlaylist(playlist, startIndex: playIndex);
        }

        // 🎯 方案A：同时更新 PlaybackQueueProvider（统一队列管理）
        // 将 Music 列表转换为 PlaylistItem 列表
        final queueItems =
            playlist.map((m) => PlaylistItem.fromMusic(m)).toList();
        ref
            .read(playbackQueueProvider.notifier)
            .setQueue(
              queueName: playlistName ?? '播放列表',
              source: PlaylistSource.musicLibrary,
              items: queueItems,
              startIndex: playIndex,
            );
        debugPrint(
          '🎯 [PlaybackProvider] 已同步更新 PlaybackQueueProvider，共 ${queueItems.length} 首',
        );

        debugPrint('🎵 [PlaybackProvider] 播放列表已设置，开始索引: $playIndex');
      }

      int? directSessionId;
      if (_currentStrategy is MiIoTDirectPlaybackStrategy &&
          musicName != null &&
          musicName.isNotEmpty) {
        _directSwitchSessionId += 1;
        _directWarmupUntil = DateTime.now().add(const Duration(seconds: 8));
        _directWarmupSong = musicName;
        directSessionId = _directSwitchSessionId;

        // 🔇 通知策略层：切歌准备中，丢弃旧歌轮询结果
        (_currentStrategy as MiIoTDirectPlaybackStrategy).prepareSongSwitch();
      }

      // 使用策略播放
      await _currentStrategy!.playMusic(
        musicName: musicName ?? '',
        url: url,
        duration: optimisticDuration > 0 ? optimisticDuration : duration, // 🎯 传递 duration 到策略层
        switchSessionId: directSessionId,
      );

      debugPrint('✅ [PlaybackProvider] 播放请求成功');

      // 🖼️ 处理封面图（4种情况）
      if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
        // 情况1: 在线搜索音乐 - 直接使用搜索结果的封面图
        if (_isValidCoverUrl(albumCoverUrl)) {
          debugPrint('🖼️ [PlaybackProvider] 使用搜索结果的封面图: $albumCoverUrl');
          updateAlbumCover(albumCoverUrl);
        } else if (musicName != null && musicName.isNotEmpty) {
          debugPrint('⚠️ [PlaybackProvider] 搜索结果封面无效，改为自动搜索: $musicName');
          _autoFetchAlbumCover(musicName).catchError((e) {
            debugPrint('🖼️ [AutoCover] 搜索封面失败: $e');
          });
        }
      } else if (musicName != null && musicName.isNotEmpty) {
        // 情况2/3/4: 服务器音乐 / 本地音乐 / 直连模式 - 都需要自动搜索封面
        debugPrint(
          '🖼️ [PlaybackProvider] 自动搜索封面: $musicName (当前策略: ${_currentStrategy?.runtimeType})',
        );
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

    // 🎯 直连模式：策略层已有自己的轮询，通过 onStatusChanged 回调同步真实进度
    // 不需要额外的 _statusRefreshTimer，否则会读到策略层的过时 offset 导致进度条回跳
    final isDirect = _currentStrategy is MiIoTDirectPlaybackStrategy;

    if (isPlaying && state.currentMusic != null) {
      if (!isDirect) {
        // 非直连模式：需要 Provider 层主动轮询
        final duration = state.currentMusic?.duration ?? 0;
        final refreshInterval = duration > 300 ? 5 : 3;
        _statusRefreshTimer = Timer.periodic(
          Duration(seconds: refreshInterval),
          (_) {
            refreshStatus(silent: true);
          },
        );
        debugPrint('⏰ 启动智能进度定时器，刷新间隔: ${refreshInterval}秒');
      }

      // 本地平滑预测（所有模式通用）
      _localProgressTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) {
        _updateLocalProgress();
      });

      if (isDirect) {
        debugPrint('⏰ 启动本地进度预测定时器（直连模式，策略层轮询负责校正）');
      }
    } else if (!isPlaying && state.currentMusic != null) {
      // 🎯 暂停状态：非直连模式保持低频轮询用于自动下一首检测
      // 直连模式策略层已有自己的轮询，同样不需要额外 _statusRefreshTimer
      if (!isDirect) {
        final queueState = ref.read(playbackQueueProvider);
        if (queueState.queue != null && queueState.queue!.items.isNotEmpty) {
          _statusRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
            refreshStatus(silent: true);
          });
          debugPrint('⏰ 暂停状态但有播放队列，保持低频轮询（3秒）用于自动下一首检测');
        } else {
          debugPrint('⏸️ 停止进度定时器（无播放队列）');
        }
      } else {
        debugPrint('⏸️ 直连模式暂停，策略层轮询负责检测状态变化');
      }
    } else {
      debugPrint('⏸️ 停止进度定时器');
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
    // 1. 确保进度不超过总时长（duration>0 时）
    // 2. 避免倒退（除非是合理的小幅调整）
    // 3. 限制更新频率避免UI抖动
    // 4. duration=0（playurl 场景）时也递增进度（仅显示已播放时间）
    final newOffset = predictedOffset.floor();

    final withinDuration =
        duration <= 0 || newOffset < duration; // 🎯 duration=0 时不限制上限
    if (withinDuration &&
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
      debugPrint(
        '🔧 [PlaybackProvider] 缓存内容: ${jsonStr?.substring(0, jsonStr.length > 100 ? 100 : jsonStr.length) ?? "null"}',
      );

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
      final url =
          (_currentStrategy is LocalPlaybackStrategy)
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

  String _remotePlaybackKeyFor(String deviceId) {
    return '${_remotePlaybackKey}_$deviceId';
  }

  String _remotePlaybackCoverKeyFor(String deviceId) {
    return '${_remotePlaybackCoverKey}_$deviceId';
  }

  String _remotePlaybackApiGroupKeyFor(String deviceId) {
    return '${_remotePlaybackApiGroupKey}_$deviceId';
  }

  Future<void> _loadRemotePlayback(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_remotePlaybackKeyFor(deviceId));
      if (jsonStr == null || jsonStr.isEmpty) return;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final pm = PlayingMusic(
        ret: data['ret'] as String? ?? 'OK',
        curMusic: data['curMusic'] as String? ?? '',
        curPlaylist: (data['curPlaylist'] as String?) ?? '在线播放',
        isPlaying: false, // 恢复展示态，实际播放态以远端轮询为准
        offset: data['offset'] as int? ?? 0,
        duration: data['duration'] as int? ?? 0,
      );
      final cachedCover = prefs.getString(_remotePlaybackCoverKeyFor(deviceId));

      if (pm.curMusic.trim().isEmpty) return;

      state = state.copyWith(
        currentMusic: pm,
        albumCoverUrl:
            (cachedCover != null && cachedCover.isNotEmpty)
                ? cachedCover
                : state.albumCoverUrl,
        hasLoaded: true,
        isLoading: false,
      );

      debugPrint('💾 [PlaybackProvider] 已恢复远程播放缓存: ${pm.curMusic}');
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 恢复远程播放缓存失败: $e');
    }
  }

  Future<void> _saveRemotePlayback(PlayingMusic status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final did = ref.read(deviceProvider).selectedDeviceId ?? _currentDeviceId;
      if (did == null || did.isEmpty) return;
      final data = {
        'deviceId': did,
        'ret': status.ret,
        'curMusic': status.curMusic,
        'curPlaylist': status.curPlaylist,
        'isPlaying': status.isPlaying,
        'offset': status.offset,
        'duration': status.duration,
      };
      await prefs.setString(_remotePlaybackKeyFor(did), jsonEncode(data));
      if (_currentStrategy is RemotePlaybackStrategy) {
        final group =
            (_currentStrategy as RemotePlaybackStrategy).activeApiGroupName;
        if (group != null && group.isNotEmpty) {
          await prefs.setString(_remotePlaybackApiGroupKeyFor(did), group);
        }
      }
      if (state.albumCoverUrl != null && state.albumCoverUrl!.isNotEmpty) {
        await prefs.setString(
          _remotePlaybackCoverKeyFor(did),
          state.albumCoverUrl!,
        );
      }
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 保存远程播放缓存失败: $e');
    }
  }

  /// 💾 保存直连模式播放状态（专用于直连模式）
  /// 🎯 直连模式歌曲播放完成处理：自动播放下一首
  ///
  /// 当直连模式检测到歌曲播放完成时，会调用此方法
  /// 从播放队列获取下一首歌曲并播放
  Future<void> _handleDirectModeSongComplete() async {
    debugPrint('🎵 [PlaybackProvider] 开始处理直连模式自动下一首');

    try {
      // 🎯 单曲循环短路：设备已在循环播放，APP 端无需干预
      final queueState = ref.read(playbackQueueProvider);
      if (queueState.queue != null &&
          queueState.queue!.playMode == QueuePlayMode.singleLoop) {
        debugPrint('🔂 [PlaybackProvider] 单曲循环模式，设备自行循环，跳过自动下一首');
        return;
      }

      // 检查播放队列
      if (queueState.queue == null || queueState.queue!.items.isEmpty) {
        debugPrint('⚠️ [PlaybackProvider] 播放队列为空，无法自动播放下一首');
        return;
      }

      // 🎯 保存当前队列索引用于失败回滚
      final oldQueueIndex = queueState.queue!.currentIndex;

      // 获取下一首歌曲
      final nextItem = ref.read(playbackQueueProvider.notifier).next();
      if (nextItem == null) {
        debugPrint('⚠️ [PlaybackProvider] 播放队列已到末尾（顺序播放模式）');
        return;
      }

      debugPrint('🎵 [PlaybackProvider] 下一首歌曲: ${nextItem.displayName}');
      debugPrint('🎵 [PlaybackProvider] 来源类型: ${nextItem.sourceType}');

      // 🎯 根据歌曲来源类型决定播放方式
      try {
      if (nextItem.isOnline) {
        // 🎵 在线歌曲：使用统一的 playOnlineItem 方法
        debugPrint('🎵 [PlaybackProvider] 在线歌曲，使用 playOnlineItem 播放');
        await playOnlineItem(nextItem);
      } else if (nextItem.isLocal && nextItem.localPath != null) {
        // 🎵 本地歌曲：直接使用本地路径播放
        debugPrint('🎵 [PlaybackProvider] 本地歌曲，直接播放: ${nextItem.localPath}');
        await _currentStrategy?.playMusic(
          musicName: nextItem.displayName,
          url: nextItem.localPath!,
          duration: nextItem.duration > 0 ? nextItem.duration : null, // 🎯 方案C
        );
      } else if (nextItem.isServer) {
        // 🎵 服务器歌曲（xiaomusic 模式）：直连模式下无法播放
        // 因为直连模式没有 xiaomusic 服务端来解析音乐
        debugPrint(
          '⚠️ [PlaybackProvider] 服务器歌曲在直连模式下无法播放: ${nextItem.displayName}',
        );
        // 尝试跳到下一首
        final nextNext = ref.read(playbackQueueProvider.notifier).next();
        if (nextNext != null && !nextNext.isServer) {
          debugPrint('🔄 [PlaybackProvider] 跳过服务器歌曲，尝试播放下一首');
          await _handleDirectModeSongComplete();
        }
      } else {
        debugPrint('⚠️ [PlaybackProvider] 歌曲没有有效的播放源');
      }
      } catch (e) {
        // 🔄 自动下一首播放失败，回滚队列索引
        debugPrint('🔄 [PlaybackProvider] 自动下一首播放失败，回滚队列索引');
        ref.read(playbackQueueProvider.notifier).jumpToIndex(oldQueueIndex);
        _optimisticUpdateProtectionUntil = null;
        state = state.copyWith(error: '自动播放下一首失败: ${nextItem.displayName}');
      }
    } catch (e) {
      debugPrint('❌ [PlaybackProvider] 自动下一首失败: $e');
    }
  }

  // 🎯 xiaomusic 模式自动下一首检测相关变量
  bool _xiaomusicAutoNextTriggered = false;
  String? _xiaomusicLastSongName;
  int _xiaomusicLastPosition = 0;
  int _xiaomusicLastDuration = 0;
  int _xiaomusicNearEndHits = 0;
  String? _xiaomusicLastAudioId; // 🎯 追踪 audio_id 变化
  DateTime? _xiaomusicAutoNextWarmupUntil; // 🎯 启动热身保护期，避免首次轮询误触发

  /// 🎯 xiaomusic 模式：检测歌曲是否接近结尾并触发自动下一首
  ///
  /// 当使用懒加载队列播放在线音乐时，服务端播完一首不会自动从 APP 队列取下一首
  /// 需要 APP 端检测并主动推送下一首
  ///
  /// 三重检测机制：
  /// 1. 接近结尾检测：position 接近 duration（阈值15秒，大于2倍轮询间隔）
  /// 2. 位置跳跃检测：上次接近结尾 → 这次回到开头
  /// 3. 歌曲异常切换检测：xiaomusic 自动切到非队列歌曲 → APP 介入
  Future<void> _checkXiaomusicAutoNext(PlayingMusic? currentMusic) async {
    if (currentMusic == null) return;

    // 检查是否有 APP 端的播放队列
    final queueState = ref.read(playbackQueueProvider);
    if (queueState.queue == null || queueState.queue!.items.isEmpty) {
      // 没有 APP 端队列，依赖服务端自己的播放列表管理
      return;
    }

    // 🎯 保护期内不做自动下一首检测（避免解析/切歌中误触发）
    if (_optimisticUpdateProtectionUntil != null &&
        DateTime.now().isBefore(_optimisticUpdateProtectionUntil!)) {
      return;
    }

    final currentSongName = currentMusic.curMusic;
    final position = currentMusic.offset;
    final duration = currentMusic.duration;
    final isPlaying = currentMusic.isPlaying;

    // ========== 检测方式C：歌曲异常切换检测（最可靠，优先级最高） ==========
    // 🎯 必须在 duration 检查之前！因为元歌单通过 playurl 播放时 duration=0，
    // 如果放在后面会被 duration<=0 的早期返回跳过，导致无法自动切歌。
    //
    // 原理：xiaomusic 服务端播完 APP 推送的歌后，会自动切回服务端自己的播放列表。
    // 如果新歌不在 APP 的播放队列中，说明服务端自行切歌了，APP 应该介入。
    if (_xiaomusicLastSongName != null &&
        currentSongName != _xiaomusicLastSongName &&
        !_xiaomusicAutoNextTriggered) {
      // 歌曲名发生了变化，检查新歌是否在 APP 队列中
      final queue = queueState.queue!;
      final isInQueue = queue.items.any(
        (item) => item.displayName == currentSongName,
      );

      // 🎯 判断上一首歌是否已播放完毕
      // 当 duration > 0 时：精确判断（上一首接近结尾 + 当前在开头）
      // 当 duration == 0 时（元歌单/playurl场景）：放宽条件，只要歌名变了且不在队列中就触发
      final hasDurationInfo = _xiaomusicLastDuration > 10;
      final nearEndThresholdC =
          hasDurationInfo
              ? (_xiaomusicLastDuration * 0.02).round().clamp(3, 8)
              : 0;
      final wasNearEnd =
          hasDurationInfo &&
          _xiaomusicLastPosition > 10 &&
          (_xiaomusicLastDuration - _xiaomusicLastPosition) < nearEndThresholdC;
      final isAtStart = position < 10;

      // 触发条件：新歌不在队列中 + (上一首接近结尾 或 上一首没有时长信息)
      final shouldTriggerC =
          !isInQueue && (wasNearEnd || !hasDurationInfo) && isAtStart;

      if (shouldTriggerC) {
        final reason = hasDurationInfo ? '上一首接近结尾' : '上一首无时长信息(元歌单/playurl)';
        debugPrint('🎵 [xiaomusic-AutoNext] 🔍 检测到歌曲异常切换! [$reason]');
        debugPrint('   上一首(APP推送): $_xiaomusicLastSongName');
        debugPrint('   当前(服务端自切): $currentSongName');
        debugPrint('   该歌曲不在APP队列中 → 触发自动下一首');

        _xiaomusicAutoNextTriggered = true;
        _xiaomusicLastSongName = currentSongName;

        // 🎯 从 APP 队列获取下一首
        final nextItem = ref.read(playbackQueueProvider.notifier).next();
        if (nextItem != null) {
          debugPrint('🎵 [xiaomusic-AutoNext] 下一首: ${nextItem.displayName}');
          try {
            await _playNextItem(nextItem);
            debugPrint('✅ [xiaomusic-AutoNext] 自动下一首播放成功(异常切换检测)');
          } catch (e) {
            debugPrint('❌ [xiaomusic-AutoNext] 自动下一首播放失败: $e');
            _xiaomusicAutoNextTriggered = false;
          }
        } else {
          debugPrint('⚠️ [xiaomusic-AutoNext] 队列已到末尾');
        }

        // 更新位置信息
        _xiaomusicLastPosition = position;
        _xiaomusicLastDuration = duration;
        return; // 已处理，提前返回
      }
    }

    // ========== 检测方式D：audio_id 变化检测（同名歌曲源切换） ==========
    // 🎯 当歌名没变但 audio_id 变了，说明服务端切到了同名但不同源的歌曲
    // 例如：元歌单的「伤不起」播完 → 服务端「全部」列表里的「伤不起」
    final currentAudioId = _currentStrategy?.lastAudioId;

    // 🛡️ 热身保护期内不做 audio_id 变化检测（避免启动时缓存旧值误触发）
    final inWarmup =
        _xiaomusicAutoNextWarmupUntil != null &&
        DateTime.now().isBefore(_xiaomusicAutoNextWarmupUntil!);
    if (inWarmup) {
      // 热身期：只更新追踪值，不触发检测
      if (currentAudioId != null) {
        _xiaomusicLastAudioId = currentAudioId;
      }
    } else if (currentAudioId != null &&
        _xiaomusicLastAudioId != null &&
        currentAudioId != _xiaomusicLastAudioId &&
        !_xiaomusicAutoNextTriggered) {
      // audio_id 变了，检查是否需要触发自动下一首
      final queue = queueState.queue!;
      final isAtStart = position < 10;

      // 🎯 判断上一首是否已播放完毕（duration=0 的 playurl 场景）
      final hasDurationInfo = _xiaomusicLastDuration > 10;

      if (!hasDurationInfo && isAtStart) {
        // 元歌单（playurl）场景：无 duration 信息 + 从头开始 → 服务端劫持
        debugPrint('🎵 [xiaomusic-AutoNext] 🔍 检测到 audio_id 变化（同名歌曲源切换）!');
        debugPrint('   歌名: $currentSongName（未变化）');
        debugPrint('   audio_id: $_xiaomusicLastAudioId → $currentAudioId');
        debugPrint('   上一首无时长信息(元歌单/playurl) → 触发自动下一首');

        _xiaomusicAutoNextTriggered = true;
        _xiaomusicLastAudioId = currentAudioId;

        final nextItem = ref.read(playbackQueueProvider.notifier).next();
        if (nextItem != null) {
          debugPrint('🎵 [xiaomusic-AutoNext] 下一首: ${nextItem.displayName}');
          try {
            await _playNextItem(nextItem);
            debugPrint('✅ [xiaomusic-AutoNext] 自动下一首播放成功(audio_id变化检测)');
          } catch (e) {
            debugPrint('❌ [xiaomusic-AutoNext] 自动下一首播放失败: $e');
            _xiaomusicAutoNextTriggered = false;
          }
        } else {
          debugPrint('⚠️ [xiaomusic-AutoNext] 队列已到末尾');
        }

        _xiaomusicLastPosition = position;
        _xiaomusicLastDuration = duration;
        return;
      }
    }
    // 更新 audio_id 追踪
    if (currentAudioId != null) {
      _xiaomusicLastAudioId = currentAudioId;
    }

    // 🔄 重置保护标志：当歌曲名变化时（新歌开始播放）
    if (currentSongName != _xiaomusicLastSongName) {
      if (_xiaomusicAutoNextTriggered) {
        debugPrint('🔄 [xiaomusic-AutoNext] 检测到新歌曲，重置保护标志');
      }
      _xiaomusicAutoNextTriggered = false;
      _xiaomusicLastSongName = currentSongName;
    }

    // ========== 检测方式E：duration=0 时的位置回跳检测 ==========
    // 🎯 playUrl 播放的元歌单歌曲，服务端返回 duration=0，
    // 歌曲播完后服务端会重新循环（同歌名、同 audio_id），position 从大值跳回开头。
    // Method A/B 因 duration<=0 会被跳过，所以需要单独处理。
    if (duration <= 0 &&
        _xiaomusicLastPosition > 30 &&
        position < 10 &&
        isPlaying &&
        !_xiaomusicAutoNextTriggered) {
      debugPrint('🎵 [xiaomusic-AutoNext] 🔍 检测到 playUrl 歌曲位置回跳（Method E）!');
      debugPrint('   歌名: $currentSongName');
      debugPrint(
        '   位置: ${_xiaomusicLastPosition}s → ${position}s (duration=0)',
      );
      debugPrint('   判定：元歌单歌曲播放完毕，服务端重新循环 → 触发自动下一首');

      _xiaomusicAutoNextTriggered = true;

      final nextItem = ref.read(playbackQueueProvider.notifier).next();
      if (nextItem != null) {
        debugPrint('🎵 [xiaomusic-AutoNext] 下一首: ${nextItem.displayName}');
        try {
          await _playNextItem(nextItem);
          debugPrint('✅ [xiaomusic-AutoNext] 自动下一首播放成功(playUrl位置回跳检测)');
        } catch (e) {
          debugPrint('❌ [xiaomusic-AutoNext] 自动下一首播放失败: $e');
          _xiaomusicAutoNextTriggered = false;
        }
      } else {
        debugPrint('⚠️ [xiaomusic-AutoNext] 队列已到末尾');
      }

      _xiaomusicLastPosition = position;
      _xiaomusicLastDuration = duration;
      return;
    }

    // duration/offset 不可靠时，跳过基于进度的检测（方式A/B）
    // 注意：方式C/D/E 已在上方处理，不受此限制
    if (duration <= 0 || position < 0 || !isPlaying) {
      _xiaomusicLastPosition = position;
      _xiaomusicLastDuration = duration;
      return;
    }

    final remaining = duration - position;
    final nearEndThreshold = (duration * 0.02).round().clamp(3, 8);
    final isAtEnd = duration > 0 && remaining <= 3;
    final shouldCountNearEnd = remaining > 0 && remaining <= nearEndThreshold;

    // ========== 检测方式A：position 接近 duration ==========
    // 🎯 阈值基于时长动态调整，避免短歌过早触发
    final isNearEnd =
        duration > 10 &&
        position > 10 &&
        shouldCountNearEnd &&
        position > (duration * 0.85);

    // ========== 检测方式B：位置跳跃检测 ==========
    // 上一次接近结尾 → 这一次回到开头（同一首歌循环播放的情况）
    final wasNearEndAB =
        _xiaomusicLastDuration > 10 &&
        _xiaomusicLastPosition > 10 &&
        (_xiaomusicLastDuration - _xiaomusicLastPosition) < nearEndThreshold;
    final jumpedToStart = position < 10;
    final isPositionJump = wasNearEndAB && jumpedToStart;

    if (isAtEnd) {
      _xiaomusicNearEndHits = 2;
    } else if (isNearEnd) {
      _xiaomusicNearEndHits += 1;
    } else {
      _xiaomusicNearEndHits = 0;
    }

    final shouldTrigger =
        ((isNearEnd && _xiaomusicNearEndHits >= 2) || isPositionJump) &&
        !_xiaomusicAutoNextTriggered;

    if (shouldTrigger) {
      final reason =
          isNearEnd
              ? '接近结尾(剩${duration - position}秒)'
              : '位置跳跃(${_xiaomusicLastPosition}s→${position}s)';
      debugPrint('🎵 [xiaomusic-AutoNext] 检测到歌曲播放完成 [$reason]');
      debugPrint(
        '🎵 [xiaomusic-AutoNext] 当前: $currentSongName, position=$position, duration=$duration',
      );
      debugPrint('🎵 [xiaomusic-AutoNext] 触发自动下一首...');

      // 设置保护标志，防止重复触发
      _xiaomusicAutoNextTriggered = true;

      // 🎯 从 APP 队列获取下一首
      final nextItem = ref.read(playbackQueueProvider.notifier).next();
      if (nextItem != null) {
        debugPrint('🎵 [xiaomusic-AutoNext] 下一首: ${nextItem.displayName}');

        // 使用统一的播放方法
        try {
          await _playNextItem(nextItem);
          debugPrint('✅ [xiaomusic-AutoNext] 自动下一首播放成功');
        } catch (e) {
          debugPrint('❌ [xiaomusic-AutoNext] 自动下一首播放失败: $e');
          // 播放失败，重置标志以便重试
          _xiaomusicAutoNextTriggered = false;
        }
      } else {
        debugPrint('⚠️ [xiaomusic-AutoNext] 队列已到末尾（顺序播放模式）');
      }
    }

    // 🔄 更新上一次轮询的位置（必须在检测之后更新）
    _xiaomusicLastPosition = position;
    _xiaomusicLastDuration = duration;
  }

  /// 🎵 根据歌曲类型自动分发播放方法
  ///
  /// - server 类型：使用 playMusic（xiaomusic 服务器本地歌曲）
  /// - online 类型：使用 playOnlineItem（在线搜索歌曲，需 JS 解析 URL）
  Future<void> _playNextItem(PlaylistItem item) async {
    if (item.isOnline) {
      await playOnlineItem(item);
    } else {
      // server / local 类型：直接用 playMusic
      final deviceId = ref.read(deviceProvider).selectedDeviceId;
      if (deviceId == null) {
        throw Exception('未选择播放设备');
      }
      await playMusic(
        deviceId: deviceId,
        musicName: item.displayName,
        albumCoverUrl: item.coverUrl,
        playlistName: _getCurrentQueueName(),
      );
    }
  }

  /// 🎵 统一的在线歌曲播放方法（懒加载方式）
  ///
  /// 适用于：
  /// - 搜索页面点击播放（xiaomusic懒加载模式、直连模式）
  /// - 自动下一首（xiaomusic模式、直连模式）
  ///
  /// 流程：JS解析URL → playMusic() → 更新封面
  Future<void> playOnlineItem(PlaylistItem item) async {
    debugPrint('🎵 [PlaybackProvider] playOnlineItem: ${item.displayName}');

    try {
      // 检查是否为在线音乐
      if (!item.isOnline) {
        throw Exception('playOnlineItem 仅支持在线音乐');
      }

      if (item.platform == null || item.songId == null) {
        throw Exception('在线音乐缺少 platform 或 songId');
      }

      // 获取设备 ID
      final playbackMode = ref.read(playbackModeProvider);
      String? deviceId;

      if (playbackMode == PlaybackMode.miIoTDirect) {
        // 🎯 直连模式：从 directModeProvider 获取设备 ID
        final directState = ref.read(directModeProvider);
        if (directState is DirectModeAuthenticated) {
          deviceId = directState.playbackDeviceType;
          debugPrint('🎵 [playOnlineItem] 直连模式设备ID: $deviceId');
        }
      } else {
        // xiaomusic 模式：从 deviceProvider 获取设备 ID
        final deviceState = ref.read(deviceProvider);
        deviceId = deviceState.selectedDeviceId;
      }

      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('未选择播放设备');
      }

      // 🎯 关键修复：在 URL 解析开始前就设置保护期和乐观更新
      // 这样定时器的 refreshStatus() 就不会覆盖我们的乐观更新
      _optimisticUpdateProtectionUntil = DateTime.now().add(
        const Duration(seconds: 15),
      );
      debugPrint('🛡️ [playOnlineItem] 设置乐观更新保护期: 15秒（覆盖整个 URL 解析 + 播放过程）');

      // 🎯 立即乐观更新 UI，不等待 URL 解析
      final optimisticMusic = PlayingMusic(
        ret: 'OK',
        curMusic: item.displayName,
        curPlaylist: _getCurrentQueueName(),
        isPlaying: true,
        duration: item.duration ?? 0,
        offset: 0,
      );
      state = state.copyWith(
        currentMusic: optimisticMusic,
        isLoading: false, // 🎯 立即显示播放状态，不转圈
        error: null,
        albumCoverUrl: item.coverUrl,
      );
      debugPrint('✨ [playOnlineItem] 乐观更新UI（无转圈）: ${item.displayName}');

      // 🎯 关键修复：立即停止进度预测定时器 + 重置预测基准
      // 原因：乐观更新已将 offset 设为 0，但旧的定时器仍使用上一首歌的
      // _lastServerOffset 继续递增预测值，导致 URL 解析期间 offset 从 0 涨到 ~5
      // 随后 playMusic 重置回 0，造成 5→0→3 的进度条跳动
      _localProgressTimer?.cancel();
      _localProgressTimer = null;
      _statusRefreshTimer?.cancel();
      _statusRefreshTimer = null;
      _lastServerOffset = 0;
      _lastUpdateTime = DateTime.now();
      _lastProgressUpdate = null;
      debugPrint('⏸️ [playOnlineItem] 已停止进度预测定时器，等待真实播放后重建');

      // 🎯 懒加载：解析 URL
      debugPrint('🎵 [playOnlineItem] 开始解析 URL...');
      final resolveResult = await _resolveUrlWithPerSongFallback(item);
      final url = resolveResult.url;
      final resolvedDuration = resolveResult.duration;

      if (url == null || url.isEmpty) {
        throw Exception('无法解析播放 URL');
      }

      debugPrint(
        '✅ [playOnlineItem] URL 解析成功: ${url.substring(0, url.length > 80 ? 80 : url.length)}...',
      );

      // 🎯 如果解析过程中获取到了 duration（旧歌曲没有存储 duration 的情况），更新乐观状态
      if (resolvedDuration != null &&
          resolvedDuration > 0 &&
          (item.duration == null || item.duration == 0)) {
        debugPrint(
          '🎯 [playOnlineItem] 解析获得 duration=${resolvedDuration}秒，补充到状态',
        );
        final updatedMusic = PlayingMusic(
          ret: 'OK',
          curMusic: item.displayName,
          curPlaylist: _getCurrentQueueName(),
          isPlaying: true,
          duration: resolvedDuration,
          offset: 0,
        );
        state = state.copyWith(currentMusic: updatedMusic);

        // 🎯 同时更新队列中该歌曲的 duration，后续播放就不用再补了
        ref
            .read(playbackQueueProvider.notifier)
            .updateCurrentDuration(resolvedDuration);
      }

      // 🎯 通过 playMusic 播放（自动适配 xiaomusic/直连模式）
      await playMusic(
        deviceId: deviceId,
        musicName: item.displayName,
        url: url,
        albumCoverUrl: item.coverUrl,
        duration: resolvedDuration ?? item.duration, // 🎯 传递 duration，避免策略层丢失
      );

      debugPrint('✅ [playOnlineItem] 播放命令已发送');

      // 🎯 播放命令后做一次非静默刷新，清理 loading 并同步状态
      // 使用保护期避免被旧歌曲状态覆盖
      await Future.delayed(const Duration(milliseconds: 400));
      await refreshStatus(silent: false);

      // 🖼️ 如果没有封面，自动搜索
      if (item.coverUrl == null || item.coverUrl!.isEmpty) {
        debugPrint('🖼️ [playOnlineItem] 封面未缓存，开始搜索');
        _autoFetchAlbumCover(item.displayName)
            .then((_) {
              if (state.albumCoverUrl != null &&
                  state.albumCoverUrl!.isNotEmpty) {
                ref
                    .read(playbackQueueProvider.notifier)
                    .updateCurrentCover(state.albumCoverUrl!);
                debugPrint('✅ [playOnlineItem] 封面已缓存到队列');
              }
            })
            .catchError((e) {
              debugPrint('⚠️ [playOnlineItem] 封面搜索失败: $e');
            });
      }

      debugPrint('✅ [playOnlineItem] 播放流程完成');
    } catch (e, stackTrace) {
      debugPrint('❌ [playOnlineItem] 播放失败: $e');
      debugPrint(
        '❌ [playOnlineItem] 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );
      state = state.copyWith(error: '播放失败: ${e.toString()}', isLoading: false);
      // 🎯 失败时清除保护期
      _optimisticUpdateProtectionUntil = null;
      rethrow;
    }
  }

  /// 🎯 单曲级回退解析：
  /// 先按设置策略的首选平台解析，失败后再跨平台搜同一首并解析
  Future<({String? url, int? duration})> _resolveUrlWithPerSongFallback(
    PlaylistItem item,
  ) async {
    final platform = item.platform;
    final songId = item.songId;
    if (platform == null || platform.isEmpty || songId == null || songId.isEmpty) {
      debugPrint('❌ [单曲回退] 缺少平台或songId: ${item.displayName}');
      return (url: null, duration: null);
    }

    final resolver = ref.read(songResolverServiceProvider);
    final result = await resolver.resolveSong(
      SongResolveRequest(
        title: item.title,
        artist: item.artist,
        album: item.album,
        coverUrl: item.coverUrl,
        duration: item.duration > 0 ? item.duration : null,
        originalPlatform: platform,
        originalSongId: songId,
        quality: '320k',
      ),
    );

    if (result == null) {
      debugPrint('❌ [单曲回退] 所有平台解析失败: ${item.displayName}');
      return (url: null, duration: null);
    }

    return (url: result.url, duration: result.duration ?? item.duration);
  }

  /// 💾 保存直连模式播放状态
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
        await prefs.setString(
          _directModePlaybackCoverKey,
          state.albumCoverUrl!,
        );
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
      if (!_isValidCoverUrl(coverUrl)) {
        debugPrint('⚠️ [PlaybackProvider] 跳过无效封面URL: $coverUrl');
        return;
      }

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
        (_currentStrategy as MiIoTDirectPlaybackStrategy).setAlbumCover(
          coverUrl,
        );
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
    final lower = url.toLowerCase();

    if (lower.contains('proxy?urlb64=') ||
        lower.contains('proxy%3furlb64%3d')) {
      debugPrint('⚠️ [CoverURL] 检测到音频代理URL被误用为封面: $url');
      return false;
    }

    if (RegExp(
      r'\.(mp3|flac|m4a|aac|wav)(\?|$)',
      caseSensitive: false,
    ).hasMatch(url)) {
      debugPrint('⚠️ [CoverURL] 检测到音频直链被误用为封面: $url');
      return false;
    }

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
    // 🎯 优先级1：如果有 APP 端播放队列 → 同步到 QueuePlayMode，不走服务端
    final queueState = ref.read(playbackQueueProvider);
    if (queueState.queue != null && queueState.queue!.items.isNotEmpty) {
      debugPrint('🎵 [switchPlayMode] 检测到 APP 端队列，映射 PlayMode → QueuePlayMode');

      // PlayMode → QueuePlayMode 映射
      final QueuePlayMode queueMode;
      switch (newMode) {
        case PlayMode.loop:
          queueMode = QueuePlayMode.listLoop;
          break;
        case PlayMode.single:
        case PlayMode.singlePlay:
          queueMode = QueuePlayMode.singleLoop;
          break;
        case PlayMode.random:
          queueMode = QueuePlayMode.random;
          break;
        case PlayMode.sequence:
          queueMode = QueuePlayMode.sequence;
          break;
      }

      ref.read(playbackQueueProvider.notifier).setPlayMode(queueMode);
      state = state.copyWith(playMode: newMode);
      debugPrint('✅ [switchPlayMode] 队列播放模式已同步: ${newMode.displayName} → ${queueMode.displayName}');
      return;
    }

    // 🎯 优先级2：无 APP 队列 → 走 xiaomusic 服务端命令
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
    // 🎯 服务端接管播放时，清除 APP 端的旧队列
    final oldQueueState = ref.read(playbackQueueProvider);
    if (oldQueueState.queue != null) {
      debugPrint('🗑️ [播放歌单] 服务端接管，清除 APP 端旧队列');
      ref.read(playbackQueueProvider.notifier).clearQueue();
    }

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
  Future<void> playSongFromPlaylist(
    String songName,
    String playlistName,
  ) async {
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
      state = state.copyWith(isLoading: false, error: '播放失败: ${e.toString()}');
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
          await apiService.executeCommand(did: selectedDid, command: '取消定时关机');
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
    final availableSongs =
        playlist.where((song) => song != currentSong).toList();

    if (availableSongs.isEmpty) {
      // 歌单只有一首歌，重新播放当前歌曲
      debugPrint('🎲 [播放模式] 歌单只有一首歌，重新播放');
      await _replayCurrentSong();
      return;
    }

    // 随机选择
    final random =
        DateTime.now().millisecondsSinceEpoch % availableSongs.length;
    final nextSong = availableSongs[random];

    debugPrint(
      '🎲 [播放模式] 随机选择: $nextSong (歌单共${playlist.length}首，可选${availableSongs.length}首)',
    );

    // 添加当前歌曲到历史记录
    if (currentSong != null && currentSong.isNotEmpty) {
      _addToHistory(currentSong);
    }

    try {
      // 播放选中的歌曲
      await playMusic(deviceId: _currentDeviceId ?? '', musicName: nextSong);
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
      debugPrint(
        '❌ 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );
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
      int? resolvedDuration;

      // 根据来源类型获取播放URL
      if (item.isOnline) {
        // 在线音乐：通过 SongResolverService 解析
        // 遵循 playlistResolveStrategy（如 qqFirst）+ URL 有效性检测（过期/无效 URL 自动跨平台回退）
        if (item.platform == null || item.songId == null) {
          throw Exception('在线音乐缺少platform或songId');
        }
        debugPrint('🎵 [队列播放] 在线音乐，通过 SongResolver 解析: ${item.platform}/${item.songId}');
        final resolveResult = await _resolveUrlWithPerSongFallback(item);
        url = resolveResult.url;
        resolvedDuration = resolveResult.duration;
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
        // 🎯 优先使用 SongResolver 返回的 duration（搜索匹配后可能比 item 自带的更准确）
        duration: resolvedDuration ?? item.duration,
        switchSessionId:
            _currentStrategy is MiIoTDirectPlaybackStrategy
                ? _directSwitchSessionId
                : null,
      );

      debugPrint('✅ [队列播放] 播放命令已发送');

      // 更新UI状态（使用缓存的封面和歌词）
      if (item.coverUrl != null && item.coverUrl!.isNotEmpty) {
        debugPrint('🖼️ [队列播放] 使用缓存的封面图');
        updateAlbumCover(item.coverUrl!);
      } else {
        // 如果队列没有封面，自动搜索并缓存
        debugPrint('🖼️ [队列播放] 封面未缓存，开始搜索');
        _autoFetchAlbumCover(item.displayName)
            .then((coverUrl) {
              // 搜索成功后缓存到队列
              if (state.albumCoverUrl != null &&
                  state.albumCoverUrl!.isNotEmpty) {
                ref
                    .read(playbackQueueProvider.notifier)
                    .updateCurrentCover(state.albumCoverUrl!);
                debugPrint('✅ [队列播放] 封面已缓存到队列');
              }
            })
            .catchError((e) {
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
      debugPrint(
        '❌ [队列播放] 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );
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
        state = state.copyWith(isLoading: false, error: '歌单不存在: $playlistName');
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

      debugPrint(
        '✅ [直连歌单] 找到歌单: ${playlist.name}, 共 ${playlist.songs.length} 首歌',
      );

      // 🎯 播放第一首歌曲
      final firstSong = playlist.songs.first;
      debugPrint('🎵 [直连歌单] 播放第一首: $firstSong');

      // 🎯 检查策略是否已初始化
      if (_currentStrategy == null) {
        debugPrint('❌ [直连歌单] 播放策略未初始化');
        state = state.copyWith(isLoading: false, error: '播放策略未初始化，请检查设备连接');
        return;
      }

      // 🎵 更新当前播放列表信息（用于UI显示）
      state = state.copyWith(currentPlaylistSongs: playlist.songs);

      // 🎯 播放第一首歌曲
      await playMusic(
        deviceId: _currentDeviceId ?? 'direct',
        musicName: firstSong,
      );

      debugPrint('✅ [直连歌单] 歌单播放成功: $playlistName');
      state = state.copyWith(isLoading: false);
    } catch (e, stackTrace) {
      debugPrint('❌ [直连歌单] 播放失败: $e');
      debugPrint(
        '❌ [直连歌单] 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );
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
