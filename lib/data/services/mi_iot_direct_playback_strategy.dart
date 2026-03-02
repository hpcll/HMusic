import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'; // 🎯 添加导入用于 AppLifecycleListener
import 'package:audio_service/audio_service.dart'; // 🎯 添加导入用于 MediaControl 和 AudioProcessingState
import 'package:shared_preferences/shared_preferences.dart'; // 🎯 新增：用于状态持久化
import '../models/playing_music.dart';
import '../models/music.dart';
import 'playback_strategy.dart';
import 'mi_iot_service.dart';
import 'audio_handler_service.dart';
import 'mi_hardware_detector.dart';
import 'mi_play_mode.dart';

/// 小米IoT直连播放策略
/// 不依赖xiaomusic服务端，直接调用小米云端API控制小爱音箱
/// 实现 PlaybackStrategy 接口，与现有架构完美集成
class MiIoTDirectPlaybackStrategy implements PlaybackStrategy {
  final MiIoTService _miService;
  final String _deviceId;
  final String _deviceName;
  AudioHandlerService? _audioHandler;

  // 状态变化回调
  Function(int? switchSessionId)? onStatusChanged;

  @override
  String? get lastAudioId => null;

  // 获取音乐URL的回调（由PlaybackProvider设置）
  Future<String?> Function(String musicName)? onGetMusicUrl;

  // 🎯 歌曲播放完成回调（用于自动下一首）
  Function()? onSongComplete;

  // 当前播放状态缓存
  PlayingMusic? _currentPlayingMusic;
  String? _albumCoverUrl;
  String? _currentMusicUrl; // 🎯 保存当前播放 URL（用于 OH2P 暂停后恢复播放）

  // 🎵 播放列表管理（APP端维护）
  List<Music> _playlist = [];
  int _currentIndex = 0;

  // 🔄 状态轮询定时器
  Timer? _statusTimer;
  int _statusPollIntervalSeconds = 3;
  bool _isWarmupPolling = false;
  DateTime? _warmupDeadline;
  String? _warmupSongName;
  int? _activeSwitchSessionId;

  // 🔇 切歌准备期：从 prepareSongSwitch 到 playMusic finally，丢弃旧轮询
  bool _isSongSwitchPending = false;

  // 🎯 设备硬件信息
  String? _hardware;

  // 🎯 APP生命周期状态（用于控制后台轮询）
  bool _isAppInBackground = false;

  // 🎯 APP生命周期监听器
  AppLifecycleListener? _lifecycleListener;

  // 🎯 缓存有效的 audio_id 和 duration（用于修复暂停时 duration 突变的问题）
  // 小米 IoT API 在暂停状态下返回的 duration 可能是异常值（如缓冲区大小）
  String? _lastValidAudioId;
  int _lastValidDuration = 0;

  // 🎯 命令状态保护窗口（用于修复设备状态API不可靠的问题）
  // 发送 play/pause 命令后，在保护窗口内信任本地状态，忽略设备返回的矛盾状态
  // 原因：部分设备（如OH2P）的 player_get_play_status 始终返回 status=1
  DateTime? _playingStateProtectedUntil;  // 保护"播放中"状态
  DateTime? _pauseStateProtectedUntil;    // 保护"已暂停"状态

  // 🎯 Seek 保护窗口：seek 后短期内忽略比 seek 目标小的进度值
  // 原因：设备 seek 后第一次轮询可能返回旧的 position（设备尚未完成 seek）
  DateTime? _seekProtectedUntil;
  int? _seekTargetPosition; // seek 目标位置（秒）

  // 🎯 本地时间预测进度（用于 detail=null 的设备，如OH2P）
  // 原理与 xiaomusic 的 time.time() - _start_time 相同：
  // 播放开始时记录时间戳，根据已播放时间计算 offset
  DateTime? _localPlayStartTime;         // 当前歌曲开始播放的时间
  Duration _localAccumulatedPause = Duration.zero; // 累计暂停时长
  DateTime? _localPauseStartTime;        // 当前暂停开始的时间（null=非暂停状态）

  // 🔬 实验性 API 标志：避免重复调用
  bool _hasTriedAltApis = false;

  // 🎯 自动下一首保护：防止重复触发
  bool _isAutoNextTriggered = false;
  String? _lastCompletedAudioId;

  // 🎯 位置跳跃检测：记录上一次轮询的 position 和 duration
  int _lastPolledPosition = 0;
  int _lastPolledDuration = 0;

  // 🎯 方案C：APP端倒计时定时器（备用自动下一首触发）
  // 当 API 返回的 play_song_detail 为空或 duration=0 时，使用此定时器作为备用
  Timer? _backupAutoNextTimer;
  String? _backupTimerMusicName; // 定时器对应的歌曲名，用于验证

  // 🎯 持久化存储的Key
  static const String _keyLastMusicName = 'direct_mode_last_music_name';
  static const String _keyLastPlaylist = 'direct_mode_last_playlist';
  static const String _keyLastDuration = 'direct_mode_last_duration';
  static const String _keyLastAlbumCover = 'direct_mode_last_album_cover';

  MiIoTDirectPlaybackStrategy({
    required MiIoTService miService,
    required String deviceId,
    String? deviceName,
    AudioHandlerService? audioHandler,
    Function(int? switchSessionId)?
    onStatusChanged, // 🔧 在构造函数中接收回调，确保轮询启动前已设置
    Future<String?> Function(String musicName)? onGetMusicUrl, // 🔧 在构造函数中接收回调
    Function()? onSongComplete, // 🎯 歌曲播放完成回调（自动下一首）
    bool skipRestore = false, // 🎯 模式切换时跳过状态恢复，避免显示错误的歌曲
  })  : _miService = miService,
        _deviceId = deviceId,
        _deviceName = deviceName ?? '小爱音箱',
        _audioHandler = audioHandler,
        onStatusChanged = onStatusChanged, // 🔧 立即设置回调，避免 NULL 问题
        onGetMusicUrl = onGetMusicUrl,     // 🔧 立即设置回调
        onSongComplete = onSongComplete {  // 🎯 设置播放完成回调
    _initializeAudioHandler();
    _initializeHardwareInfo(); // 🎯 初始化硬件信息
    // 🎯 只有非模式切换时才恢复状态（APP 首次启动时恢复，模式切换时跳过）
    if (!skipRestore) {
      _restoreLastPlayingState(); // 🎯 恢复上次播放状态（在轮询之前）
    } else {
      debugPrint('⏭️ [MiIoTDirect] 模式切换，跳过状态恢复，等待轮询获取真实状态');
    }
    _startStatusPolling(); // 🔄 启动状态轮询

    // 🎯 注册APP生命周期监听器（使用 AppLifecycleListener，更简洁）
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onAppLifecycleStateChanged,
    );
    debugPrint('🔧 [MiIoTDirect] 已注册APP生命周期监听器');
  }

  /// 🎯 APP生命周期状态变化回调
  void _onAppLifecycleStateChanged(AppLifecycleState state) {
    debugPrint('🔄 [MiIoTDirect] APP生命周期变化: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // APP回到前台：恢复轮询
        _isAppInBackground = false;
        debugPrint('✅ [MiIoTDirect] APP回到前台，轮询已恢复');

        // 🎯 关键修复：APP回到前台时，立即轮询一次同步真实状态
        // 避免UI显示的状态与音箱真实状态不一致
        debugPrint('🔄 [MiIoTDirect] 立即轮询一次，同步真实状态');
        _pollPlayStatus().then((_) {
          debugPrint('✅ [MiIoTDirect] 前台状态同步完成');
        }).catchError((e) {
          debugPrint('⚠️ [MiIoTDirect] 前台状态同步失败: $e');
        });
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // APP进入后台：暂停轮询
        _isAppInBackground = true;
        debugPrint('⏸️ [MiIoTDirect] APP进入后台，暂停轮询（避免网络错误）');
        break;
    }
  }

  /// 🎯 初始化设备硬件信息
  Future<void> _initializeHardwareInfo() async {
    try {
      // 获取设备列表并找到当前设备
      final devices = await _miService.getDevices();
      final device = devices.firstWhere(
        (d) => d.deviceId == _deviceId || d.did == _deviceId,
        orElse: () => MiDevice(deviceId: '', did: '', name: '', hardware: ''),
      );

      if (device.hardware.isNotEmpty) {
        _hardware = device.hardware;
        final hardwareDesc = MiHardwareDetector.getHardwareDescription(_hardware!);
        final playMethod = MiHardwareDetector.getRecommendedPlayMethod(_hardware!);
        debugPrint('📱 [MiIoTDirect] 设备硬件: ${_hardware!} ($hardwareDesc)');
        debugPrint('🎵 [MiIoTDirect] 推荐播放方式: $playMethod');
      }
    } catch (e) {
      debugPrint('⚠️ [MiIoTDirect] 初始化硬件信息失败: $e');
    }
  }

  /// 🎯 恢复上次播放状态（APP重启时调用）
  Future<void> _restoreLastPlayingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final lastMusicName = prefs.getString(_keyLastMusicName);
      final lastPlaylist = prefs.getString(_keyLastPlaylist) ?? '直连播放';
      final lastDuration = prefs.getInt(_keyLastDuration) ?? 0;
      final lastAlbumCover = prefs.getString(_keyLastAlbumCover);

      if (lastMusicName != null && lastMusicName.isNotEmpty) {
        // 恢复播放状态（播放状态设为false，因为重启后音箱可能已停止）
        _currentPlayingMusic = PlayingMusic(
          ret: 'OK',
          curMusic: lastMusicName,
          curPlaylist: lastPlaylist,
          isPlaying: false, // 🎯 重启后默认为暂停，等轮询更新真实状态
          duration: lastDuration,
          offset: 0, // 进度由轮询更新
        );

        _albumCoverUrl = lastAlbumCover;

        // 🎯 同时初始化 duration 缓存，避免轮询时误判为异常值
        if (lastDuration > 10) {
          _lastValidDuration = lastDuration;
        }

        debugPrint('✅ [MiIoTDirect] 恢复上次播放状态: $lastMusicName');
        debugPrint('📀 [MiIoTDirect] 歌单: $lastPlaylist, 时长: $lastDuration秒, 封面: ${lastAlbumCover ?? "无"}');

        // 🎯 立即更新通知栏显示恢复的歌曲信息
        if (_audioHandler != null) {
          final parts = lastMusicName.split(' - ');
          final title = parts.isNotEmpty ? parts[0] : lastMusicName;
          final artist = parts.length > 1 ? parts[1] : _deviceName;

          _audioHandler!.setMediaItem(
            title: title,
            artist: artist,
            album: lastPlaylist,
            artUri: lastAlbumCover,
            duration: lastDuration > 0 ? Duration(seconds: lastDuration) : null,
          );

          _audioHandler!.playbackState.add(_audioHandler!.playbackState.value.copyWith(
            playing: false, // 重启后默认显示播放按钮
            processingState: AudioProcessingState.ready,
            updatePosition: Duration.zero,
            controls: [
              MediaControl.skipToPrevious,
              MediaControl.play,
              MediaControl.skipToNext,
            ],
          ));

          debugPrint('🔔 [MiIoTDirect] 已将恢复的状态更新到通知栏');
        }

        // 通知状态变化（让UI立即显示恢复的歌曲）
        onStatusChanged?.call(_activeSwitchSessionId);
      } else {
        debugPrint('ℹ️ [MiIoTDirect] 没有保存的播放状态，跳过恢复');
      }
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 恢复播放状态失败: $e');
    }
  }

  /// 🎯 保存当前播放状态（播放新歌曲时调用）
  Future<void> _saveCurrentPlayingState() async {
    if (_currentPlayingMusic == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_keyLastMusicName, _currentPlayingMusic!.curMusic);
      await prefs.setString(_keyLastPlaylist, _currentPlayingMusic!.curPlaylist);
      await prefs.setInt(_keyLastDuration, _currentPlayingMusic!.duration);

      if (_albumCoverUrl != null) {
        await prefs.setString(_keyLastAlbumCover, _albumCoverUrl!);
      } else {
        await prefs.remove(_keyLastAlbumCover);
      }

      debugPrint('💾 [MiIoTDirect] 已保存播放状态: ${_currentPlayingMusic!.curMusic}');
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 保存播放状态失败: $e');
    }
  }

  /// 🔄 启动状态轮询
  void _startStatusPolling({int intervalSeconds = 3}) {
    _statusPollIntervalSeconds = intervalSeconds;
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _pollPlayStatus();
    });
    debugPrint('⏰ [MiIoTDirect] 启动状态轮询（${intervalSeconds}s）');
  }

  /// 🔇 通知策略层即将切歌：直接停止轮询定时器 + 标记 pending
  /// 停止定时器 → URL 解析期间不会有新轮询产生（根源解决）
  /// pending 标记 → 仅用于拦截停止定时器前已在飞行中的最后一个 HTTP 请求
  /// playMusic 的 finally 块统一清除 pending 并启动新的 warmup 轮询
  void prepareSongSwitch() {
    _statusTimer?.cancel();
    _statusTimer = null;
    _isSongSwitchPending = true;
    debugPrint('🔇 [MiIoTDirect] 切歌准备：已停止轮询定时器');
  }

  /// 🔇 取消切歌准备期（用于失败回滚：URL 解析或播放失败时立即恢复轮询）
  void cancelSongSwitchPending() {
    if (_isSongSwitchPending) {
      _isSongSwitchPending = false;
      debugPrint('🔇 [MiIoTDirect] 切歌准备已取消，恢复轮询');
      // prepareSongSwitch 停了定时器，失败回滚时必须重启
      _startStatusPolling(intervalSeconds: _statusPollIntervalSeconds);
    }
  }

  void _enterWarmupPolling(String songName) {
    _isWarmupPolling = true;
    _warmupDeadline = DateTime.now().add(const Duration(seconds: 8));
    _warmupSongName = songName;
    // 只标记 warmup 状态，轮询启动统一放在 playMusic finally 阶段
    debugPrint('🔥 [MiIoTDirect] 进入切歌 warmup（由 finally 统一启动轮询）: $songName');
  }

  void _exitWarmupPolling(String reason) {
    if (!_isWarmupPolling) return;
    _isWarmupPolling = false;
    _warmupDeadline = null;
    _warmupSongName = null;
    _startStatusPolling(intervalSeconds: 3);
    debugPrint('✅ [MiIoTDirect] 退出切歌 warmup: $reason');
  }

  /// 🎯 本地时间预测：计算当前播放 offset（秒）
  /// 原理：从播放开始时间戳推算已播放时间，扣除累计暂停时长
  /// 与 xiaomusic 的 time.time() - self._start_time 实现相同逻辑
  int _getLocalPredictedOffset() {
    if (_localPlayStartTime == null) return 0;

    final now = DateTime.now();
    var elapsed = now.difference(_localPlayStartTime!);

    // 扣除累计暂停时长
    elapsed -= _localAccumulatedPause;

    // 扣除当前正在进行的暂停时长
    if (_localPauseStartTime != null) {
      elapsed -= now.difference(_localPauseStartTime!);
    }

    final maxDuration = _currentPlayingMusic?.duration ?? 999999;
    return elapsed.inSeconds.clamp(0, maxDuration);
  }

  /// 🎯 用服务器返回的真实进度校准本地计时器
  /// 当 detail!=null（如L05B）时，用服务器的 position 反推 _localPlayStartTime
  void _syncLocalTimerWithServer(int serverOffsetSeconds) {
    if (_localPlayStartTime == null) return;

    final now = DateTime.now();
    // 反推：startTime = now - serverOffset - accumulatedPause
    var totalPaused = _localAccumulatedPause;
    if (_localPauseStartTime != null) {
      totalPaused += now.difference(_localPauseStartTime!);
    }
    _localPlayStartTime = now.subtract(
      Duration(seconds: serverOffsetSeconds) + totalPaused,
    );
  }

  /// 🔄 轮询播放状态
  Future<void> _pollPlayStatus() async {
    // 🎯 后台时跳过轮询，避免网络访问被系统限制
    if (_isAppInBackground) {
      debugPrint('⏭️ [MiIoTDirect] APP在后台，跳过本次轮询');
      return;
    }

    // 🔇 切歌准备期：定时器已停，但可能有在飞行中的旧 HTTP 请求
    if (_isSongSwitchPending) {
      debugPrint('⏭️ [MiIoTDirect] 切歌准备中，跳过轮询');
      return;
    }

    try {
      // 🎯 Session 快照：慢网下旧 HTTP 可能在 finally 清除 pending 之后才返回
      // 此时 pending 已 false，但 session 已变 → 快照不匹配 → 丢弃
      final sessionSnapshot = _activeSwitchSessionId;

      final status = await _miService.getPlayStatus(_deviceId);

      // 🔇 二次检查（双重防线）：
      // 防线1: pending — 覆盖 URL 解析阶段（pending=true，定时器已停）
      // 防线2: session 快照 — 覆盖慢网长尾：旧 HTTP 在 finally 清 pending 后才返回
      if (_isSongSwitchPending) {
        debugPrint('⏭️ [MiIoTDirect] 轮询返回时已处于切歌准备期，丢弃结果');
        return;
      }
      if (_activeSwitchSessionId != sessionSnapshot) {
        debugPrint('⏭️ [MiIoTDirect] 轮询期间 session 已变更 ($sessionSnapshot→$_activeSwitchSessionId)，丢弃旧结果');
        return;
      }

      if (status != null) {
        // 解析状态
        var isPlaying = status['status'] == 1;
        final detail = status['play_song_detail'] as Map<String, dynamic>?;

        // 🎯 检查命令状态保护窗口
        // 部分设备（如OH2P）的 player_get_play_status 始终返回 status=1，
        // 即使已暂停也报告"播放中"，必须信任本地命令状态

        // 播放保护：playMusic()/play() 成功后，忽略设备返回的"暂停"
        if (_playingStateProtectedUntil != null) {
          if (DateTime.now().isBefore(_playingStateProtectedUntil!)) {
            if (!isPlaying && _currentPlayingMusic?.isPlaying == true) {
              debugPrint('🛡️ [MiIoTDirect] 播放保护窗口内，忽略设备"暂停"，保持为"播放"');
              isPlaying = true;
            }
          } else {
            _playingStateProtectedUntil = null;
            debugPrint('🛡️ [MiIoTDirect] 播放保护窗口已过期');
          }
        }

        // 暂停保护：pause() 成功后，忽略设备返回的"播放"
        if (_pauseStateProtectedUntil != null) {
          if (DateTime.now().isBefore(_pauseStateProtectedUntil!)) {
            if (isPlaying && _currentPlayingMusic?.isPlaying == false) {
              debugPrint('🛡️ [MiIoTDirect] 暂停保护窗口内，忽略设备"播放"，保持为"暂停"');
              isPlaying = false;
            }
          } else {
            _pauseStateProtectedUntil = null;
            debugPrint('🛡️ [MiIoTDirect] 暂停保护窗口已过期');
          }
        }

        debugPrint('🔄 [MiIoTDirect] 轮询状态: status=$isPlaying, detail=$detail');

        if (detail != null) {
          final title = detail['title'] as String?;
          final audioId = detail['audio_id'] as String?; // 🎯 获取 audio_id 用于判断是否同一首歌
          final durationMs = detail['duration'] as int? ?? 0; // 毫秒
          final positionMs = detail['position'] as int? ?? 0; // 毫秒

          // 🎯 将毫秒转换为秒（与 xiaomusic 模式保持一致）
          int duration = (durationMs / 1000).round();
          final position = (positionMs / 1000).round();

          // 🎯 修复：检测并处理暂停状态下 duration 异常突变的问题
          // 小米 IoT API 在暂停时可能返回异常小的 duration（如缓冲区大小而非歌曲总时长）
          if (audioId != null && audioId.isNotEmpty) {
            if (audioId == _lastValidAudioId) {
              // 同一首歌，检查 duration 是否异常
              // 异常条件：新 duration < 10秒 且 之前的有效 duration > 30秒
              // 或者：新 duration 与 position 非常接近（差值 < 5秒），说明返回的是剩余缓冲区
              final isAbnormalDuration = (duration < 10 && _lastValidDuration > 30) ||
                  (duration > 0 && (duration - position).abs() < 5 && _lastValidDuration > 30);

              if (isAbnormalDuration) {
                debugPrint('⚠️ [MiIoTDirect] 检测到异常 duration: ${duration}秒（position=${position}秒），使用缓存值: ${_lastValidDuration}秒');
                duration = _lastValidDuration;
              } else if (duration > 10) {
                // 有效的 duration，更新缓存
                _lastValidDuration = duration;
              }
            } else {
              // 换歌了，更新 audio_id 和 duration 缓存
              _lastValidAudioId = audioId;
              if (duration > 10) {
                _lastValidDuration = duration;
                debugPrint('🎵 [MiIoTDirect] 新歌曲 audio_id: $audioId, duration: ${duration}秒');
              }
            }
          }

          // 🎯 智能更新：只有当新值有效时才更新，否则保留原值
          // 注意：小米 IoT API 通常不返回 title，所以必须保留原来的歌曲名！
          String finalTitle;
          int finalDuration;

          // 🎯 智能状态更新策略
          // 关键原则：轮询只负责更新进度和播放状态，不修改歌曲名！
          // 歌曲名只能由 playMusic() 设置（因为 API 不返回）
          if (_currentPlayingMusic != null) {
            // 已有播放信息，智能合并

            // 🎯 关键修复：严格保留原歌曲名！
            // 轮询只更新进度和播放状态，绝不覆盖歌曲名
            // API 返回的 title 通常为空，不能用它覆盖原有歌曲名
            if (title != null && title.isNotEmpty && _currentPlayingMusic!.curMusic.isEmpty) {
              // 仅当原歌曲名为空且API返回了标题时，才使用API的标题
              finalTitle = title;
              debugPrint('🎯 [MiIoTDirect] 使用API返回的标题: $title');
            } else {
              // 否则，严格保留原歌曲名（这是99%的情况）
              finalTitle = _currentPlayingMusic!.curMusic;
              if (title != null && title.isNotEmpty && title != finalTitle) {
                debugPrint('⚠️ [MiIoTDirect] 忽略API标题 "$title"，保留原歌曲名 "$finalTitle"');
              }
            }

            finalDuration = (duration > 0)
                ? duration
                : _currentPlayingMusic!.duration;

            // 🎯 Seek 保护：如果在 seek 保护窗口内且轮询返回的进度明显低于 seek 目标，
            // 说明设备尚未完成 seek，使用 seek 目标值代替
            int finalPosition = position;
            if (_seekProtectedUntil != null &&
                _seekTargetPosition != null &&
                DateTime.now().isBefore(_seekProtectedUntil!)) {
              final diff = _seekTargetPosition! - position;
              if (diff > 5) {
                // 轮询返回的进度比 seek 目标低 5 秒以上 → 设备尚未完成 seek
                debugPrint('🛡️ [MiIoTDirect] Seek保护: 轮询=${position}s < 目标=${_seekTargetPosition}s，使用目标值');
                finalPosition = _seekTargetPosition!;
              } else {
                // 进度已接近 seek 目标，清除保护
                _seekProtectedUntil = null;
                _seekTargetPosition = null;
              }
            } else if (_seekProtectedUntil != null &&
                       DateTime.now().isAfter(_seekProtectedUntil!)) {
              // 保护窗口已过期，清除
              _seekProtectedUntil = null;
              _seekTargetPosition = null;
            }

            _currentPlayingMusic = PlayingMusic(
              ret: 'OK',
              curMusic: finalTitle,
              curPlaylist: '直连播放',
              isPlaying: isPlaying,
              duration: finalDuration,
              offset: finalPosition,
            );

            debugPrint('🔄 [MiIoTDirect] 轮询更新: 播放=$isPlaying, 进度=$position/$finalDuration秒, 歌曲=${finalTitle.isEmpty ? "(空)" : finalTitle}');

            // 🎯 更新通知栏（无论是否有歌曲名，都要更新播放状态）
            // 确保通知栏按钮状态与音箱实际状态一致
            if (finalTitle.isNotEmpty) {
              // 有歌曲名：完整更新
              _updateNotificationFromStatus();
            } else {
              // 无歌曲名：只更新播放状态按钮
              if (_audioHandler != null) {
                _audioHandler!.playbackState.add(_audioHandler!.playbackState.value.copyWith(
                  playing: isPlaying,
                  processingState: AudioProcessingState.ready,
                  updatePosition: Duration(seconds: position), // 🎯 即使无歌曲名也要更新进度
                  controls: [
                    MediaControl.skipToPrevious,
                    isPlaying ? MediaControl.pause : MediaControl.play,
                    MediaControl.skipToNext,
                  ],
                ));
                debugPrint('🔄 [MiIoTDirect] 已更新通知栏播放状态: $isPlaying, 进度: ${position}s');
              }
            }
          } else {
            // 🎯 首次轮询或APP重启后，尝试创建状态对象
            // 即使API不返回title，也要创建对象以便更新进度
            debugPrint('⏭️ [MiIoTDirect] 首次轮询或APP重启，检测到播放状态');

            // 🎯 如果音箱正在播放，创建状态对象（进度可以更新）
            if (isPlaying || position > 0) {
              _currentPlayingMusic = PlayingMusic(
                ret: 'OK',
                curMusic: title ?? '', // API通常不返回title，但先尝试
                curPlaylist: '直连播放',
                isPlaying: isPlaying,
                duration: duration,
                offset: position,
              );
              debugPrint('✅ [MiIoTDirect] 已创建状态对象: 播放=$isPlaying, 进度=$position/$duration 秒');

              // 如果有歌曲名，更新通知栏
              if (_currentPlayingMusic!.curMusic.isNotEmpty) {
                _updateNotificationFromStatus();
              }
            } else {
              // 音箱完全空闲，保持 null
              debugPrint('⏭️ [MiIoTDirect] 音箱空闲，保持 null 状态');
            }
          }
          // 🎯 detail 有真实进度，用服务器数据校准本地计时器
          _syncLocalTimerWithServer(position);
        } else if (_currentPlayingMusic != null) {
          // 🎯 detail == null: 设备不返回播放详情（如OH2P始终无 play_song_detail）
          // 使用本地时间预测 offset（与 xiaomusic 的 time.time()-_start_time 同理）

          // 🔬 实验性：首次遇到 detail=null 时尝试调用备选 API
          if (!_hasTriedAltApis && isPlaying) {
            _hasTriedAltApis = true;
            debugPrint('🔬 [MiIoTDirect] detail=null，尝试实验性 API...');
            try {
              // 尝试 player_play_status（与 player_get_play_status 不同）
              final altStatus = await _miService.getPlayStatusAlt(_deviceId);
              debugPrint('🔬 [MiIoTDirect] player_play_status 结果: $altStatus');

              // 尝试 player_get_context
              final context = await _miService.getPlayContext(_deviceId);
              debugPrint('🔬 [MiIoTDirect] player_get_context 结果: $context');
            } catch (e) {
              debugPrint('🔬 [MiIoTDirect] 实验性 API 调用失败: $e');
            }
          }

          // 🎯 非对称信任策略（针对 detail=null 设备如 OH2P）：
          // - 设备报告 status=0（停止）→ 信任（设备没有理由谎报停止）
          // - 设备报告 status=1（播放）但本地为"暂停"→ 不信任
          //   原因：OH2P 暂停后仍然返回 status=1，保护窗口过期后会错误恢复播放
          //   只有 play()/playMusic() 才能将 isPlaying 从 false 变为 true
          if (isPlaying && !_currentPlayingMusic!.isPlaying) {
            debugPrint('🛡️ [MiIoTDirect] detail=null 非对称信任：设备报告播放但本地为暂停，保持暂停');
            isPlaying = false;
          }

          // 🎯 边界情况：APP重启后检测到设备正在播放，但本地计时器未初始化
          // 从当前时刻开始计时（offset从0开始递增，虽然不精确但比卡在0好）
          if (_localPlayStartTime == null && isPlaying) {
            _localPlayStartTime = DateTime.now();
            _localAccumulatedPause = Duration.zero;
            _localPauseStartTime = null;
            debugPrint('⏱️ [MiIoTDirect] detail=null 设备正在播放但本地计时器未启动，立即初始化');
          }

          final predictedOffset = _getLocalPredictedOffset();

          _currentPlayingMusic = PlayingMusic(
            ret: _currentPlayingMusic!.ret,
            curMusic: _currentPlayingMusic!.curMusic,
            curPlaylist: _currentPlayingMusic!.curPlaylist,
            isPlaying: isPlaying,
            duration: _currentPlayingMusic!.duration,
            offset: predictedOffset,
          );
          debugPrint('🔄 [MiIoTDirect] detail=null，本地预测进度: $predictedOffset/${_currentPlayingMusic!.duration}秒, 播放=$isPlaying');
        }

        if (_isWarmupPolling) {
          final expired =
              _warmupDeadline != null &&
              DateTime.now().isAfter(_warmupDeadline!);
          final sameSong =
              _warmupSongName != null &&
              _currentPlayingMusic?.curMusic == _warmupSongName;
          final hasReadyProgress =
              sameSong &&
              (_currentPlayingMusic?.offset ?? 0) >= 1 &&
              (_currentPlayingMusic?.duration ?? 0) > 0;
          if (hasReadyProgress) {
            _exitWarmupPolling('拿到首个有效进度');
          } else if (expired) {
            _exitWarmupPolling('warmup超时');
          }
        }

        // 通知状态变化（始终通知，让 Provider 的进度预测定时器正常运作）
        // detail=null 时通过本地时间预测提供递增的 offset，不会导致进度重置
        onStatusChanged?.call(_activeSwitchSessionId);

        // 🎯 自动下一首检测：当歌曲播放完成时自动播放下一首
        //
        // ⚠️ 关键发现：
        // 1. 小爱音箱播放完歌曲后不会停止（status 保持为 1），会自动循环
        // 2. 轮询间隔 3 秒，但歌曲循环只需 1 秒，可能错过 "接近结尾" 的瞬间
        //
        // 检测策略（双保险）：
        // A. 位置接近结尾：position 接近 duration（差值 < 3秒）
        // B. 位置跳跃检测：上一次 position 接近结尾，这一次跳回开头
        if (_currentPlayingMusic != null && detail != null) {
          final audioId = detail['audio_id'] as String?;
          final durationMs = detail['duration'] as int? ?? 0;
          final positionMs = detail['position'] as int? ?? 0;
          final detailDuration = (durationMs / 1000).round();
          final detailPosition = (positionMs / 1000).round();

          final hasValidAudioId = audioId != null && audioId.isNotEmpty;

          // 🔄 重置保护标志：当 audio_id 变化时（新歌开始播放）
          if (hasValidAudioId && _isAutoNextTriggered && audioId != _lastCompletedAudioId) {
            _isAutoNextTriggered = false;
            debugPrint('🔄 [MiIoTDirect] 检测到新歌曲 (audioId: $audioId)，重置自动下一首保护标志');
          }

          // ========== 歌曲完成检测（双保险） ==========

          // 方案A：position 接近 duration
          final isNearEnd = detailDuration > 10 && detailPosition > 10 && (detailDuration - detailPosition) < 6;

          // 方案B：位置跳跃检测（上一次接近结尾 → 这一次回到开头）
          // 条件：上一次 position 在最后 5 秒内，这一次 position 在前 10 秒内
          // 且是同一首歌（同一个 audio_id）
          final wasNearEnd = _lastPolledDuration > 10 &&
              _lastPolledPosition > 10 &&
              (_lastPolledDuration - _lastPolledPosition) < 5;
          final jumpedToStart = detailPosition < 10;
          final isPositionJump = wasNearEnd && jumpedToStart;

          // 更新上一次的轮询位置（放在检测之后）
          final shouldTrigger = (isNearEnd || isPositionJump) &&
              hasValidAudioId &&
              audioId != _lastCompletedAudioId &&
              !_isAutoNextTriggered;

          if (shouldTrigger) {
            final reason = isNearEnd ? '接近结尾' : '位置跳跃 (${_lastPolledPosition}s→${detailPosition}s)';
            debugPrint('🎵 [MiIoTDirect] 检测到歌曲播放完成 [$reason]: position=$detailPosition, duration=$detailDuration, audioId=$audioId');
            debugPrint('🎵 [MiIoTDirect] 触发自动下一首...');

            // 设置保护标志，防止重复触发
            _isAutoNextTriggered = true;
            _lastCompletedAudioId = audioId;

            // 触发回调
            if (onSongComplete != null) {
              onSongComplete!();
              debugPrint('✅ [MiIoTDirect] 已调用 onSongComplete 回调');
            } else {
              debugPrint('⚠️ [MiIoTDirect] onSongComplete 回调未设置');
            }
          }

          // 🔄 更新上一次轮询的位置（必须在检测之后更新）
          _lastPolledPosition = detailPosition;
          _lastPolledDuration = detailDuration;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [MiIoTDirect] 状态轮询失败: $e');
    }
  }

  /// 🎯 方案C：备用自动下一首定时器触发处理
  ///
  /// 当 API 检测（position/duration）失败时，使用此定时器作为备用。
  ///
  /// Bug2 fix: 使用本地计时器的真实播放时长（扣除暂停）判断是否到达歌曲末尾，
  /// 而非 _currentPlayingMusic.offset（该值到达 duration 后就封顶不更新，
  /// 如果歌曲已单曲循环重新开始，offset 依旧卡在 duration，无法用于判断）。
  /// 如果实际播放时长不足（用户暂停了很久导致挂钟超时），则重新调度定时器。
  void _handleBackupAutoNextTimer(String expectedMusicName) {
    debugPrint('⏱️ [MiIoTDirect] 备用定时器触发，检查是否需要自动下一首');
    debugPrint('   - 期望歌曲: $expectedMusicName');
    debugPrint('   - 当前歌曲: ${_currentPlayingMusic?.curMusic ?? "空"}');
    debugPrint('   - 已触发过: $_isAutoNextTriggered');

    // 验证条件：
    // 1. 定时器对应的歌曲名与当前播放的歌曲名一致（没有被手动切歌）
    // 2. 尚未通过 API 检测触发过自动下一首
    final currentMusic = _currentPlayingMusic?.curMusic ?? '';
    final isSameSong = currentMusic == expectedMusicName ||
        expectedMusicName == _backupTimerMusicName;

    if (!isSameSong) {
      debugPrint('⏭️ [MiIoTDirect] 歌曲已切换，忽略备用定时器');
      return;
    }

    if (_isAutoNextTriggered) {
      debugPrint('⏭️ [MiIoTDirect] 已通过 API 检测触发，忽略备用定时器');
      return;
    }

    // 🎯 Bug2 fix: 用本地计时器的实际播放时长判断，而非可能封顶的 offset
    final predictedOffset = _getLocalPredictedOffset();
    final duration = _currentPlayingMusic?.duration ?? 0;
    if (duration > 0) {
      final remaining = duration - predictedOffset;
      if (remaining > 15) {
        // 实际播放时长还差很远，说明用户暂停了很久导致挂钟超时
        // 重新调度定时器（剩余播放时长 + 5秒缓冲）
        final reschedule = Duration(seconds: remaining + 5);
        debugPrint('⏭️ [MiIoTDirect] 备用定时器：实际播放 $predictedOffset/$duration 秒，'
            '剩余 $remaining 秒，未到结尾，重新调度 ${reschedule.inSeconds}秒后再检查');
        _backupAutoNextTimer?.cancel();
        _backupAutoNextTimer = Timer(reschedule, () {
          _handleBackupAutoNextTimer(expectedMusicName);
        });
        return;
      }
    }

    // 🎯 触发自动下一首
    debugPrint('🎵 [MiIoTDirect] 备用定时器：触发自动下一首！(播放进度: $predictedOffset/$duration)');
    _isAutoNextTriggered = true;

    if (onSongComplete != null) {
      onSongComplete!();
      debugPrint('✅ [MiIoTDirect] 备用定时器：已调用 onSongComplete 回调');
    } else {
      debugPrint('⚠️ [MiIoTDirect] 备用定时器：onSongComplete 回调未设置');
    }
  }

  /// 更新通知栏状态
  void _updateNotificationFromStatus() {
    if (_audioHandler == null || _currentPlayingMusic == null) return;

    final parts = _currentPlayingMusic!.curMusic.split(' - ');
    final title = parts.isNotEmpty ? parts[0] : _currentPlayingMusic!.curMusic;
    final artist = parts.length > 1 ? parts[1] : _deviceName;

    // 🎯 关键修复：同时更新媒体信息和播放状态
    // 确保通知栏显示正确的歌曲信息和按钮状态
    _audioHandler!.setMediaItem(
      title: title,
      artist: artist,
      album: '直连模式',
      artUri: _albumCoverUrl,
      duration: Duration(seconds: _currentPlayingMusic!.duration),
    );

    // 🎯 同步播放状态到通知栏（修复按钮状态不一致问题）
    _audioHandler!.playbackState.add(_audioHandler!.playbackState.value.copyWith(
      playing: _currentPlayingMusic!.isPlaying,
      processingState: AudioProcessingState.ready,
      updatePosition: Duration(seconds: _currentPlayingMusic!.offset), // 🎯 关键修复：更新进度条位置
      controls: [
        MediaControl.skipToPrevious,
        _currentPlayingMusic!.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
    ));

    debugPrint('🔔 [MiIoTDirect] 通知栏已更新: 歌曲=$title, 播放=${_currentPlayingMusic!.isPlaying}, 进度=${_currentPlayingMusic!.offset}s');
  }

  /// 初始化音频处理器（通知栏控制）
  void _initializeAudioHandler() {
    if (_audioHandler != null) {
      // 禁用本地播放器监听
      _audioHandler!.setListenToLocalPlayer(false);
      debugPrint('🔧 [MiIoTDirect] 已禁用本地播放器监听');

      // 🎯 启用远程播放模式（防止APP退后台时音箱暂停）
      _audioHandler!.setRemotePlayback(true);
      debugPrint('🔧 [MiIoTDirect] 已启用远程播放模式');

      // 连接通知栏控制按钮（默认回调，PlaybackProvider 会覆盖 play/pause/next/previous）
      // onPlay/onPause/onNext/onPrevious 由 PlaybackProvider 设置，
      // 路由到 PlaybackProvider 的方法以支持播放队列逻辑

      // 🎯 关键修复：初始化通知栏显示时设置正确的 PlaybackState
      // 确保控制中心能正常显示控制项
      _audioHandler!.setMediaItem(
        title: '正在加载...',
        artist: _deviceName,
        album: '直连模式',
      );

      // 🎯 设置初始播放状态，确保通知栏控制项正常显示
      _audioHandler!.playbackState.add(_audioHandler!.playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.ready, // 🔧 关键：设置为 ready 才能显示控制项
        updatePosition: Duration.zero, // 🎯 初始化时进度为0
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
      ));

      debugPrint('🔧 [MiIoTDirect] 已初始化通知栏为直连模式');
    }
  }

  @override
  bool get isLocalMode => false;

  @override
  Future<void> play() async {
    debugPrint('🎵 [MiIoTDirect] 执行播放 (设备: $_deviceId)');

    try {
      // 🎯 OH2P 等需要 player_play_music API 的设备：
      // player_play_operation('play') 对这类设备无法恢复播放（API 返回 200 但设备无声音）
      // 必须重新发送完整的 player_play_music 命令才能让音箱重新发声
      // 注意：L05B 等设备虽然用 player_play_music 播新歌，但支持正常 resume，不在此列
      final needsFullReplay = _hardware != null &&
          MiHardwareDetector.needsFullReplayOnResume(_hardware!) &&
          _currentMusicUrl != null &&
          _currentPlayingMusic != null;

      if (needsFullReplay) {
        // 🎯 Bug1 fix: OH2P 不支持 startOffset，resume 必须从头播放
        // 不传 startOffsetSec，让 playMusic 内部和本地计时器都从 0 开始
        final supportsOffset = _hardware != null &&
            MiHardwareDetector.supportsStartOffset(_hardware!);
        final resumeOffset = supportsOffset ? _currentPlayingMusic!.offset : 0;
        debugPrint(
            '🔄 [MiIoTDirect] 设备 $_hardware 不支持 resume，重新发送播放命令'
            ' (startOffset=${supportsOffset ? "${resumeOffset}s" : "不支持，从头播放"})...');
        await playMusic(
          musicName: _currentPlayingMusic!.curMusic,
          url: _currentMusicUrl,
          duration: _currentPlayingMusic!.duration > 0
              ? _currentPlayingMusic!.duration
              : null,
          startOffsetSec: supportsOffset && resumeOffset > 0 ? resumeOffset : null,
        );
        // playMusic() 内部已完整处理状态更新，直接返回
        return;
      }

      final success = await _miService.resume(_deviceId);

      if (success) {
        debugPrint('✅ [MiIoTDirect] 播放成功');

        // 🎯 立即更新本地播放状态为播放中
        if (_currentPlayingMusic != null) {
          _currentPlayingMusic = PlayingMusic(
            ret: _currentPlayingMusic!.ret,
            curMusic: _currentPlayingMusic!.curMusic,
            curPlaylist: _currentPlayingMusic!.curPlaylist,
            isPlaying: true,
            duration: _currentPlayingMusic!.duration,
            offset: _currentPlayingMusic!.offset,
          );
        }

        // 🛡️ 设置播放保护窗口（5秒内忽略设备返回的"暂停"状态）
        _playingStateProtectedUntil = DateTime.now().add(const Duration(seconds: 5));
        _pauseStateProtectedUntil = null; // 互斥：清除暂停保护

        // 🎯 恢复本地计时器：累计暂停时长，清除暂停时间点
        if (_localPauseStartTime != null) {
          _localAccumulatedPause += DateTime.now().difference(_localPauseStartTime!);
          _localPauseStartTime = null;
          debugPrint('⏱️ [MiIoTDirect] 本地计时器：恢复计时，累计暂停=${_localAccumulatedPause.inSeconds}秒');
        }

        // 通知状态变化
        onStatusChanged?.call(_activeSwitchSessionId);
      } else {
        debugPrint('❌ [MiIoTDirect] 播放失败');
      }
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 播放异常: $e');
    }
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [MiIoTDirect] 执行暂停 (设备: $_deviceId)');

    try {
      final success = await _miService.pause(_deviceId);

      if (success) {
        debugPrint('✅ [MiIoTDirect] 暂停成功');

        // 🎯 立即更新本地播放状态为暂停
        // 部分设备（如OH2P）状态API不可靠，始终返回 status=1
        // 必须信任本地命令状态，而非设备返回值
        if (_currentPlayingMusic != null) {
          _currentPlayingMusic = PlayingMusic(
            ret: _currentPlayingMusic!.ret,
            curMusic: _currentPlayingMusic!.curMusic,
            curPlaylist: _currentPlayingMusic!.curPlaylist,
            isPlaying: false,
            duration: _currentPlayingMusic!.duration,
            offset: _currentPlayingMusic!.offset,
          );
        }

        // 🛡️ 设置暂停保护窗口（5秒内忽略设备返回的"播放"状态）
        _pauseStateProtectedUntil = DateTime.now().add(const Duration(seconds: 5));
        _playingStateProtectedUntil = null; // 互斥：清除播放保护

        // 🎯 记录暂停开始时间（用于本地时间预测）
        if (_localPauseStartTime == null) {
          _localPauseStartTime = DateTime.now();
          debugPrint('⏱️ [MiIoTDirect] 本地计时器：记录暂停时间点');
        }

        // 通知状态变化
        onStatusChanged?.call(_activeSwitchSessionId);
      } else {
        debugPrint('❌ [MiIoTDirect] 暂停失败');
      }
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 暂停异常: $e');
    }
  }

  @override
  Future<void> next() async {
    debugPrint('🎵 [MiIoTDirect] 播放下一首');

    if (_playlist.isEmpty) {
      debugPrint('⚠️ [MiIoTDirect] 播放列表为空，无法播放下一首');
      return;
    }

    _currentIndex = (_currentIndex + 1) % _playlist.length;
    final nextMusic = _playlist[_currentIndex];
    debugPrint('🎵 [MiIoTDirect] 下一首: ${nextMusic.name} (index: $_currentIndex)');

    // 获取音乐URL并播放
    await _playMusicFromPlaylist(nextMusic);
  }

  @override
  Future<void> previous() async {
    debugPrint('🎵 [MiIoTDirect] 播放上一首');

    if (_playlist.isEmpty) {
      debugPrint('⚠️ [MiIoTDirect] 播放列表为空，无法播放上一首');
      return;
    }

    _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    final prevMusic = _playlist[_currentIndex];
    debugPrint('🎵 [MiIoTDirect] 上一首: ${prevMusic.name} (index: $_currentIndex)');

    // 获取音乐URL并播放
    await _playMusicFromPlaylist(prevMusic);
  }

  /// 从播放列表播放指定音乐
  Future<void> _playMusicFromPlaylist(Music music) async {
    try {
      // Music 模型只有名字，需要通过回调获取URL
      String? url;
      if (onGetMusicUrl != null) {
        debugPrint('🔍 [MiIoTDirect] 获取音乐URL: ${music.name}');
        url = await onGetMusicUrl!(music.name);
      }

      if (url == null || url.isEmpty) {
        debugPrint('❌ [MiIoTDirect] 无法获取音乐URL: ${music.name}');
        return;
      }

      await playMusic(musicName: music.name, url: url);
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 播放失败: $e');
    }
  }

  /// 🎵 设置播放列表
  void setPlaylist(List<Music> playlist, {int startIndex = 0}) {
    _playlist = playlist;
    _currentIndex = startIndex;
    debugPrint('🎵 [MiIoTDirect] 设置播放列表: ${playlist.length} 首歌曲, 起始索引: $startIndex');
  }

  /// 获取当前播放列表
  List<Music> get playlist => List.unmodifiable(_playlist);

  @override
  Future<void> seekTo(int seconds) async {
    // 🎯 Bug3 fix: OH2P 等设备不支持 seek，直接忽略
    if (_hardware != null && !MiHardwareDetector.supportsSeek(_hardware!)) {
      debugPrint('⚠️ [MiIoTDirect] 设备 $_hardware 不支持 seek，忽略 seekTo(${seconds}s)');
      return;
    }

    debugPrint('🎯 [MiIoTDirect] 跳转进度: ${seconds}秒 (设备: $_deviceId)');
    try {
      final positionMs = seconds * 1000;
      final success = await _miService.seekTo(_deviceId, positionMs);
      if (success) {
        debugPrint('✅ [MiIoTDirect] 跳转进度成功');

        // 🎯 设置 seek 保护窗口（3秒内忽略比 seek 目标值回退的进度）
        _seekProtectedUntil = DateTime.now().add(const Duration(seconds: 3));
        _seekTargetPosition = seconds;
        debugPrint('🛡️ [MiIoTDirect] 设置 seek 保护窗口: 3秒，目标: ${seconds}秒');

        // 🎯 Seek 期间也保护播放状态：设备 seek 时可能短暂汇报 status=2（缓冲）
        // 不应让 APP 误认为用户暂停了
        if (_currentPlayingMusic?.isPlaying == true) {
          _playingStateProtectedUntil = DateTime.now().add(const Duration(seconds: 3));
          debugPrint('🛡️ [MiIoTDirect] Seek期间保护播放状态: 3秒');
        }

        // 🎯 同步本地计时器：重置起始时间 = now - seekPosition
        _localPlayStartTime = DateTime.now().subtract(Duration(seconds: seconds));
        _localAccumulatedPause = Duration.zero;
        _localPauseStartTime = null;

        // 🎯 同步当前播放状态的 offset
        if (_currentPlayingMusic != null) {
          _currentPlayingMusic = PlayingMusic(
            ret: _currentPlayingMusic!.ret,
            curMusic: _currentPlayingMusic!.curMusic,
            curPlaylist: _currentPlayingMusic!.curPlaylist,
            isPlaying: _currentPlayingMusic!.isPlaying,
            duration: _currentPlayingMusic!.duration,
            offset: seconds,
          );
          onStatusChanged?.call(_activeSwitchSessionId);
        }
      } else {
        debugPrint('❌ [MiIoTDirect] 跳转进度失败');
      }
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 跳转进度异常: $e');
    }
  }

  @override
  Future<void> setVolume(int volume) async {
    debugPrint('🔊 [MiIoTDirect] 设置音量: $volume (设备: $_deviceId)');
    try {
      final success = await _miService.setVolume(_deviceId, volume);
      if (success) {
        debugPrint('✅ [MiIoTDirect] 音量设置成功');
      } else {
        debugPrint('❌ [MiIoTDirect] 音量设置失败');
      }
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 设置音量异常: $e');
    }
  }

  @override
  Future<void> playMusic({
    required String musicName,
    String? url,
    String? platform,
    String? songId,
    int? duration, // 🎯 方案C：歌曲时长（秒），用于设置备用倒计时定时器
    int? switchSessionId,
    int? startOffsetSec, // 🎯 起始播放位置（秒），用于 OH2P 暂停后从指定位置恢复
  }) async {
    debugPrint('🎵 [MiIoTDirect] 播放音乐: $musicName');
    debugPrint('🔗 [MiIoTDirect] URL: $url');
    debugPrint('📱 [MiIoTDirect] 设备硬件: ${_hardware ?? "未知"}');

    if (url == null || url.isEmpty) {
      debugPrint('❌ [MiIoTDirect] 播放URL为空');
      return;
    }

    // 🎯 保存当前播放 URL（用于 OH2P 等设备暂停后恢复播放）
    _currentMusicUrl = url;

    _activeSwitchSessionId = switchSessionId;

    // 🎯 关键修复：播放新歌时暂停状态轮询，避免竞态条件
    // 问题：状态轮询定时器可能在播放流程中间触发，获取到旧歌状态并覆盖新歌信息
    // 解决：暂停轮询 → 播放新歌 → 恢复轮询
    debugPrint('⏸️ [MiIoTDirect] 暂停状态轮询，避免竞态条件');
    _statusTimer?.cancel();

    try {
      // 🎯 调用增强的播放API，传入音乐名称和硬件信息
      final success = await _miService.playMusic(
        deviceId: _deviceId,
        musicUrl: url,
        musicName: musicName, // 🎯 传入音乐名称用于生成音频ID
        durationMs: duration != null ? duration * 1000 : null, // 🎯 传入歌曲时长（秒→毫秒）
        startOffsetMs:
            startOffsetSec != null && startOffsetSec > 0
                ? startOffsetSec * 1000
                : null, // 🎯 传入起始位置（秒→毫秒），OH2P 暂停后恢复用
      );

      if (success) {
        debugPrint('✅ [MiIoTDirect] 播放成功');

        // 🎯 异步设置设备为单曲循环，防止设备自行播放未知内容
        // APP 端自己管理播放队列和下一首逻辑
        _miService.setLoopType(_deviceId, 0).then((ok) {
          if (ok) {
            debugPrint('🔁 [MiIoTDirect] 已设置设备为单曲循环（APP管理队列）');
          } else {
            debugPrint('⚠️ [MiIoTDirect] 设置单曲循环失败，设备可能自行切歌');
          }
        }).catchError((e) {
          debugPrint('⚠️ [MiIoTDirect] 设置单曲循环异常: $e');
        });

        // 更新当前播放信息
        _currentPlayingMusic = PlayingMusic(
          ret: 'OK',
          curMusic: musicName,
          curPlaylist: '直连播放',
          isPlaying: true,
          duration: duration ?? 0, // 使用传入的歌曲时长，无则回退 0
          offset: startOffsetSec ?? 0, // 🎯 从起始位置开始（恢复播放时为暂停位置，新歌为0）
        );
        debugPrint('✅ [MiIoTDirect] 已设置播放状态: 歌曲=$musicName, 播放=true');
        debugPrint('🔧 [MiIoTDirect] _currentPlayingMusic.curMusic = "${_currentPlayingMusic!.curMusic}"');

        // 🎯 保存播放状态到本地（重启后可恢复）
        _saveCurrentPlayingState();

        // 更新通知栏媒体信息和播放状态
        final parts = musicName.split(' - ');
        final title = parts.isNotEmpty ? parts[0] : musicName;
        final artist = parts.length > 1 ? parts[1] : _deviceName;

        if (_audioHandler != null) {
          // 1️⃣ 设置媒体信息
          _audioHandler!.setMediaItem(
            title: title,
            artist: artist,
            album: '直连模式 (${_hardware ?? "未知设备"})',
            artUri: _albumCoverUrl,
          );

          // 2️⃣ 🎯 关键修复：更新播放状态和控制按钮
          _audioHandler!.playbackState.add(_audioHandler!.playbackState.value.copyWith(
            playing: true, // 设置为播放状态
            processingState: AudioProcessingState.ready,
            updatePosition: Duration.zero, // 🎯 播放新歌曲时进度从0开始
            controls: [
              MediaControl.skipToPrevious,
              MediaControl.pause, // 显示暂停按钮
              MediaControl.skipToNext,
            ],
            systemActions: const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
          ));
          debugPrint('✅ [MiIoTDirect] 已更新通知栏播放状态为播放中（进度:0s）');
        }

        // 🛡️ 设置播放状态保护窗口（5秒内忽略轮询返回的"暂停"状态）
        _playingStateProtectedUntil = DateTime.now().add(const Duration(seconds: 5));
        _pauseStateProtectedUntil = null; // 互斥：清除暂停保护
        _seekProtectedUntil = null; // 🎯 新歌开始，清除旧的 seek 保护
        _seekTargetPosition = null;
        debugPrint('🛡️ [MiIoTDirect] 设置播放状态保护窗口: 5秒');

        // 🎯 初始化本地时间预测计时器
        // 恢复播放时从暂停位置开始计时，新歌从 0 开始
        _localPlayStartTime = startOffsetSec != null && startOffsetSec > 0
            ? DateTime.now().subtract(Duration(seconds: startOffsetSec))
            : DateTime.now();
        _localAccumulatedPause = Duration.zero;
        _localPauseStartTime = null;
        debugPrint('⏱️ [MiIoTDirect] 本地计时器已启动 (起始: ${startOffsetSec ?? 0}s)');

        // 🎯 方案C：设置备用自动下一首定时器
        // 当 API 返回的 play_song_detail 为空或 duration=0 时，使用此定时器作为备用
        _backupAutoNextTimer?.cancel();
        _backupTimerMusicName = musicName;
        if (duration != null && duration > 10) {
          // 定时器时间 = 剩余时长 + 5秒缓冲（恢复播放时要减去已播放部分）
          final elapsed = startOffsetSec ?? 0;
          final remaining = (duration - elapsed).clamp(0, duration);
          final timerDuration = Duration(seconds: remaining + 5);
          debugPrint(
              '⏱️ [MiIoTDirect] 设置备用自动下一首定时器: ${timerDuration.inSeconds}秒 (歌曲时长: ${duration}秒, 起始: ${elapsed}s, 剩余: ${remaining}s)');

          _backupAutoNextTimer = Timer(timerDuration, () {
            _handleBackupAutoNextTimer(musicName);
          });
        } else {
          debugPrint('⚠️ [MiIoTDirect] 无有效 duration ($duration)，未设置备用定时器');
        }

        // 🔄 重置自动下一首保护标志（新歌开始）
        _isAutoNextTriggered = false;
        _lastCompletedAudioId = null;
        _hasTriedAltApis = false; // 🔬 新歌开始时重置实验性 API 标志

        // 🎯 播放命令推送成功，立即通知 Provider 开始进度计时
        // offset=0 就是正确的起始点（歌曲此刻刚开始播放）
        // Provider 收到后会启动本地进度预测定时器：0→1→2→3...
        // 3 秒后周期轮询拿到设备真实位置（~3s），与预测值吻合，无跳动
        _enterWarmupPolling(musicName);
        onStatusChanged?.call(_activeSwitchSessionId);
      } else {
        debugPrint('❌ [MiIoTDirect] 播放失败');
      }
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 播放异常: $e');
    } finally {
      // 🔇 解除切歌准备期（慢网下旧 HTTP 可能仍未返回，由 session 快照兜底）
      _isSongSwitchPending = false;

      // 🎯 即时轮询获取设备真实位置（带超时保护，避免网络慢时阻塞轮询恢复）
      try {
        debugPrint('▶️ [MiIoTDirect] 即时轮询获取真实进度...');
        await _pollPlayStatus().timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('⚠️ [MiIoTDirect] 即时轮询超时或失败，跳过: $e');
      }
      // 无论即时轮询成功与否，都恢复周期性轮询
      _startStatusPolling(
        intervalSeconds: _isWarmupPolling ? 1 : _statusPollIntervalSeconds,
      );
    }
  }

  @override
  Future<void> playMusicList({
    required String listName,
    required String musicName,
  }) async {
    debugPrint('⚠️ [MiIoTDirect] 直连模式不支持播放列表功能');
    // 直连模式需要xiaomusic服务端的歌单功能
    // 这里只能播放单曲
  }

  @override
  Future<PlayingMusic?> getCurrentStatus() async {
    // 直连模式无法主动查询播放状态
    // 返回缓存的状态
    debugPrint('🔍 [MiIoTDirect] getCurrentStatus 被调用，返回: ${_currentPlayingMusic?.curMusic ?? "null"}');
    return _currentPlayingMusic;
  }

  @override
  Future<int> getVolume() async {
    // 🎯 尝试从设备获取真实音量
    try {
      final status = await _miService.getPlayStatus(_deviceId);
      if (status != null) {
        // 🔧 小米IoT API 返回的播放状态中可能包含音量信息
        // 如果有 volume 字段，使用它；否则返回默认值
        final volume = status['volume'] as int?;
        if (volume != null) {
          debugPrint('✅ [MiIoTDirect] 获取到设备音量: $volume');
          return volume;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [MiIoTDirect] 获取音量失败: $e');
    }

    // 返回默认值
    debugPrint('⚠️ [MiIoTDirect] 使用默认音量值: 50');
    return 50;
  }

  @override
  Future<void> dispose() async {
    debugPrint('🔧 [MiIoTDirect] 释放资源');

    // 🎯 释放APP生命周期监听器
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    debugPrint('🔧 [MiIoTDirect] 已释放APP生命周期监听器');

    _statusTimer?.cancel();
    _statusTimer = null;
    _isWarmupPolling = false;
    _warmupDeadline = null;
    _warmupSongName = null;
    _activeSwitchSessionId = null;
    _currentPlayingMusic = null;
    _albumCoverUrl = null;
    _playlist.clear();
    onStatusChanged = null;
    onGetMusicUrl = null;
    onSongComplete = null; // 🎯 清理播放完成回调

    // 🎯 清理自动下一首保护标志
    _isAutoNextTriggered = false;
    _lastCompletedAudioId = null;
    _lastPolledPosition = 0;
    _lastPolledDuration = 0;

    // 🎯 方案C：清理备用定时器
    _backupAutoNextTimer?.cancel();
    _backupAutoNextTimer = null;
    _backupTimerMusicName = null;

    // 🎯 清理 duration 缓存
    _lastValidAudioId = null;
    _lastValidDuration = 0;

    // 🎯 清理播放状态保护窗口
    _playingStateProtectedUntil = null;
    _pauseStateProtectedUntil = null;

    // 🎯 清理本地时间预测计时器
    _localPlayStartTime = null;
    _localAccumulatedPause = Duration.zero;
    _localPauseStartTime = null;

    // 🔇 清理切歌准备状态
    _isSongSwitchPending = false;

    // 🎯 恢复AudioHandler为本地播放模式
    if (_audioHandler != null) {
      _audioHandler!.setListenToLocalPlayer(true);
      _audioHandler!.setRemotePlayback(false);
      debugPrint('🔧 [MiIoTDirect] 已恢复AudioHandler为本地播放模式');
    }
  }

  /// 更新通知栏状态
  void _updateNotificationState({bool? isPlaying}) {
    if (_audioHandler == null || _currentPlayingMusic == null) {
      return;
    }

    final playing = isPlaying ?? _currentPlayingMusic!.isPlaying;

    // 注意: AudioHandlerService 通过 play/pause 方法自动更新状态
    // 这里只需要调用对应的播放控制方法
    if (playing) {
      // 通知栏会自动显示播放状态
      debugPrint('🔔 [MiIoTDirect] 通知栏状态: 播放中');
    } else {
      debugPrint('🔔 [MiIoTDirect] 通知栏状态: 已暂停');
    }
  }

  /// 设置封面图URL（外部调用）
  void setAlbumCover(String? coverUrl) {
    _albumCoverUrl = coverUrl;

    // 🎯 保存封面URL到本地
    _saveCurrentPlayingState();

    if (_audioHandler != null && _currentPlayingMusic != null) {
      final parts = _currentPlayingMusic!.curMusic.split(' - ');
      final title = parts.isNotEmpty ? parts[0] : _currentPlayingMusic!.curMusic;
      final artist = parts.length > 1 ? parts[1] : _deviceName;

      _audioHandler!.setMediaItem(
        title: title,
        artist: artist,
        album: '直连模式',
        artUri: coverUrl,
      );
    }
  }
}
