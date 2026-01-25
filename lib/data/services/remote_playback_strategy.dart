import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../models/playing_music.dart';
import 'music_api_service.dart';
import 'playback_strategy.dart';
import 'audio_handler_service.dart';

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

    // 🔧 连接通知栏控制按钮到远程播放
    if (_audioHandler != null) {
      _audioHandler!.onPlay = () {
        debugPrint('🎵 [RemotePlayback] 通知栏触发播放');
        play();
      };
      _audioHandler!.onPause = () {
        debugPrint('🎵 [RemotePlayback] 通知栏触发暂停');
        pause();
      };
      _audioHandler!.onNext = () {
        debugPrint('🎵 [RemotePlayback] 通知栏触发下一首');
        next();
      };
      _audioHandler!.onPrevious = () {
        debugPrint('🎵 [RemotePlayback] 通知栏触发上一首');
        previous();
      };
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
      _audioHandler!.playbackState.add(PlaybackState(
        processingState: AudioProcessingState.loading,
        playing: false,
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
      ));

      debugPrint('🔧 [RemotePlayback] 已初始化通知栏为远程播放模式');
    }
  }

  @override
  bool get isLocalMode => false;

  @override
  Future<void> play() async {
    debugPrint('🎵 [RemotePlayback] 执行播放 (设备: $_deviceId)');
    await _apiService.resumeMusic(did: _deviceId);

    // 🔧 获取最新状态并更新通知栏
    await _updateNotificationState();
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [RemotePlayback] 执行暂停 (设备: $_deviceId)');
    await _apiService.pauseMusic(did: _deviceId);

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
  }) async {
    debugPrint('🎵 [RemotePlayback] 播放音乐: $musicName (设备: $_deviceId)');

    // 如果有直链URL，使用在线播放
    if (url != null && url.isNotEmpty) {
      debugPrint('🎵 [RemotePlayback] 使用在线播放链接');

      // 从 musicName 解析出歌曲名和歌手名（格式: "歌名 - 歌手"）
      final parts = musicName.split(' - ');
      final title = parts.isNotEmpty ? parts[0] : musicName;
      final author = parts.length > 1 ? parts[1] : '未知歌手';

      await _apiService.playOnlineMusic(
        did: _deviceId,
        musicUrl: url,
        musicTitle: title,
        musicAuthor: author,
      );
    } else {
      // 否则，使用音乐名称播放（服务器本地音乐）
      debugPrint('🎵 [RemotePlayback] 播放服务器本地音乐');
      await _apiService.playMusic(did: _deviceId, musicName: musicName);
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
  }

  @override
  Future<PlayingMusic?> getCurrentStatus() async {
    try {
      final response = await _apiService.getCurrentPlaying(did: _deviceId);
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
        _audioHandler!.playbackState.add(_audioHandler!.playbackState.value.copyWith(
          playing: status.isPlaying,
          processingState: AudioProcessingState.ready, // 🔧 设置为 ready 才能显示进度条
          updatePosition: Duration(seconds: status.offset), // 🔧 更新当前进度
          bufferedPosition: Duration(seconds: status.duration), // 🔧 设置缓冲进度
          controls: [
            MediaControl.skipToPrevious,
            status.isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
          ],
        ));
        debugPrint('🔧 [RemotePlayback] 已更新通知栏: playing=${status.isPlaying}, position=${status.offset}s/${status.duration}s, cover=$_albumCoverUrl');
      }

      return status;
    } catch (e) {
      debugPrint('❌ [RemotePlayback] 获取播放状态失败: $e');
      return null;
    }
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
