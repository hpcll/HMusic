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
  Function()? onStatusChanged;

  @override
  String? get lastAudioId => null;

  // 获取音乐URL的回调（由PlaybackProvider设置）
  Future<String?> Function(String musicName)? onGetMusicUrl;

  // 🎯 歌曲播放完成回调（用于自动下一首）
  Function()? onSongComplete;

  // 当前播放状态缓存
  PlayingMusic? _currentPlayingMusic;
  String? _albumCoverUrl;

  // 🎵 播放列表管理（APP端维护）
  List<Music> _playlist = [];
  int _currentIndex = 0;

  // 🔄 状态轮询定时器
  Timer? _statusTimer;

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

  // 🎯 播放状态保护窗口（用于修复 playMusic 后状态被轮询覆盖的问题）
  // playMusic() 成功后，在保护窗口内忽略轮询返回的"暂停"状态
  DateTime? _playingStateProtectedUntil;

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
    Function()? onStatusChanged, // 🔧 在构造函数中接收回调，确保轮询启动前已设置
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
        onStatusChanged?.call();
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

  /// 🔄 启动状态轮询（每3秒获取一次播放状态）
  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollPlayStatus();
    });
    debugPrint('⏰ [MiIoTDirect] 启动状态轮询');
  }

  /// 🔄 轮询播放状态
  Future<void> _pollPlayStatus() async {
    // 🎯 后台时跳过轮询，避免网络访问被系统限制
    if (_isAppInBackground) {
      debugPrint('⏭️ [MiIoTDirect] APP在后台，跳过本次轮询');
      return;
    }

    try {
      final status = await _miService.getPlayStatus(_deviceId);
      if (status != null) {
        // 解析状态
        var isPlaying = status['status'] == 1;
        final detail = status['play_song_detail'] as Map<String, dynamic>?;

        // 🎯 检查播放状态保护窗口
        // 如果在保护窗口内且设备返回"暂停"，忽略这个状态，保持为"播放"
        // 原因：playMusic() 成功后设备状态同步有延迟，前几次轮询可能返回旧的"暂停"状态
        if (_playingStateProtectedUntil != null) {
          if (DateTime.now().isBefore(_playingStateProtectedUntil!)) {
            if (!isPlaying && _currentPlayingMusic?.isPlaying == true) {
              debugPrint('🛡️ [MiIoTDirect] 保护窗口内，忽略设备返回的"暂停"状态，保持为"播放"');
              isPlaying = true;
            }
          } else {
            // 保护窗口已过期，清除
            _playingStateProtectedUntil = null;
            debugPrint('🛡️ [MiIoTDirect] 播放状态保护窗口已过期');
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

            _currentPlayingMusic = PlayingMusic(
              ret: 'OK',
              curMusic: finalTitle,
              curPlaylist: '直连播放',
              isPlaying: isPlaying,
              duration: finalDuration,
              offset: position,
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
        } else if (_currentPlayingMusic != null) {
          // 没有详情时只更新播放状态
          _currentPlayingMusic = PlayingMusic(
            ret: _currentPlayingMusic!.ret,
            curMusic: _currentPlayingMusic!.curMusic,
            curPlaylist: _currentPlayingMusic!.curPlaylist,
            isPlaying: isPlaying,
            duration: _currentPlayingMusic!.duration,
            offset: _currentPlayingMusic!.offset,
          );
          debugPrint('🔄 [MiIoTDirect] 仅更新播放状态: $isPlaying');
        }

        // 通知状态变化
        onStatusChanged?.call();

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
  /// 当 API 检测（position/duration）失败时，使用此定时器作为备用
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

    // 🎯 触发自动下一首
    debugPrint('🎵 [MiIoTDirect] 备用定时器：触发自动下一首！');
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

      // 连接通知栏控制按钮
      _audioHandler!.onPlay = () {
        debugPrint('🎵 [MiIoTDirect] 通知栏触发播放');
        play();
      };
      _audioHandler!.onPause = () {
        debugPrint('🎵 [MiIoTDirect] 通知栏触发暂停');
        pause();
      };
      _audioHandler!.onNext = () {
        debugPrint('🎵 [MiIoTDirect] 通知栏触发下一首');
        next();
      };
      _audioHandler!.onPrevious = () {
        debugPrint('🎵 [MiIoTDirect] 通知栏触发上一首');
        previous();
      };

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
      final success = await _miService.resume(_deviceId);

      if (success) {
        debugPrint('✅ [MiIoTDirect] 播放成功');

        // 通知状态变化
        onStatusChanged?.call();
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

        // 通知状态变化
        onStatusChanged?.call();
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
    debugPrint('⚠️ [MiIoTDirect] 直连模式暂不支持进度拖动');
    // 小米IoT API目前不支持进度控制
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
  }) async {
    debugPrint('🎵 [MiIoTDirect] 播放音乐: $musicName');
    debugPrint('🔗 [MiIoTDirect] URL: $url');
    debugPrint('📱 [MiIoTDirect] 设备硬件: ${_hardware ?? "未知"}');

    if (url == null || url.isEmpty) {
      debugPrint('❌ [MiIoTDirect] 播放URL为空');
      return;
    }

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
      );

      if (success) {
        debugPrint('✅ [MiIoTDirect] 播放成功');

        // 更新当前播放信息
        _currentPlayingMusic = PlayingMusic(
          ret: 'OK',
          curMusic: musicName,
          curPlaylist: '直连播放',
          isPlaying: true,
          duration: 0, // 直连模式无法获取时长
          offset: 0,
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

        // 🎯 设置播放状态保护窗口（5秒内忽略轮询返回的"暂停"状态）
        // 原因：小米设备状态同步有延迟，轮询可能获取到旧的"暂停"状态
        _playingStateProtectedUntil = DateTime.now().add(const Duration(seconds: 5));
        debugPrint('🛡️ [MiIoTDirect] 设置播放状态保护窗口: 5秒');

        // 🎯 方案C：设置备用自动下一首定时器
        // 当 API 返回的 play_song_detail 为空或 duration=0 时，使用此定时器作为备用
        _backupAutoNextTimer?.cancel();
        _backupTimerMusicName = musicName;
        if (duration != null && duration > 10) {
          // 定时器时间 = 歌曲时长 + 5秒缓冲（确保歌曲真的播放完成）
          final timerDuration = Duration(seconds: duration + 5);
          debugPrint('⏱️ [MiIoTDirect] 设置备用自动下一首定时器: ${timerDuration.inSeconds}秒 (歌曲时长: ${duration}秒)');

          _backupAutoNextTimer = Timer(timerDuration, () {
            _handleBackupAutoNextTimer(musicName);
          });
        } else {
          debugPrint('⚠️ [MiIoTDirect] 无有效 duration ($duration)，未设置备用定时器');
        }

        // 🔄 重置自动下一首保护标志（新歌开始）
        _isAutoNextTriggered = false;
        _lastCompletedAudioId = null;

        // 通知状态变化
        debugPrint('🔔 [MiIoTDirect] 准备调用 onStatusChanged (${onStatusChanged != null ? "已设置" : "NULL"})');
        onStatusChanged?.call();
        debugPrint('🔔 [MiIoTDirect] onStatusChanged 调用完成');
      } else {
        debugPrint('❌ [MiIoTDirect] 播放失败');
      }
    } catch (e) {
      debugPrint('❌ [MiIoTDirect] 播放异常: $e');
    } finally {
      // 🎯 关键修复：恢复状态轮询（无论成功还是失败）
      // 确保轮询机制能继续工作，更新播放进度和状态
      debugPrint('▶️ [MiIoTDirect] 恢复状态轮询');
      _startStatusPolling();
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
