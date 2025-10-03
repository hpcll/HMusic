import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/playing_music.dart';
import '../../data/models/online_music_result.dart';
import 'dio_provider.dart';
import 'device_provider.dart';

enum PlayMode {
  sequence, // 顺序播放
  loop, // 循环播放
  random, // 随机播放
  single, // 单曲循环
}

extension PlayModeExtension on PlayMode {
  String get displayName {
    switch (this) {
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.loop:
        return '循环播放';
      case PlayMode.random:
        return '随机播放';
      case PlayMode.single:
        return '单曲循环';
    }
  }

  String get command {
    switch (this) {
      case PlayMode.sequence:
        return 'sequence';
      case PlayMode.loop:
        return 'loop';
      case PlayMode.random:
        return 'random';
      case PlayMode.single:
        return 'single';
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

  const PlaybackState({
    this.currentMusic,
    this.volume = 0, // Initial UI shows volume at 0 before server data arrives
    this.isLoading = false,
    this.error,
    this.playMode = PlayMode.sequence,
    this.hasLoaded = false,
    this.albumCoverUrl,
  });

  PlaybackState copyWith({
    PlayingMusic? currentMusic,
    int? volume,
    bool? isLoading,
    String? error,
    PlayMode? playMode,
    bool? hasLoaded,
    String? albumCoverUrl,
  }) {
    return PlaybackState(
      currentMusic: currentMusic ?? this.currentMusic,
      volume: volume ?? this.volume,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      playMode: playMode ?? this.playMode,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      albumCoverUrl: albumCoverUrl ?? this.albumCoverUrl,
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

  PlaybackNotifier(this.ref)
    : super(const PlaybackState(isLoading: false, hasLoaded: false)) {
    // 禁用自动初始化，避免在未登录时进行网络请求
    // 需要用户手动触发初始化
    debugPrint('PlaybackProvider: 自动初始化已禁用，等待用户手动触发');
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    _localProgressTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      await ref.read(deviceProvider.notifier).loadDevices();
      await refreshStatus();
    } catch (e) {
      // 初始化失败，设置错误状态但不抛出异常
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

  // 设备加载由 deviceProvider 负责

  Future<void> refreshStatus({bool silent = false}) async {
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

      // 直接使用播放状态API获取完整信息
      final currentPlayingResponse = await apiService.getCurrentPlaying(
        did: selectedDid,
      );
      print('🎵 播放状态API响应: $currentPlayingResponse');

      PlayingMusic? currentMusic;

      if (currentPlayingResponse['ret'] == 'OK') {
        currentMusic = PlayingMusic.fromJson(currentPlayingResponse);
        print(
          '🎵 解析后的播放状态: 音乐=${currentMusic.curMusic}, 播放中=${currentMusic.isPlaying}, 进度=${currentMusic.offset}/${currentMusic.duration}',
        );
      } else {
        print('🎵 API返回错误或无播放内容');
      }

      final volumeResponse = await apiService.getVolume(did: selectedDid);
      print('🎵 音量响应: $volumeResponse');

      final volume = volumeResponse['volume'] as int? ?? state.volume;

      print('🎵 最终播放状态: ${currentMusic?.curMusic ?? "无"}');
      print('🎵 当前音量: $volume');

      // 智能进度同步校准机制
      bool needsRecalibration = false;
      bool useSmoothing = false;

      if (state.currentMusic != null && currentMusic != null) {
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

      state = state.copyWith(
        currentMusic: currentMusic,
        volume: volume,
        error: null,
        isLoading: silent ? state.isLoading : false,
        hasLoaded: true,
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

      // 如果音乐正在播放，启动自动刷新进度
      _startProgressTimer(currentMusic?.isPlaying ?? false);
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
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    // 🎯 乐观更新：先更新本地UI状态
    if (state.currentMusic != null) {
      final updatedMusic = PlayingMusic(
        curMusic: state.currentMusic!.curMusic,
        curPlaylist: state.currentMusic!.curPlaylist,
        isPlaying: false, // 立即显示为暂停状态
        offset: state.currentMusic!.offset,
        duration: state.currentMusic!.duration,
        ret: '',
      );
      state = state.copyWith(currentMusic: updatedMusic);
      _startProgressTimer(false); // 停止本地进度更新
    }

    try {
      print('🎵 执行暂停命令');
      await apiService.pauseMusic(did: selectedDid);

      // 延迟同步真实状态
      Future.delayed(const Duration(milliseconds: 1500), () {
        refreshStatus(silent: true);
      });
    } catch (e) {
      print('🎵 暂停失败: $e');
      // 如果请求失败，恢复原来的状态
      refreshStatus(silent: true);
      state = state.copyWith(error: '暂停失败: ${e.toString()}');
    }
  }

  Future<void> resumeMusic() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

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
      _lastServerOffset = state.currentMusic!.offset; // 保存当前进度作为基准
      _lastUpdateTime = DateTime.now(); // 重置本地进度计时
      _startProgressTimer(true); // 开始本地进度更新
    }

    try {
      print('🎵 执行播放命令');
      await apiService.resumeMusic(did: selectedDid);

      // 延迟同步真实状态
      Future.delayed(const Duration(milliseconds: 1500), () {
        refreshStatus(silent: true);
      });
    } catch (e) {
      print('🎵 播放失败: $e');
      // 如果请求失败，恢复原来的状态
      refreshStatus(silent: true);
      state = state.copyWith(error: '播放失败: ${e.toString()}');
    }
  }

  Future<void> playPause() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      final isPlaying = state.currentMusic?.isPlaying ?? false;
      print('🎵 执行播放控制命令: ${isPlaying ? "暂停" : "播放歌曲"}');

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

        // 更新本地进度计时器
        _startProgressTimer(!isPlaying);
        if (!isPlaying) {
          _lastServerOffset = state.currentMusic!.offset;
          _lastUpdateTime = DateTime.now();
        }
      }

      // 异步执行实际命令
      if (isPlaying) {
        await apiService.pauseMusic(did: selectedDid);
      } else {
        await apiService.resumeMusic(did: selectedDid);
      }

      // 延迟同步真实状态，但不影响UI响应
      Future.delayed(
        const Duration(milliseconds: 1500),
        () => refreshStatus(silent: true),
      );
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
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      state = state.copyWith(isLoading: true);

      print('🎵 执行上一首命令');

      await apiService.executeCommand(
        did: selectedDid,
        command: '上一首', // 使用中文命令
      );

      // 等待命令执行后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 上一首失败: $e');
      state = state.copyWith(isLoading: false, error: '上一首失败: ${e.toString()}');
    }
  }

  Future<void> next() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      state = state.copyWith(isLoading: true);

      print('🎵 执行下一首命令');

      await apiService.executeCommand(
        did: selectedDid,
        command: '下一首', // 使用中文命令
      );

      // 等待命令执行后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 下一首失败: $e');
      state = state.copyWith(isLoading: false, error: '下一首失败: ${e.toString()}');
    }
  }

  Future<void> setVolume(int volume) async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      await apiService.setVolume(did: selectedDid, volume: volume);

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
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;
    try {
      await apiService.seek(did: selectedDid, seconds: seconds);
      await Future.delayed(const Duration(milliseconds: 500));
      await refreshStatus(silent: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> playMusic({
    required String deviceId,
    String? musicName,
    String? searchKey,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      state = state.copyWith(error: 'API 服务未初始化');
      return;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      print('🎵 开始播放音乐: $musicName, 设备ID: $deviceId');

      await apiService.playMusic(
        did: deviceId,
        musicName: musicName,
        searchKey: searchKey,
      );

      print('🎵 播放请求成功');

      // 等待一下让播放状态更新
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 播放失败: $e');
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

  Future<void> switchPlayMode() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    // 循环切换播放模式
    final currentMode = state.playMode;
    final nextMode =
        PlayMode.values[(currentMode.index + 1) % PlayMode.values.length];

    try {
      state = state.copyWith(isLoading: true);

      // 使用服务器配置中的正确命令名称
      String command;
      switch (nextMode) {
        case PlayMode.sequence:
          command = 'set_play_type_seq'; // 顺序播放
          break;
        case PlayMode.loop:
          command = 'set_play_type_all'; // 全部循环
          break;
        case PlayMode.single:
          command = 'set_play_type_one'; // 单曲循环
          break;
        case PlayMode.random:
          command = 'set_play_type_rnd'; // 随机播放
          break;
      }

      print('🎵 切换播放模式: ${nextMode.displayName} (命令: $command)');

      await apiService.executeCommand(did: selectedDid, command: command);

      state = state.copyWith(playMode: nextMode, isLoading: false);

      // 延迟刷新状态以确认模式切换
      Future.delayed(
        const Duration(milliseconds: 500),
        () => refreshStatus(silent: true),
      );
    } catch (e) {
      print('🎵 播放模式切换失败: $e');
      state = state.copyWith(
        isLoading: false,
        error: '播放模式切换失败: ${e.toString()}',
      );
    }
  }

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

  /// 更新专辑封面图 URL
  void updateAlbumCover(String coverUrl) {
    if (coverUrl.isNotEmpty) {
      state = state.copyWith(albumCoverUrl: coverUrl);
      print('[Playback] 🖼️  封面图已更新: $coverUrl');
    }
  }
}

final playbackProvider = StateNotifierProvider<PlaybackNotifier, PlaybackState>(
  (ref) {
    return PlaybackNotifier(ref);
  },
);
