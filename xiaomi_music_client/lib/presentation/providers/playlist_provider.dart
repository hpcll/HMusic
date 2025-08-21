import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/playlist.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';
import '../../data/adapters/playlist_adapter.dart';

class PlaylistState {
  final List<Playlist> playlists;
  final bool isLoading;
  final String? error;
  final String? currentPlaylist;
  final List<String> currentPlaylistMusics;
  // 服务端真实可删除的播放列表名称
  final Set<String> deletablePlaylists;

  const PlaylistState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
    this.currentPlaylist,
    this.currentPlaylistMusics = const [],
    this.deletablePlaylists = const {},
  });

  PlaylistState copyWith({
    List<Playlist>? playlists,
    bool? isLoading,
    String? error,
    String? currentPlaylist,
    List<String>? currentPlaylistMusics,
    Set<String>? deletablePlaylists,
  }) {
    return PlaylistState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPlaylist: currentPlaylist ?? this.currentPlaylist,
      currentPlaylistMusics:
          currentPlaylistMusics ?? this.currentPlaylistMusics,
      deletablePlaylists: deletablePlaylists ?? this.deletablePlaylists,
    );
  }
}

class PlaylistNotifier extends StateNotifier<PlaylistState> {
  final Ref ref;

  PlaylistNotifier(this.ref) : super(const PlaylistState()) {
    // 禁用自动加载播放列表，避免在未登录时进行网络请求
    debugPrint('PlaylistProvider: 自动加载已禁用，等待用户手动触发');

    // 监听认证状态变化，但不再自动加载
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        debugPrint('PlaylistProvider: 用户已认证，但不会自动加载播放列表');
      }
      if (next is AuthInitial) {
        state = const PlaylistState();
      }
    });
  }

  Future<void> _loadPlaylists() async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      final resp = await apiService.getPlaylistNames();
      final fullMap = await apiService.getMusicList();
      final playlists = PlaylistAdapter.mergeToPlaylists(resp, fullMap);
      final deletable = PlaylistAdapter.extractNames(resp).toSet();

      state = state.copyWith(
        playlists: playlists,
        isLoading: false,
        error: null,
        deletablePlaylists: deletable,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refreshPlaylists() async {
    await _loadPlaylists();
  }

  Future<void> loadPlaylistMusics(String playlistName) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      // 优先从 /musiclist 的聚合结果中拿（包含很多内置类别）
      final full = await apiService.getMusicList();
      List<String>? fromFull;
      final byKey = full[playlistName];
      if (byKey is List) {
        fromFull = byKey.map((e) => e.toString()).toList();
      }

      List<String> musics;
      if (fromFull != null) {
        musics = fromFull;
      } else {
        final response = await apiService.getPlaylistMusics(playlistName);
        // 兼容不同返回字段：music_list / musics / songs
        final dynamicList =
            (response['music_list'] as List?) ??
            (response['musics'] as List?) ??
            (response['songs'] as List?) ??
            [];
        musics = dynamicList.map((m) => m.toString()).toList();
      }

      state = state.copyWith(
        currentPlaylist: playlistName,
        currentPlaylistMusics: musics,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> playPlaylist({
    required String deviceId,
    required String playlistName,
    String? specificMusic,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      await apiService.playMusicList(
        deviceId: deviceId,
        playlistName: playlistName,
        musicName: specificMusic,
      );

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // 触发整表网络下载
  Future<void> downloadPlaylist(String playlistName, {String? url}) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;
    try {
      state = state.copyWith(isLoading: true);
      final resp = await apiService.downloadPlaylist(
        playlistName: playlistName,
        url: url,
      );
      // 简单成功判断
      if (resp['ret'] == 'OK' || resp['success'] == true) {
        state = state.copyWith(isLoading: false);
      } else {
        state = state.copyWith(isLoading: false, error: resp.toString());
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createPlaylist(String name) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      await apiService.createPlaylist(name);
      await _loadPlaylists(); // 重新加载播放列表

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deletePlaylist(String name) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      await apiService.deletePlaylist(name);
      await _loadPlaylists(); // 重新加载播放列表

      if (state.currentPlaylist == name) {
        state = state.copyWith(
          currentPlaylist: null,
          currentPlaylistMusics: [],
        );
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final playlistProvider = StateNotifierProvider<PlaylistNotifier, PlaylistState>(
  (ref) {
    return PlaylistNotifier(ref);
  },
);
