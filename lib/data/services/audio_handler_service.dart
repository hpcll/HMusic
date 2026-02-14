import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

/// 音频后台服务处理器
/// 负责管理系统媒体通知和后台播放
class AudioHandlerService extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player;

  // 🔧 暴露 AudioPlayer 实例,供 LocalPlaybackStrategy 共享使用
  AudioPlayer get player => _player;

  MediaItem? _currentMediaItem;

  // 🔧 添加回调函数,用于通知栏控制
  Function()? onNext;
  Function()? onPrevious;
  Function(Duration)? onSeek;
  Function()? onPlay;   // 🔧 添加播放回调
  Function()? onPause;  // 🔧 添加暂停回调

  // 🔧 控制是否监听本地播放器(远程播放时需要禁用)
  bool _listenToLocalPlayer = true;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _bufferedPositionSubscription;
  StreamSubscription? _speedSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _processingStateSubscription;

  // 🎯 远程播放模式标志（直连模式/xiaomusic远程播放）
  // 保留字段供 setRemotePlayback() 兼容调用，但不再用于暂停判断
  bool _isRemotePlayback = false;

  AudioHandlerService({required AudioPlayer player}) : _player = player {
    _init();
  }

  /// 🔧 设置是否监听本地播放器
  void setListenToLocalPlayer(bool listen) {
    if (_listenToLocalPlayer == listen) return;

    _listenToLocalPlayer = listen;
    debugPrint('🔧 [AudioHandler] ${listen ? "启用" : "禁用"}本地播放器监听');

    if (listen) {
      _startListeningToPlayer();
    } else {
      _stopListeningToPlayer();
    }
  }

  /// 🎯 设置远程播放模式
  /// 远程播放时，系统触发的暂停不会影响音箱播放
  void setRemotePlayback(bool isRemote) {
    if (_isRemotePlayback == isRemote) return;

    _isRemotePlayback = isRemote;
    debugPrint('🔧 [AudioHandler] ${isRemote ? "启用" : "禁用"}远程播放模式');
  }

  void _init() {
    debugPrint('🧩 [AudioHandler] 初始化');
    // 初始状态
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const [MediaControl.play],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      ),
    );

    // 启动本地播放器监听
    _startListeningToPlayer();
  }

  /// 🔧 启动监听本地播放器
  void _startListeningToPlayer() {
    _stopListeningToPlayer(); // 先停止旧的监听

    // 监听播放状态变化
    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      if (!_listenToLocalPlayer) return; // 远程模式跳过

      debugPrint('🧩 [AudioHandler] playerState: playing=${playerState.playing}, state=${playerState.processingState}');
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      // 🔧 将 ready 和 completed 状态都映射为 ready,确保通知栏正常显示
      final mappedState = _mapProcessingState(processingState);
      final effectiveState = (mappedState == AudioProcessingState.ready ||
                             mappedState == AudioProcessingState.completed)
          ? AudioProcessingState.ready
          : mappedState;

      playbackState.add(playbackState.value.copyWith(
        playing: isPlaying,
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: effectiveState,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
    });

    // 监听播放进度
    _positionSubscription = _player.positionStream.listen((position) {
      if (!_listenToLocalPlayer) return; // 远程模式跳过

      debugPrint('🧩 [AudioHandler] position: ${position.inMilliseconds}ms');
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
    });

    // 监听缓冲进度和倍速变化以同步到系统
    _bufferedPositionSubscription = _player.bufferedPositionStream.listen((bp) {
      if (!_listenToLocalPlayer) return; // 远程模式跳过

      debugPrint('🧩 [AudioHandler] buffered: ${bp.inMilliseconds}ms');
      playbackState.add(playbackState.value.copyWith(bufferedPosition: bp));
    });

    _speedSubscription = _player.speedStream.listen((sp) {
      if (!_listenToLocalPlayer) return; // 远程模式跳过

      debugPrint('🧩 [AudioHandler] speed: $sp');
      playbackState.add(playbackState.value.copyWith(speed: sp));
    });

    // 监听时长变化，及时更新媒体项以便控制中心显示进度条
    _durationSubscription = _player.durationStream.listen((d) {
      if (!_listenToLocalPlayer) return; // 远程模式跳过

      if (_currentMediaItem != null && d != null) {
        _currentMediaItem = _currentMediaItem!.copyWith(duration: d);
        mediaItem.add(_currentMediaItem);
      }
    });

    // 播放完成自动下一首
    _processingStateSubscription = _player.processingStateStream.listen((state) {
      if (!_listenToLocalPlayer) return; // 远程模式跳过

      debugPrint('🧩 [AudioHandler] processingState: $state');
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  /// 🔧 停止监听本地播放器
  void _stopListeningToPlayer() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _bufferedPositionSubscription?.cancel();
    _speedSubscription?.cancel();
    _durationSubscription?.cancel();
    _processingStateSubscription?.cancel();

    _playerStateSubscription = null;
    _positionSubscription = null;
    _bufferedPositionSubscription = null;
    _speedSubscription = null;
    _durationSubscription = null;
    _processingStateSubscription = null;
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Future<void> setMediaItem({
    required String title,
    String? artist,
    String? album,
    String? artUri,
    Duration? duration,
  }) async {
    _currentMediaItem = MediaItem(
      id: title,
      title: title,
      artist: artist ?? '未知艺术家',
      album: album ?? '本地播放',
      artUri: artUri != null && artUri.isNotEmpty ? Uri.parse(artUri) : null,
      duration: duration,
    );

    mediaItem.add(_currentMediaItem);
    debugPrint('🎵 [AudioHandler] 更新媒体信息: $title - $artist');
  }

  @override
  Future<void> play() async {
    debugPrint('🎵 [AudioHandler] 播放');

    // 🔧 立即更新播放状态（在调用回调前），避免按钮闪烁
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
      ],
    ));

    // 🔧 如果有外部回调(远程播放),调用回调而不是本地播放器
    if (onPlay != null) {
      onPlay!();
      return;
    }

    // 否则使用本地播放器
    await _player.play();
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [AudioHandler] 暂停');

    // 🔧 立即更新暂停状态（在调用回调前），避免按钮闪烁
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.ready,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
    ));

    // 🔧 有外部回调时（远程/直连模式），调用回调处理暂停
    if (onPause != null) {
      onPause!();
      return;
    }

    // 否则使用本地播放器
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    debugPrint('🎵 [AudioHandler] 停止');
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('🎵 [AudioHandler] 跳转到: ${position.inSeconds}s');
    await _player.seek(position);

    // 🔧 调用回调通知上层
    if (onSeek != null) {
      onSeek!(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('🎵 [AudioHandler] 下一首');
    // 🔧 调用回调函数
    if (onNext != null) {
      onNext!();
    } else {
      debugPrint('⚠️ [AudioHandler] onNext 回调未设置');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('🎵 [AudioHandler] 上一首');
    // 🔧 调用回调函数
    if (onPrevious != null) {
      onPrevious!();
    } else {
      debugPrint('⚠️ [AudioHandler] onPrevious 回调未设置');
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    debugPrint('🎵 [AudioHandler] 自定义操作: $name');
    return super.customAction(name, extras);
  }

  Future<void> clearNotification() async {
    await stop();
    mediaItem.add(null);
  }
}
