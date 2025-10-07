import 'package:flutter/foundation.dart';
import '../models/playing_music.dart';
import 'music_api_service.dart';
import 'playback_strategy.dart';

/// 远程播放策略实现
/// 通过API控制播放设备播放音乐
class RemotePlaybackStrategy implements PlaybackStrategy {
  final MusicApiService _apiService;
  final String _deviceId;

  RemotePlaybackStrategy({
    required MusicApiService apiService,
    required String deviceId,
  }) : _apiService = apiService,
       _deviceId = deviceId;

  @override
  bool get isLocalMode => false;

  @override
  Future<void> play() async {
    debugPrint('🎵 [RemotePlayback] 执行播放 (设备: $_deviceId)');
    await _apiService.resumeMusic(did: _deviceId);
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [RemotePlayback] 执行暂停 (设备: $_deviceId)');
    await _apiService.pauseMusic(did: _deviceId);
  }

  @override
  Future<void> next() async {
    debugPrint('🎵 [RemotePlayback] 播放下一首 (设备: $_deviceId)');
    await _apiService.executeCommand(did: _deviceId, command: '下一首');
  }

  @override
  Future<void> previous() async {
    debugPrint('🎵 [RemotePlayback] 播放上一首 (设备: $_deviceId)');
    await _apiService.executeCommand(did: _deviceId, command: '上一首');
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
      return PlayingMusic.fromJson(response);
    } catch (e) {
      debugPrint('❌ [RemotePlayback] 获取播放状态失败: $e');
      return null;
    }
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
    // 远程控制不需要释放本地资源
  }
}
