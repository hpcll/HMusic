import '../models/playing_music.dart';

/// 播放策略抽象接口
/// 定义统一的播放控制方法，由远程控制和本地播放分别实现
abstract class PlaybackStrategy {
  /// 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seekTo(int seconds);
  Future<void> setVolume(int volume);

  /// 播放指定音乐
  /// [musicName] 歌曲名称（格式：歌名 - 歌手）
  /// [url] 可选的直接播放链接（在线音乐）
  /// [platform] 音乐平台（用于在线音乐）
  /// [songId] 歌曲ID（用于在线音乐）
  Future<void> playMusic({
    required String musicName,
    String? url,
    String? platform,
    String? songId,
  });

  /// 播放音乐列表
  Future<void> playMusicList({
    required String listName,
    required String musicName,
  });

  /// 获取当前播放状态
  /// 返回 PlayingMusic 对象或 null
  Future<PlayingMusic?> getCurrentStatus();

  /// 获取当前音量
  Future<int> getVolume();

  /// 释放资源
  Future<void> dispose();

  /// 是否为本地播放模式
  bool get isLocalMode;
}
