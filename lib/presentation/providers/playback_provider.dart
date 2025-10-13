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
import 'dio_provider.dart';
import 'device_provider.dart';
import 'music_library_provider.dart';

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

  // 🔧 缓存的播放状态（待策略初始化后恢复）
  PlayingMusic? _cachedPlayingMusic;
  String? _cachedMusicUrl;
  String? _cachedCoverUrl;
  int? _cachedOffset;

  // 🎵 播放策略（本地播放或远程控制）
  PlaybackStrategy? _currentStrategy;
  String? _currentDeviceId; // 当前使用的设备ID

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
    _currentStrategy?.dispose();
    _albumCoverService?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      debugPrint('🔧 [PlaybackProvider] 开始初始化');

      // 1. 加载设备列表
      await ref.read(deviceProvider.notifier).loadDevices();

      // 2. 获取当前选中的设备并初始化策略
      final deviceState = ref.read(deviceProvider);
      debugPrint('🔧 [PlaybackProvider] 设备列表加载完成: ${deviceState.devices.length} 个设备');
      debugPrint('🔧 [PlaybackProvider] 当前选中设备ID: ${deviceState.selectedDeviceId}');

      if (deviceState.selectedDeviceId != null &&
          deviceState.devices.isNotEmpty) {
        debugPrint('🔧 [PlaybackProvider] 开始初始化播放策略');
        await _switchStrategy(
          deviceState.selectedDeviceId!,
          deviceState.devices,
        );
      } else {
        debugPrint('⚠️ [PlaybackProvider] 无设备或未选中设备，跳过策略初始化');
      }

      // 3. 刷新播放状态（仅远程模式需要）
      if (_currentStrategy != null && !_currentStrategy!.isLocalMode) {
        await refreshStatus();
      }

      debugPrint('✅ [PlaybackProvider] 初始化完成');
    } catch (e) {
      // 初始化失败，设置错误状态但不抛出异常
      debugPrint('❌ [PlaybackProvider] 初始化失败: $e');
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
    ref.listen<DeviceState>(deviceProvider, (previous, next) {
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
          '🎵 [PlaybackProvider] 检测到设备切换: $_currentDeviceId -> $newDeviceId',
        );
        _switchStrategy(newDeviceId, next.devices);
      }
    });
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

      state = state.copyWith(
        currentMusic: currentMusic,
        volume: volume,
        error: null,
        isLoading: silent ? state.isLoading : false,
        hasLoaded: true,
        albumCoverUrl: isSongChanged ? null : state.albumCoverUrl,
        isFavorite: isSongChanged ? false : state.isFavorite,
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

      // 🔧 只有远程模式需要启动进度定时器（本地模式通过statusStream自动更新）
      if (_currentStrategy != null && !_currentStrategy!.isLocalMode) {
        _startProgressTimer(currentMusic?.isPlaying ?? false);
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

      // 🔧 本地模式通过statusStream自动更新，不需要定时器
      if (!_currentStrategy!.isLocalMode) {
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

      // 🔧 本地模式通过statusStream自动更新，不需要定时器
      if (!_currentStrategy!.isLocalMode) {
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

        // 🔧 远程模式需要更新进度计时器
        if (!_currentStrategy!.isLocalMode) {
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
      return;
    }

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('🎵 执行上一首命令');

      await _currentStrategy!.previous();

      // 等待命令执行后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));

      // 🔄 远程模式需要刷新状态，本地模式会自动更新
      if (!_currentStrategy!.isLocalMode) {
        await refreshStatus();
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
      return;
    }

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('🎵 执行下一首命令');

      await _currentStrategy!.next();

      // 等待命令执行后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));

      // 🔄 远程模式需要刷新状态，本地模式会自动更新
      if (!_currentStrategy!.isLocalMode) {
        await refreshStatus();
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
      debugPrint('❌ [PlaybackProvider] 播放策略未初始化');
      return;
    }

    try {
      await _currentStrategy!.setVolume(volume);
      state = state.copyWith(volume: volume);
    } catch (e) {
      state = state.copyWith(error: e.toString());
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
      state = state.copyWith(isLoading: true, error: null);
      debugPrint('🎵 [PlaybackProvider] 开始播放音乐: $musicName, 设备ID: $deviceId');

      // 🖼️ 切歌时重置防抖标记，允许新歌曲搜索封面
      _lastCoverSearchSong = null;

      // 🎵 如果是本地播放模式且提供了播放列表，设置到策略中
      if (_currentStrategy != null &&
          _currentStrategy!.isLocalMode &&
          playlist != null &&
          playlist.isNotEmpty) {
        debugPrint('🎵 [PlaybackProvider] 设置本地播放列表: ${playlist.length} 首歌曲');
        final localStrategy = _currentStrategy as LocalPlaybackStrategy;

        // 如果没有指定索引，尝试找到当前播放歌曲的索引
        int playIndex = startIndex ?? 0;
        if (musicName != null && musicName.isNotEmpty && startIndex == null) {
          final index = playlist.indexWhere((m) => m.name == musicName);
          if (index >= 0) {
            playIndex = index;
          }
        }

        localStrategy.setPlaylist(playlist, startIndex: playIndex);
        debugPrint('🎵 [PlaybackProvider] 播放列表已设置，开始索引: $playIndex');
      }

      // 使用策略播放
      await _currentStrategy!.playMusic(musicName: musicName ?? '', url: url);

      debugPrint('✅ [PlaybackProvider] 播放请求成功');

      // 🖼️ 处理封面图（4种情况）
      if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
        // 情况1&3: 搜索音乐（本地/远程）- 直接使用搜索结果的封面图
        debugPrint('🖼️ [PlaybackProvider] 使用搜索结果的封面图: $albumCoverUrl');
        updateAlbumCover(albumCoverUrl);
      } else if (musicName != null && musicName.isNotEmpty && url == null) {
        // 情况2&4: 服务器音乐（本地/远程）- 需要自动搜索封面
        debugPrint('🖼️ [PlaybackProvider] 服务器音乐，自动搜索封面: $musicName');
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

  void updateAlbumCover(String coverUrl) {
    if (coverUrl.isNotEmpty) {
      state = state.copyWith(albumCoverUrl: coverUrl);
      print('[Playback] 🖼️  封面图已更新: $coverUrl');

      // 🎵 如果是本地播放模式，同时更新通知栏封面
      if (_currentStrategy is LocalPlaybackStrategy) {
        (_currentStrategy as LocalPlaybackStrategy).setAlbumCover(coverUrl);
        (_currentStrategy as LocalPlaybackStrategy).refreshNotification();
      }
      // 🎵 如果是远程播放模式，也要更新通知栏封面
      else if (_currentStrategy is RemotePlaybackStrategy) {
        (_currentStrategy as RemotePlaybackStrategy).updateAlbumCover(coverUrl);
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

  /// 🖼️ 自动搜索并获取歌曲封面图（新版：支持上传到服务器）
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

      // 🔧 初始化 AlbumCoverService（如果未初始化）
      if (_albumCoverService == null) {
        final apiService = ref.read(apiServiceProvider);
        if (apiService == null) {
          debugPrint('❌ [AutoCover] API服务未初始化，无法获取封面');
          return;
        }

        debugPrint('🔧 [AutoCover] 初始化 AlbumCoverService');
        final nativeSearch = ref.read(nativeMusicSearchServiceProvider);
        _albumCoverService = AlbumCoverService(
          musicApi: apiService,
          nativeSearch: nativeSearch,
        );
      }

      // 获取登录地址（用于URL替换）
      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) return;
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

  /// ⭐ 加入收藏
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

  /// ⭐💔 切换收藏状态
  Future<void> toggleFavorites() async {
    if (state.isFavorite) {
      await removeFromFavorites();
    } else {
      await addToFavorites();
    }
  }

  /// ⏰ 设置定时关机
  Future<void> setTimer() async {
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

    // 循环增加定时：0 -> 10 -> 15 -> 20 -> ... -> 60 -> 0
    int nextMinutes;
    if (state.timerMinutes == 0) {
      nextMinutes = 10; // 初始为 10 分钟
    } else if (state.timerMinutes >= 60) {
      nextMinutes = 0; // 达到 60 分钟后归零（取消定时）
    } else {
      nextMinutes = state.timerMinutes + 5; // 每次增加 5 分钟
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

  /// ⏰ 快速取消定时（长按）
  void cancelTimer() {
    debugPrint('⏰ 快速取消定时关机');
    state = state.copyWith(timerMinutes: 0);
  }
}

final playbackProvider = StateNotifierProvider<PlaybackNotifier, PlaybackState>(
  (ref) {
    return PlaybackNotifier(ref);
  },
);
