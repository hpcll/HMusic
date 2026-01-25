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
    // 监听认证状态变化，在用户登录后自动加载播放列表
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is AuthAuthenticated && previous is! AuthAuthenticated) {
        debugPrint('PlaylistProvider: 用户已认证，自动加载播放列表');
        // 延迟一点时间确保认证完全完成
        Future.delayed(const Duration(milliseconds: 500), () {
          refreshPlaylists();
        });
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

      // 🔧 并行请求两个 API，提升加载速度
      final results = await Future.wait([
        apiService.getPlaylistNames(),
        apiService.getMusicList(),
      ]);
      final resp = results[0];  // dynamic 类型，可能是 List 或 Map
      final fullMap = results[1] as Map<String, dynamic>;

      // 🔧 添加调试日志
      debugPrint('📋 [PlaylistProvider] getPlaylistNames响应: $resp');
      debugPrint('📋 [PlaylistProvider] getMusicList返回 ${fullMap.keys.length} 个键:');
      for (final key in fullMap.keys) {
        final value = fullMap[key];
        final count = value is List ? value.length : 0;
        debugPrint('   - "$key": $count 首歌曲 (类型: ${value.runtimeType})');
      }

      final playlists = PlaylistAdapter.mergeToPlaylists(resp, fullMap);
      final deletable = PlaylistAdapter.extractNames(resp).toSet();

      debugPrint('📋 [PlaylistProvider] 合并后的播放列表:');
      for (final p in playlists) {
        debugPrint('   - "${p.name}": ${p.count ?? 0} 首歌曲');
      }
      debugPrint('📋 [PlaylistProvider] 可删除播放列表: $deletable');

      state = state.copyWith(
        playlists: playlists,
        isLoading: false,
        error: null,
        deletablePlaylists: deletable,
      );
    } catch (e) {
      debugPrint('❌ [PlaylistProvider] _loadPlaylists失败: $e');
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

      debugPrint('📋 [PlaylistProvider] loadPlaylistMusics 开始: $playlistName');

      // 优先从 /musiclist 的聚合结果中拿（包含很多内置类别）
      final full = await apiService.getMusicList();

      debugPrint('📋 [PlaylistProvider] /musiclist 返回的所有键: ${full.keys.toList()}');

      List<String>? fromFull;
      final byKey = full[playlistName];

      debugPrint('📋 [PlaylistProvider] 查找键 "$playlistName": ${byKey != null ? "找到" : "未找到"}');
      if (byKey != null) {
        debugPrint('📋 [PlaylistProvider] 值类型: ${byKey.runtimeType}');
      }

      if (byKey is List) {
        fromFull = byKey.map((e) => e.toString()).toList();
        debugPrint('📋 [PlaylistProvider] 从 /musiclist 获取到 ${fromFull.length} 首歌曲');
      }

      List<String> musics;
      if (fromFull != null) {
        musics = fromFull;
      } else {
        debugPrint('📋 [PlaylistProvider] /musiclist 未找到，尝试 getPlaylistMusics API');
        final response = await apiService.getPlaylistMusics(playlistName);
        debugPrint('📋 [PlaylistProvider] getPlaylistMusics 响应: $response');

        // 兼容不同返回字段：music_list / musics / songs
        final dynamicList =
            (response['music_list'] as List?) ??
            (response['musics'] as List?) ??
            (response['songs'] as List?) ??
            [];
        musics = dynamicList.map((m) => m.toString()).toList();
        debugPrint('📋 [PlaylistProvider] 从 getPlaylistMusics 获取到 ${musics.length} 首歌曲');
      }

      debugPrint('✅ [PlaylistProvider] loadPlaylistMusics 完成: $playlistName, ${musics.length} 首歌曲');

      state = state.copyWith(
        currentPlaylist: playlistName,
        currentPlaylistMusics: musics,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      debugPrint('❌ [PlaylistProvider] loadPlaylistMusics 失败: $e');
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
        did: deviceId,
        listName: playlistName,
        musicName: specificMusic ?? '',
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

  /// 将歌曲从当前播放列表移动到目标播放列表
  ///
  /// [musicNames] 要移动的歌曲名称列表
  /// [sourcePlaylistName] 源播放列表名称
  /// [targetPlaylistName] 目标播放列表名称
  Future<void> moveMusicToPlaylist({
    required List<String> musicNames,
    required String sourcePlaylistName,
    required String targetPlaylistName,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('📦 [PlaylistProvider] 移动歌曲: $musicNames 从 $sourcePlaylistName 到 $targetPlaylistName');

      // 1. 先添加到目标播放列表
      await apiService.addMusicToPlaylist(
        playlistName: targetPlaylistName,
        musicList: musicNames,
      );
      debugPrint('✅ [PlaylistProvider] 已添加到目标播放列表: $targetPlaylistName');

      // 2. 尝试从源播放列表删除
      final deleteResult = await apiService.removeMusicFromPlaylist(
        playlistName: sourcePlaylistName,
        musicList: musicNames,
      );

      // 3. 检查删除结果
      final deleteSuccess = _isDeleteSuccessful(deleteResult);
      if (deleteSuccess) {
        debugPrint('✅ [PlaylistProvider] 已从源播放列表删除: $sourcePlaylistName');
      } else {
        debugPrint('⚠️ [PlaylistProvider] 从源播放列表删除失败: $sourcePlaylistName, 响应: $deleteResult');
        // 如果删除失败，尝试回滚：从目标播放列表移除
        try {
          await apiService.removeMusicFromPlaylist(
            playlistName: targetPlaylistName,
            musicList: musicNames,
          );
          debugPrint('🔄 [PlaylistProvider] 已回滚添加操作');
        } catch (rollbackError) {
          debugPrint('❌ [PlaylistProvider] 回滚失败: $rollbackError');
        }

        // 抛出异常，告知用户操作失败
        final errorMsg = deleteResult['ret'] ?? '未知错误';
        throw Exception('无法从 $sourcePlaylistName 移动歌曲: $errorMsg');
      }

      // 4. 刷新播放列表数据
      await _loadPlaylists();

      // 5. 如果当前正在查看源播放列表，刷新其内容
      if (state.currentPlaylist == sourcePlaylistName) {
        await loadPlaylistMusics(sourcePlaylistName);
      }

      state = state.copyWith(isLoading: false);
      debugPrint('✅ [PlaylistProvider] 移动歌曲成功');
    } catch (e) {
      debugPrint('❌ [PlaylistProvider] 移动歌曲失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 检查删除操作是否成功
  bool _isDeleteSuccessful(Map<String, dynamic> response) {
    final ret = response['ret'];
    if (ret == null) return false;

    // 成功的响应通常是 "OK" 或 "Del OK"
    final retStr = ret.toString().toLowerCase();
    return retStr == 'ok' || retStr == 'del ok' || retStr.contains('success');
  }

  /// 添加歌曲到播放列表（不删除源列表）
  ///
  /// [musicNames] 要添加的歌曲名称列表
  /// [playlistName] 目标播放列表名称
  Future<void> addMusicToPlaylist({
    required List<String> musicNames,
    required String playlistName,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('➕ [PlaylistProvider] 添加歌曲到播放列表: $playlistName');

      await apiService.addMusicToPlaylist(
        playlistName: playlistName,
        musicList: musicNames,
      );

      // 刷新播放列表数据
      await _loadPlaylists();

      state = state.copyWith(isLoading: false);
      debugPrint('✅ [PlaylistProvider] 添加歌曲成功');
    } catch (e) {
      debugPrint('❌ [PlaylistProvider] 添加歌曲失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 从播放列表删除歌曲
  ///
  /// [musicNames] 要删除的歌曲名称列表
  /// [playlistName] 播放列表名称
  Future<void> removeMusicFromPlaylist({
    required List<String> musicNames,
    required String playlistName,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);
      debugPrint('➖ [PlaylistProvider] 从播放列表删除歌曲: $playlistName');

      final deleteResult = await apiService.removeMusicFromPlaylist(
        playlistName: playlistName,
        musicList: musicNames,
      );

      // 检查删除结果
      final deleteSuccess = _isDeleteSuccessful(deleteResult);
      if (!deleteSuccess) {
        final errorMsg = deleteResult['ret'] ?? '未知错误';
        debugPrint('❌ [PlaylistProvider] 删除歌曲失败: $errorMsg');
        throw Exception('无法从 $playlistName 删除歌曲: $errorMsg');
      }

      // 刷新播放列表数据
      await _loadPlaylists();

      // 如果当前正在查看该播放列表，刷新其内容
      if (state.currentPlaylist == playlistName) {
        await loadPlaylistMusics(playlistName);
      }

      state = state.copyWith(isLoading: false);
      debugPrint('✅ [PlaylistProvider] 删除歌曲成功');
    } catch (e) {
      debugPrint('❌ [PlaylistProvider] 删除歌曲失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }
}

final playlistProvider = StateNotifierProvider<PlaylistNotifier, PlaylistState>(
  (ref) {
    return PlaylistNotifier(ref);
  },
);
