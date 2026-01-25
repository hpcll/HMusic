import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/direct_mode_playlist_service.dart';
import '../../data/models/local_playlist_model.dart';
import '../../core/utils/playlist_refresh_controller.dart';

/// 直连模式歌单状态
class DirectModePlaylistState {
  final List<LocalPlaylistModel> playlists;
  final bool isLoading;
  final String? error;

  const DirectModePlaylistState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  DirectModePlaylistState copyWith({
    List<LocalPlaylistModel>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return DirectModePlaylistState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 直连模式歌单管理器
///
/// 包装 DirectModePlaylistService，提供 Riverpod 响应式状态管理
class DirectModePlaylistNotifier extends StateNotifier<DirectModePlaylistState> {
  final DirectModePlaylistService _service = DirectModePlaylistService();
  StreamSubscription? _refreshSubscription;

  DirectModePlaylistNotifier() : super(const DirectModePlaylistState()) {
    _init();
  }

  /// 初始化
  Future<void> _init() async {
    // 加载歌单
    await refreshPlaylists();

    // 监听刷新事件
    _refreshSubscription = PlaylistRefreshController.stream.listen((_) {
      debugPrint('🔄 [DirectModePlaylistProvider] 收到刷新事件');
      refreshPlaylists();
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  /// 刷新歌单列表
  Future<void> refreshPlaylists() async {
    try {
      state = state.copyWith(isLoading: true);

      final playlists = await _service.getAllPlaylists();

      debugPrint('✅ [DirectModePlaylistProvider] 加载了 ${playlists.length} 个歌单');
      for (final p in playlists) {
        debugPrint('   - "${p.name}": ${p.songs.length} 首歌曲');
      }

      state = state.copyWith(
        playlists: playlists,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      debugPrint('❌ [DirectModePlaylistProvider] 加载歌单失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 创建歌单
  Future<void> createPlaylist(String name) async {
    try {
      state = state.copyWith(isLoading: true);

      final success = await _service.createPlaylist(name: name);
      if (!success) {
        throw Exception('歌单名称已存在');
      }

      await refreshPlaylists();
      debugPrint('✅ [DirectModePlaylistProvider] 创建歌单: $name');
    } catch (e) {
      debugPrint('❌ [DirectModePlaylistProvider] 创建歌单失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 删除歌单
  Future<void> deletePlaylist(String playlistName) async {
    try {
      state = state.copyWith(isLoading: true);

      // 找到歌单 ID
      final playlist = await _service.getPlaylistByName(playlistName);
      if (playlist == null) {
        throw Exception('歌单不存在');
      }

      final success = await _service.deletePlaylist(playlist.id);
      if (!success) {
        throw Exception('删除失败');
      }

      await refreshPlaylists();
      debugPrint('✅ [DirectModePlaylistProvider] 删除歌单: $playlistName');
    } catch (e) {
      debugPrint('❌ [DirectModePlaylistProvider] 删除歌单失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 添加歌曲到歌单
  Future<void> addSongToPlaylist({
    required String playlistName,
    required String songName,
  }) async {
    try {
      final playlist = await _service.getPlaylistByName(playlistName);
      if (playlist == null) {
        throw Exception('歌单不存在');
      }

      final success = await _service.addSongToPlaylist(playlist.id, songName);
      if (!success) {
        throw Exception('歌曲已在歌单中');
      }

      await refreshPlaylists();
      debugPrint('✅ [DirectModePlaylistProvider] 添加歌曲到 $playlistName: $songName');
    } catch (e) {
      debugPrint('❌ [DirectModePlaylistProvider] 添加歌曲失败: $e');
      rethrow;
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// 直连模式歌单 Provider
final directModePlaylistProvider =
    StateNotifierProvider<DirectModePlaylistNotifier, DirectModePlaylistState>((ref) {
  return DirectModePlaylistNotifier();
});
