import 'dart:math';
import 'package:json_annotation/json_annotation.dart';
import 'playlist_item.dart';

part 'playlist_queue.g.dart';

/// 播放列表来源类型
enum PlaylistSource {
  @JsonValue('music_library')
  musicLibrary, // 音乐库

  @JsonValue('search_result')
  searchResult, // 搜索结果

  @JsonValue('favorites')
  favorites, // 收藏夹

  @JsonValue('custom_playlist')
  customPlaylist, // 自定义歌单
}

/// 队列播放模式
/// 使用独立的枚举避免与 PlaybackProvider 的 PlayMode 冲突
enum QueuePlayMode {
  @JsonValue('list_loop')
  listLoop, // 列表循环

  @JsonValue('single_loop')
  singleLoop, // 单曲循环

  @JsonValue('random')
  random, // 随机播放

  @JsonValue('sequence')
  sequence, // 顺序播放
}

/// 播放队列
@JsonSerializable(explicitToJson: true)
class PlaylistQueue {
  final String queueId; // 队列ID（用于识别）
  final String queueName; // 队列名称（如"搜索结果", "我的音乐库"）
  final PlaylistSource source; // 来源类型
  final List<PlaylistItem> items; // 队列项目
  final int currentIndex; // 当前播放索引
  final QueuePlayMode playMode; // 播放模式

  const PlaylistQueue({
    required this.queueId,
    required this.queueName,
    required this.source,
    required this.items,
    required this.currentIndex,
    required this.playMode,
  });

  factory PlaylistQueue.fromJson(Map<String, dynamic> json) =>
      _$PlaylistQueueFromJson(json);

  Map<String, dynamic> toJson() => _$PlaylistQueueToJson(this);

  /// 获取当前播放的歌曲
  PlaylistItem? get currentItem {
    if (items.isEmpty || currentIndex < 0 || currentIndex >= items.length) {
      return null;
    }
    return items[currentIndex];
  }

  /// 获取下一首的索引（根据播放模式）
  int? getNextIndex() {
    if (items.isEmpty) return null;

    switch (playMode) {
      case QueuePlayMode.singleLoop:
        return currentIndex; // 单曲循环不变

      case QueuePlayMode.random:
        // 随机播放，但避免重复当前歌曲（除非只有一首）
        if (items.length == 1) return 0;
        int nextIndex;
        do {
          nextIndex = Random().nextInt(items.length);
        } while (nextIndex == currentIndex);
        return nextIndex;

      case QueuePlayMode.sequence:
        // 顺序播放到最后停止
        if (currentIndex >= items.length - 1) return null;
        return currentIndex + 1;

      case QueuePlayMode.listLoop:
      default:
        // 列表循环
        return (currentIndex + 1) % items.length;
    }
  }

  /// 获取上一首的索引（根据播放模式）
  int? getPreviousIndex() {
    if (items.isEmpty) return null;

    switch (playMode) {
      case QueuePlayMode.singleLoop:
        return currentIndex; // 单曲循环不变

      case QueuePlayMode.random:
        // 随机播放
        if (items.length == 1) return 0;
        int prevIndex;
        do {
          prevIndex = Random().nextInt(items.length);
        } while (prevIndex == currentIndex);
        return prevIndex;

      case QueuePlayMode.sequence:
        // 顺序播放
        if (currentIndex <= 0) return null;
        return currentIndex - 1;

      case QueuePlayMode.listLoop:
      default:
        // 列表循环
        return (currentIndex - 1 + items.length) % items.length;
    }
  }

  /// 复制并更新部分字段
  PlaylistQueue copyWith({
    String? queueId,
    String? queueName,
    PlaylistSource? source,
    List<PlaylistItem>? items,
    int? currentIndex,
    QueuePlayMode? playMode,
  }) {
    return PlaylistQueue(
      queueId: queueId ?? this.queueId,
      queueName: queueName ?? this.queueName,
      source: source ?? this.source,
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      playMode: playMode ?? this.playMode,
    );
  }

  @override
  String toString() {
    return 'PlaylistQueue(queueName: $queueName, source: $source, itemsCount: ${items.length}, currentIndex: $currentIndex, playMode: $playMode)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PlaylistQueue &&
        other.queueId == queueId &&
        other.queueName == queueName &&
        other.source == source &&
        other.currentIndex == currentIndex &&
        other.playMode == playMode;
  }

  @override
  int get hashCode {
    return Object.hash(
      queueId,
      queueName,
      source,
      currentIndex,
      playMode,
    );
  }
}

/// 播放模式扩展（用于UI显示）
extension QueuePlayModeExtension on QueuePlayMode {
  String get displayName {
    switch (this) {
      case QueuePlayMode.listLoop:
        return '列表循环';
      case QueuePlayMode.singleLoop:
        return '单曲循环';
      case QueuePlayMode.random:
        return '随机播放';
      case QueuePlayMode.sequence:
        return '顺序播放';
    }
  }

  String get icon {
    switch (this) {
      case QueuePlayMode.listLoop:
        return '🔁'; // 列表循环
      case QueuePlayMode.singleLoop:
        return '🔂'; // 单曲循环
      case QueuePlayMode.random:
        return '🔀'; // 随机播放
      case QueuePlayMode.sequence:
        return '▶️'; // 顺序播放
    }
  }
}

/// 播放列表来源扩展（用于UI显示）
extension PlaylistSourceExtension on PlaylistSource {
  String get displayName {
    switch (this) {
      case PlaylistSource.musicLibrary:
        return '音乐库';
      case PlaylistSource.searchResult:
        return '搜索结果';
      case PlaylistSource.favorites:
        return '收藏夹';
      case PlaylistSource.customPlaylist:
        return '自定义歌单';
    }
  }
}
