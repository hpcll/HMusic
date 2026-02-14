import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../models/playing_music.dart';
import 'music_api_service.dart';
import 'playback_strategy.dart';
import 'audio_handler_service.dart';

enum _PlaybackApiGroup { playUrl, legacy }

/// 远程播放策略实现
/// 通过API控制播放设备播放音乐
class RemotePlaybackStrategy implements PlaybackStrategy {
  final MusicApiService _apiService;
  final String _deviceId;
  final String _deviceName; // 🔧 设备名称,用于通知栏显示
  AudioHandlerService? _audioHandler;

  // 🔧 状态变化回调,用于通知 PlaybackProvider 更新 APP 状态
  Function()? onStatusChanged;

  // 🔧 当前封面图 URL,用于通知栏显示
  String? _albumCoverUrl;
  bool? _canUsePlayUrlGroup;
  _PlaybackApiGroup? _activeApiGroup;
  String? _lastKnownMusicName;
  bool? _lastKnownIsPlaying;
  String? _lastAudioId; // 🎯 追踪 audio_id 变化，检测服务端劫持

  /// 最近一次状态查询返回的 audio_id（用于检测同名歌曲的源切换）
  String? get lastAudioId => _lastAudioId;

  RemotePlaybackStrategy({
    required MusicApiService apiService,
    required String deviceId,
    String? deviceName, // 🔧 设备名称
    AudioHandlerService? audioHandler,
  }) : _apiService = apiService,
       _deviceId = deviceId,
       _deviceName = deviceName ?? '远程播放',
       _audioHandler = audioHandler {
    // 🔧 远程播放模式:禁用本地播放器监听,避免状态冲突
    if (_audioHandler != null) {
      _audioHandler!.setListenToLocalPlayer(false);
      debugPrint('🔧 [RemotePlayback] 已禁用本地播放器监听');

      // 🎯 启用远程播放模式（防止APP退后台时音箱暂停）
      _audioHandler!.setRemotePlayback(true);
      debugPrint('🔧 [RemotePlayback] 已启用远程播放模式');
    }

    // 🔧 连接通知栏控制按钮（默认回调，PlaybackProvider 会覆盖 play/pause/next/previous）
    if (_audioHandler != null) {
      // onPlay/onPause/onNext/onPrevious 由 PlaybackProvider 设置，
      // 路由到 PlaybackProvider 的方法以支持播放队列逻辑
      _audioHandler!.onSeek = (position) {
        debugPrint('🎵 [RemotePlayback] 通知栏跳转: ${position.inSeconds}s');
        seekTo(position.inSeconds);
      };

      // 🔧 初始化通知栏显示为远程播放,避免显示本地播放器的状态
      _audioHandler!.setMediaItem(
        title: '正在加载...',
        artist: _deviceName,
        album: '远程播放',
      );

      // 🔧 设置初始播放状态,确保通知栏显示
      _audioHandler!.playbackState.add(
        PlaybackState(
          processingState: AudioProcessingState.loading,
          playing: false,
          controls: [
            MediaControl.skipToPrevious,
            MediaControl.play,
            MediaControl.skipToNext,
          ],
        ),
      );

      debugPrint('🔧 [RemotePlayback] 已初始化通知栏为远程播放模式');
    }
  }

  @override
  bool get isLocalMode => false;

  @override
  Future<void> play() async {
    debugPrint('🎵 [RemotePlayback] 执行播放 (设备: $_deviceId)');

    // 🎯 playUrl 模式下「播放歌曲」会触发 xiaomusic 服务端歌单播放，
    // 而非恢复 playUrl 歌曲。此处不做额外处理，
    // PlaybackProvider.play() 会在上层拦截并重新 push URL。
    await _apiService.resumeMusic(did: _deviceId);

    // 🔧 获取最新状态并更新通知栏
    await _updateNotificationState();
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [RemotePlayback] 执行暂停 (设备: $_deviceId)');

    if (_activeApiGroup == _PlaybackApiGroup.playUrl) {
      // 🎯 playUrl 模式：使用 /device/stop（无 TTS）代替 /cmd 暂停
      // /cmd 暂停 → xiaomusic stop() → TTS "收到,再见" + 等待 3 秒，体验极差
      debugPrint('🎵 [RemotePlayback] playUrl 模式 → 使用 stopDevice（无 TTS）');
      await _apiService.stopDevice(did: _deviceId);
    } else {
      await _apiService.pauseMusic(did: _deviceId);
    }

    // 🔧 获取最新状态并更新通知栏
    await _updateNotificationState();
  }

  /// 🔧 更新通知栏状态(从服务器获取真实状态)
  Future<void> _updateNotificationState() async {
    if (_audioHandler == null) return;

    try {
      final status = await getCurrentStatus();
      if (status != null) {
        // getCurrentStatus() 已经更新了通知栏状态,这里不需要重复更新
        debugPrint('🔧 [RemotePlayback] 通知栏状态已更新');

        // 🔧 触发状态变化回调,通知 PlaybackProvider 更新 APP
        // 使用短延迟确保回调执行时状态已稳定
        Future.delayed(const Duration(milliseconds: 100), () {
          onStatusChanged?.call();
        });
      }
    } catch (e) {
      debugPrint('❌ [RemotePlayback] 更新通知栏状态失败: $e');
    }
  }

  @override
  Future<void> next() async {
    debugPrint('🎵 [RemotePlayback] 播放下一首 (设备: $_deviceId)');
    await _apiService.executeCommand(did: _deviceId, command: '下一首');

    // 🔧 立即刷新状态,不等待定时器
    await Future.delayed(const Duration(milliseconds: 500));
    await _updateNotificationState();
  }

  @override
  Future<void> previous() async {
    debugPrint('🎵 [RemotePlayback] 播放上一首 (设备: $_deviceId)');
    await _apiService.executeCommand(did: _deviceId, command: '上一首');

    // 🔧 立即刷新状态,不等待定时器
    await Future.delayed(const Duration(milliseconds: 500));
    await _updateNotificationState();
  }

  @override
  Future<void> seekTo(int seconds) async {
    debugPrint('🎵 [RemotePlayback] 跳转到 $seconds 秒 (设备: $_deviceId)');
    await _apiService.seek(did: _deviceId, seconds: seconds);
  }

  @override
  Future<void> setVolume(int volume) async {
    debugPrint('🎵 [RemotePlayback] 设置音量: $volume (设备: $_deviceId)');
    await _apiService.setVolume(did: _deviceId, volume: volume);
  }

  @override
  Future<void> playMusic({
    required String musicName,
    String? url,
    String? platform,
    String? songId,
    int? duration,
  }) async {
    debugPrint('🎵 [RemotePlayback] 播放音乐: $musicName (设备: $_deviceId)');
    if (musicName.isNotEmpty) {
      _lastKnownMusicName = musicName;
    }

    if (url != null && url.isNotEmpty) {
      await _playOnlineMusicWithCompatibility(musicName: musicName, url: url);
    } else {
      // 否则，使用音乐名称播放（服务器本地音乐）
      // 🛡️ 如果当前在 playUrl 分组（元歌单/在线播放中），先暂停再切换
      final didPrePause = _activeApiGroup == _PlaybackApiGroup.playUrl;
      if (didPrePause) {
        try {
          debugPrint('🔄 [RemotePlayback] 先暂停 playUrl 播放，避免切换竞争');
          await _apiService.pauseMusic(did: _deviceId);
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (_) {}
      }
      debugPrint('🎵 [RemotePlayback] 播放服务器本地音乐');
      await _apiService.playMusic(did: _deviceId, musicName: musicName);
      // 🎵 如果之前做了预暂停，playmusiclist 可能不会自动播放
      // 先检查状态，只在确实暂停时才补发恢复指令（避免重复播放开头）
      if (didPrePause) {
        try {
          await Future.delayed(const Duration(milliseconds: 500));
          final status = await _apiService.getPlayerStatus(did: _deviceId);
          final playerStatus = status['status']; // 1=playing, 2=paused
          if (playerStatus == 2) {
            debugPrint('▶️ [RemotePlayback] 检测到暂停状态，补发恢复播放指令');
            await _apiService.resumeMusic(did: _deviceId);
          } else {
            debugPrint('✅ [RemotePlayback] 已在播放中，无需补发恢复指令');
          }
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> playMusicList({
    required String listName,
    required String musicName,
  }) async {
    debugPrint(
      '🎵 [RemotePlayback] 播放列表: $listName, 歌曲: $musicName (设备: $_deviceId)',
    );
    await _apiService.playMusicList(
      did: _deviceId,
      listName: listName,
      musicName: musicName,
    );
    _activeApiGroup = _PlaybackApiGroup.legacy;
  }

  @override
  Future<PlayingMusic?> getCurrentStatus() async {
    try {
      final supportsNewGroup = await _shouldUsePlayUrlGroup();
      final useNewGroup =
          _activeApiGroup == _PlaybackApiGroup.legacy
              ? false
              : supportsNewGroup;
      Map<String, dynamic> response;

      if (useNewGroup) {
        try {
          final rawResponse = await _apiService.getPlayerStatus(did: _deviceId);
          response = _convertPlayerStatus(rawResponse);
        } catch (e) {
          _degradeToLegacyApi('getPlayerStatus 异常，回退旧分组: $e');
          response = await _apiService.getCurrentPlaying(did: _deviceId);
        }
      } else {
        // 旧分组逻辑保持不变
        response = await _apiService.getCurrentPlaying(did: _deviceId);
      }

      final curMusic = (response['cur_music'] ?? '').toString().trim();
      if (curMusic.isNotEmpty) {
        _lastKnownMusicName = curMusic;
      }

      final status = PlayingMusic.fromJson(response);

      // 🔧 更新通知栏媒体信息和播放状态
      if (_audioHandler != null && status.curMusic.isNotEmpty) {
        await _audioHandler!.setMediaItem(
          title: status.curMusic,
          artist: _deviceName, // 使用设备名称
          album: status.curPlaylist,
          duration: Duration(seconds: status.duration),
          artUri: _albumCoverUrl, // 🔧 传入封面图 URL
        );

        // 🔧 同时更新播放状态和进度,确保通知栏正确显示
        _audioHandler!.playbackState.add(
          _audioHandler!.playbackState.value.copyWith(
            playing: status.isPlaying,
            processingState: AudioProcessingState.ready, // 🔧 设置为 ready 才能显示进度条
            updatePosition: Duration(seconds: status.offset), // 🔧 更新当前进度
            bufferedPosition: Duration(seconds: status.duration), // 🔧 设置缓冲进度
            controls: [
              MediaControl.skipToPrevious,
              status.isPlaying ? MediaControl.pause : MediaControl.play,
              MediaControl.skipToNext,
            ],
          ),
        );
        debugPrint(
          '🔧 [RemotePlayback] 已更新通知栏: playing=${status.isPlaying}, position=${status.offset}s/${status.duration}s, cover=$_albumCoverUrl',
        );
      }

      return status;
    } catch (e) {
      debugPrint('❌ [RemotePlayback] 获取播放状态失败: $e');
      return null;
    }
  }

  /// 🔧 转换 getPlayerStatus 返回格式为 PlayingMusic 兼容格式
  Map<String, dynamic> _convertPlayerStatus(Map<String, dynamic> status) {
    final detail = status['play_song_detail'] as Map<String, dynamic>?;

    final isPlaying = _mapPlayerStatusToIsPlaying(status);

    // play_song_detail.position/duration 是毫秒，需要转成秒
    final durationMs = detail?['duration'] as int?;
    final positionMs = detail?['position'] as int?;
    final duration =
        durationMs != null
            ? (durationMs / 1000).round()
            : (status['duration'] as int? ?? 0);
    final offset =
        positionMs != null
            ? (positionMs / 1000).round()
            : (status['offset'] as int? ?? 0);

    final currentMusic =
        (detail?['title'] ?? status['cur_music'] ?? '').toString().trim();
    final finalMusic =
        currentMusic.isNotEmpty ? currentMusic : (_lastKnownMusicName ?? '');
    _lastKnownIsPlaying = isPlaying;

    // 🎯 保存 audio_id 用于检测同名歌曲的源切换
    final audioId = detail?['audio_id'];
    if (audioId != null) {
      _lastAudioId = audioId.toString();
    }

    return {
      'ret': status['ret'] ?? 'ok',
      'is_playing': isPlaying,
      'cur_music': finalMusic,
      'cur_playlist': status['cur_playlist'] ?? status['playlist'] ?? '',
      'offset': offset,
      'duration': duration,
    };
  }

  bool _mapPlayerStatusToIsPlaying(Map<String, dynamic> status) {
    final raw =
        status['is_playing'] ??
        status['playing'] ??
        status['play_status'] ??
        status['status'];

    if (raw is bool) return raw;
    if (raw is num) {
      final code = raw.toInt();
      if (code == 1) return true;
      if (code == 0 || code == 2) return false;
      debugPrint('⚠️ [RemotePlayback] 未知 player status 数值: $code，沿用上次状态');
      return _lastKnownIsPlaying ?? false;
    }
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == '1' || value == 'true' || value == 'playing') return true;
      if (value == '0' ||
          value == '2' ||
          value == 'false' ||
          value == 'pause' ||
          value == 'paused') {
        return false;
      }
      debugPrint('⚠️ [RemotePlayback] 未知 player status 字符串: "$raw"，沿用上次状态');
      return _lastKnownIsPlaying ?? false;
    }
    return _lastKnownIsPlaying ?? false;
  }

  void _degradeToLegacyApi(String reason) {
    if (_canUsePlayUrlGroup != false) {
      debugPrint('⚠️ [RemotePlayback] 降级到旧 API 流程: $reason');
    }
    _canUsePlayUrlGroup = false;
    _activeApiGroup = _PlaybackApiGroup.legacy;
  }

  String? get activeApiGroupName {
    if (_activeApiGroup == null) return null;
    return _activeApiGroup == _PlaybackApiGroup.playUrl ? 'playurl' : 'legacy';
  }

  void restoreActiveApiGroup(String? value) {
    if (value == 'playurl') {
      _activeApiGroup = _PlaybackApiGroup.playUrl;
    } else if (value == 'legacy') {
      _activeApiGroup = _PlaybackApiGroup.legacy;
    }
  }

  Future<bool> _shouldUsePlayUrlGroup() async {
    if (_canUsePlayUrlGroup != null) {
      return _canUsePlayUrlGroup!;
    }

    final supported = await _apiService.supportsGetPlayerStatus();
    _canUsePlayUrlGroup = supported;
    debugPrint(
      '🔧 [RemotePlayback] API分组选择: ${supported ? "新分组(/playurl + /getplayerstatus)" : "旧分组(/playmusiclist + /playingmusic)"}',
    );
    return supported;
  }

  Future<void> _playOnlineMusicWithCompatibility({
    required String musicName,
    required String url,
  }) async {
    // 🛡️ 如果当前在 legacy 分组（服务端歌单播放中），先暂停再切换
    // 避免服务端歌单逻辑与 playurl 产生竞争
    final didPrePause = _activeApiGroup == _PlaybackApiGroup.legacy;
    if (didPrePause) {
      try {
        debugPrint('🔄 [RemotePlayback] 先暂停 legacy 播放，避免切换竞争');
        await _apiService.pauseMusic(did: _deviceId);
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (_) {
        // 暂停失败不影响后续播放
      }
    }

    final useNewGroup = await _shouldUsePlayUrlGroup();
    final proxyUrl = _apiService.buildProxyUrl(url);

    if (useNewGroup) {
      // 新分组：/playurl + /getplayerstatus
      try {
        debugPrint('🎵 [RemotePlayback] 使用 playUrl API 播放');
        await _apiService.playUrl(did: _deviceId, url: proxyUrl);
        final applied = await _verifyPlayUrlApplied(
          expectedMusicName: musicName,
        );
        if (!applied) {
          throw Exception('playUrl 已返回成功，但设备状态未切换');
        }
        _activeApiGroup = _PlaybackApiGroup.playUrl;
        return;
      } catch (playUrlError) {
        _degradeToLegacyApi('playUrl 失败，回退旧分组: $playUrlError');
      }
    }

    // 旧分组：playOnlineMusic（内部 saveSetting + playmusiclist）
    debugPrint('🎵 [RemotePlayback] 使用 playOnlineMusic API（旧分组）');
    final parts = musicName.split(' - ');
    final title = parts.isNotEmpty ? parts[0].trim() : musicName;
    final author =
        parts.length > 1 ? parts.sublist(1).join(' - ').trim() : '未知歌手';

    await _apiService.playOnlineMusic(
      did: _deviceId,
      musicUrl: url,
      musicTitle: title,
      musicAuthor: author,
    );
    _activeApiGroup = _PlaybackApiGroup.legacy;
    // 🎵 如果之前做了预暂停，检查状态，只在暂停时才补发恢复指令
    if (didPrePause) {
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        final status = await _apiService.getPlayerStatus(did: _deviceId);
        final playerStatus = status['status'];
        if (playerStatus == 2) {
          debugPrint('▶️ [RemotePlayback] 检测到暂停状态，补发恢复播放指令');
          await _apiService.resumeMusic(did: _deviceId);
        } else {
          debugPrint('✅ [RemotePlayback] 已在播放中，无需补发恢复指令');
        }
      } catch (_) {}
    }
  }

  Future<bool> _verifyPlayUrlApplied({
    required String expectedMusicName,
  }) async {
    try {
      final useNewGroup = await _shouldUsePlayUrlGroup();
      final expected = expectedMusicName.trim();
      final probeSchedule = <Duration>[
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 900),
        const Duration(milliseconds: 1400),
      ];

      Duration waited = Duration.zero;
      String current = '';
      bool isPlaying = false;

      for (final delay in probeSchedule) {
        final waitFor = delay - waited;
        if (waitFor > Duration.zero) {
          await Future.delayed(waitFor);
        }
        waited = delay;

        if (useNewGroup) {
          try {
            final raw = await _apiService.getPlayerStatus(did: _deviceId);
            final status = _mapPlayerStatusToIsPlaying(raw);
            final detail = raw['play_song_detail'] as Map<String, dynamic>?;
            final positionMs = detail?['position'] as int?;
            final positionSec =
                positionMs != null ? (positionMs / 1000).round() : 0;
            if (status && positionSec >= 1) {
              return true;
            }
            isPlaying = status;
            current = (detail?['title'] ?? '').toString().trim();
          } catch (_) {
            final status = await _apiService.getCurrentPlaying(did: _deviceId);
            isPlaying = status['is_playing'] == true;
            current = (status['cur_music'] ?? '').toString().trim();
            final matched =
                current.isNotEmpty &&
                _normalizeSongName(current) == _normalizeSongName(expected);
            if (matched || isPlaying) {
              return true;
            }
          }
        } else {
          final status = await _apiService.getCurrentPlaying(did: _deviceId);
          isPlaying = status['is_playing'] == true;
          current = (status['cur_music'] ?? '').toString().trim();
          final matched =
              current.isNotEmpty &&
              _normalizeSongName(current) == _normalizeSongName(expected);
          if (matched || isPlaying) {
            return true;
          }
        }
      }

      debugPrint(
        '⚠️ [RemotePlayback] playUrl 校验未通过: cur_music="$current", is_playing=$isPlaying, expected="$expected"',
      );
      return false;
    } catch (e) {
      debugPrint('⚠️ [RemotePlayback] playUrl 校验失败: $e');
      return false;
    }
  }

  String _normalizeSongName(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// 🔧 更新封面图 URL
  void updateAlbumCover(String? coverUrl) {
    _albumCoverUrl = coverUrl;
    debugPrint('🖼️ [RemotePlayback] 封面图已更新: $coverUrl');
  }

  @override
  Future<int> getVolume() async {
    try {
      final response = await _apiService.getVolume(did: _deviceId);
      return response['volume'] as int? ?? 50;
    } catch (e) {
      debugPrint('❌ [RemotePlayback] 获取音量失败: $e');
      return 50;
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('🎵 [RemotePlayback] 释放资源 (设备: $_deviceId)');

    // 🔧 切换回本地模式时,重新启用本地播放器监听
    if (_audioHandler != null) {
      _audioHandler!.setListenToLocalPlayer(true);
      debugPrint('🔧 [RemotePlayback] 已重新启用本地播放器监听');

      // 🎯 恢复本地播放模式
      _audioHandler!.setRemotePlayback(false);
      debugPrint('🔧 [RemotePlayback] 已恢复本地播放模式');
    }
  }
}
