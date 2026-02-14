import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/playlist_queue.dart';
import '../../data/models/playlist_item.dart';

/// 播放队列状态
class PlaybackQueueState {
  final PlaylistQueue? queue;
  final bool isLoading;
  final String? error;

  const PlaybackQueueState({
    this.queue,
    this.isLoading = false,
    this.error,
  });

  PlaybackQueueState copyWith({
    PlaylistQueue? queue,
    bool? isLoading,
    String? error,
  }) {
    return PlaybackQueueState(
      queue: queue ?? this.queue,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 播放队列管理器
/// 用于管理当前播放的队列（支持搜索结果、音乐库、收藏等）
class PlaybackQueueNotifier extends StateNotifier<PlaybackQueueState> {
  PlaybackQueueNotifier() : super(const PlaybackQueueState()) {
    _init();
  }

  static const String _cacheKey = 'playback_queue_cache';

  /// 初始化：恢复缓存的队列
  Future<void> _init() async {
    await _restoreFromCache();
  }

  /// 设置新的播放队列
  ///
  /// [queueName] 队列名称，如 "搜索结果: 周杰伦"
  /// [source] 队列来源类型
  /// [items] 播放列表项
  /// [startIndex] 开始播放的索引（默认0）
  void setQueue({
    required String queueName,
    required PlaylistSource source,
    required List<PlaylistItem> items,
    int startIndex = 0,
  }) {
    debugPrint('🎵 [PlaybackQueue] 设置新队列: $queueName, ${items.length}首歌, 从第${startIndex + 1}首开始');

    if (items.isEmpty) {
      debugPrint('⚠️ [PlaybackQueue] 队列为空，忽略');
      return;
    }

    // 确保索引有效
    final validIndex = startIndex.clamp(0, items.length - 1);

    final queue = PlaylistQueue(
      queueId: DateTime.now().millisecondsSinceEpoch.toString(),
      queueName: queueName,
      source: source,
      items: items,
      currentIndex: validIndex,
      playMode: state.queue?.playMode ?? QueuePlayMode.listLoop, // 保持之前的播放模式
    );

    state = state.copyWith(queue: queue, error: null);
    _saveToCache(); // 保存到缓存
  }

  /// 切换到指定索引
  void jumpToIndex(int index) {
    if (state.queue == null || state.queue!.items.isEmpty) {
      debugPrint('⚠️ [PlaybackQueue] 队列为空，无法跳转');
      return;
    }

    if (index < 0 || index >= state.queue!.items.length) {
      debugPrint('⚠️ [PlaybackQueue] 索引无效: $index');
      return;
    }

    debugPrint('🎵 [PlaybackQueue] 跳转到索引: $index');
    state = state.copyWith(
      queue: state.queue!.copyWith(currentIndex: index),
    );
    _saveToCache();
  }

  /// 获取下一首歌曲
  ///
  /// 返回 null 表示没有下一首（顺序播放模式且已到末尾）
  PlaylistItem? next() {
    if (state.queue == null || state.queue!.items.isEmpty) {
      debugPrint('⚠️ [PlaybackQueue] 队列为空，无法获取下一首');
      return null;
    }

    final nextIndex = state.queue!.getNextIndex();
    if (nextIndex == null) {
      debugPrint('⚠️ [PlaybackQueue] 已到达队列末尾（顺序播放模式）');
      return null;
    }

    debugPrint('🎵 [PlaybackQueue] 下一首: 索引 $nextIndex (${state.queue!.playMode.displayName})');
    state = state.copyWith(
      queue: state.queue!.copyWith(currentIndex: nextIndex),
    );
    _saveToCache();

    return state.queue!.items[nextIndex];
  }

  /// 获取上一首歌曲
  ///
  /// 返回 null 表示没有上一首（顺序播放模式且已到开头）
  PlaylistItem? previous() {
    if (state.queue == null || state.queue!.items.isEmpty) {
      debugPrint('⚠️ [PlaybackQueue] 队列为空，无法获取上一首');
      return null;
    }

    final prevIndex = state.queue!.getPreviousIndex();
    if (prevIndex == null) {
      debugPrint('⚠️ [PlaybackQueue] 已到达队列开头（顺序播放模式）');
      return null;
    }

    debugPrint('🎵 [PlaybackQueue] 上一首: 索引 $prevIndex (${state.queue!.playMode.displayName})');
    state = state.copyWith(
      queue: state.queue!.copyWith(currentIndex: prevIndex),
    );
    _saveToCache();

    return state.queue!.items[prevIndex];
  }

  /// 切换播放模式
  void togglePlayMode() {
    if (state.queue == null) {
      debugPrint('⚠️ [PlaybackQueue] 队列为空，无法切换播放模式');
      return;
    }

    final modes = QueuePlayMode.values;
    final currentModeIndex = modes.indexOf(state.queue!.playMode);
    final nextMode = modes[(currentModeIndex + 1) % modes.length];

    debugPrint('🎵 [PlaybackQueue] 切换播放模式: ${state.queue!.playMode.displayName} -> ${nextMode.displayName}');

    state = state.copyWith(
      queue: state.queue!.copyWith(playMode: nextMode),
    );
    _saveToCache();
  }

  /// 设置播放模式
  void setPlayMode(QueuePlayMode mode) {
    if (state.queue == null) {
      debugPrint('⚠️ [PlaybackQueue] 队列为空，无法设置播放模式');
      return;
    }

    debugPrint('🎵 [PlaybackQueue] 设置播放模式: ${mode.displayName}');
    state = state.copyWith(
      queue: state.queue!.copyWith(playMode: mode),
    );
    _saveToCache();
  }

  /// 更新当前歌曲的歌词
  void updateCurrentLyrics(String lrc) {
    if (state.queue == null || state.queue!.currentItem == null) {
      debugPrint('⚠️ [PlaybackQueue] 无法更新歌词：队列为空');
      return;
    }

    final currentIndex = state.queue!.currentIndex;
    final updatedItem = state.queue!.items[currentIndex].copyWith(lrc: lrc);
    final updatedItems = List<PlaylistItem>.from(state.queue!.items);
    updatedItems[currentIndex] = updatedItem;

    debugPrint('📝 [PlaybackQueue] 已缓存歌词到队列');
    state = state.copyWith(
      queue: state.queue!.copyWith(items: updatedItems),
    );
    _saveToCache();
  }

  /// 更新当前歌曲的封面
  void updateCurrentCover(String coverUrl) {
    if (state.queue == null || state.queue!.currentItem == null) {
      debugPrint('⚠️ [PlaybackQueue] 无法更新封面：队列为空');
      return;
    }

    final currentIndex = state.queue!.currentIndex;
    final updatedItem = state.queue!.items[currentIndex].copyWith(coverUrl: coverUrl);
    final updatedItems = List<PlaylistItem>.from(state.queue!.items);
    updatedItems[currentIndex] = updatedItem;

    debugPrint('🖼️ [PlaybackQueue] 已缓存封面到队列');
    state = state.copyWith(
      queue: state.queue!.copyWith(items: updatedItems),
    );
    _saveToCache();
  }

  /// 更新当前歌曲的 duration（用于旧歌曲解析 URL 时获取到 duration 的场景）
  void updateCurrentDuration(int duration) {
    if (state.queue == null || state.queue!.currentItem == null) {
      debugPrint('⚠️ [PlaybackQueue] 无法更新 duration：队列为空');
      return;
    }

    final currentIndex = state.queue!.currentIndex;
    final updatedItem = state.queue!.items[currentIndex].copyWith(duration: duration);
    final updatedItems = List<PlaylistItem>.from(state.queue!.items);
    updatedItems[currentIndex] = updatedItem;

    debugPrint('🎯 [PlaybackQueue] 已更新当前歌曲 duration: ${duration}秒');
    state = state.copyWith(
      queue: state.queue!.copyWith(items: updatedItems),
    );
    _saveToCache();
  }

  /// 添加单首歌曲到队列末尾
  ///
  /// 如果队列不存在，会自动创建一个新队列
  void addToQueue(PlaylistItem item) {
    if (state.queue == null) {
      // 队列不存在，创建新队列
      debugPrint('🎵 [PlaybackQueue] 队列不存在，创建新队列');
      setQueue(
        queueName: '临时播放队列',
        source: PlaylistSource.customPlaylist,
        items: [item],
        startIndex: 0,
      );
      return;
    }

    // 检查是否已存在（避免重复添加）
    final exists = state.queue!.items.any(
      (existing) =>
          existing.title == item.title &&
          existing.artist == item.artist &&
          existing.sourceType == item.sourceType &&
          existing.platform == item.platform &&
          existing.songId == item.songId,
    );

    if (exists) {
      debugPrint('⚠️ [PlaybackQueue] 歌曲已在队列中: ${item.displayName}');
      return;
    }

    // 添加到队列末尾
    final updatedItems = List<PlaylistItem>.from(state.queue!.items)..add(item);
    debugPrint('✅ [PlaybackQueue] 添加到队列: ${item.displayName} (队列长度: ${updatedItems.length})');

    state = state.copyWith(
      queue: state.queue!.copyWith(items: updatedItems),
    );
    _saveToCache();
  }

  /// 清空队列
  void clearQueue() {
    debugPrint('🎵 [PlaybackQueue] 清空队列');
    state = const PlaybackQueueState();
    _clearCache();
  }

  /// 保存队列到缓存
  Future<void> _saveToCache() async {
    if (state.queue == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(state.queue!.toJson());
      await prefs.setString(_cacheKey, jsonStr);
      debugPrint('💾 [PlaybackQueue] 队列已保存到缓存');
    } catch (e) {
      debugPrint('❌ [PlaybackQueue] 保存队列失败: $e');
    }
  }

  /// 从缓存恢复队列
  Future<void> _restoreFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_cacheKey);

      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('⚠️ [PlaybackQueue] 没有缓存的队列');
        return;
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final queue = PlaylistQueue.fromJson(json);

      debugPrint('✅ [PlaybackQueue] 恢复队列: ${queue.queueName}, ${queue.items.length}首歌');
      state = state.copyWith(queue: queue);
    } catch (e) {
      debugPrint('❌ [PlaybackQueue] 恢复队列失败: $e');
      _clearCache(); // 清除损坏的缓存
    }
  }

  /// 清除缓存
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      debugPrint('🗑️ [PlaybackQueue] 缓存已清除');
    } catch (e) {
      debugPrint('❌ [PlaybackQueue] 清除缓存失败: $e');
    }
  }

  @override
  void dispose() {
    // 不需要特殊清理
    super.dispose();
  }
}

/// 播放队列 Provider
final playbackQueueProvider =
    StateNotifierProvider<PlaybackQueueNotifier, PlaybackQueueState>((ref) {
  return PlaybackQueueNotifier();
});
