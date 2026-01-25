import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/local_playlist.dart';

/// 本地播放列表状态
class LocalPlaylistState {
  final List<LocalPlaylist> playlists;
  final bool isLoading;
  final String? error;

  const LocalPlaylistState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  LocalPlaylistState copyWith({
    List<LocalPlaylist>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return LocalPlaylistState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 本地播放列表管理器（用于直连模式）
/// 使用 SharedPreferences 存储，完全本地化，无需服务器
class LocalPlaylistNotifier extends StateNotifier<LocalPlaylistState> {
  LocalPlaylistNotifier() : super(const LocalPlaylistState()) {
    _init();
  }

  static const String _cacheKey = 'local_playlists_cache';

  /// 初始化：加载本地播放列表
  Future<void> _init() async {
    await loadPlaylists();
  }

  /// 从 SharedPreferences 加载播放列表
  Future<void> loadPlaylists() async {
    try {
      state = state.copyWith(isLoading: true);

      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_cacheKey);

      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('📋 [LocalPlaylist] 没有缓存的播放列表');
        state = state.copyWith(playlists: [], isLoading: false);
        return;
      }

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final playlists = jsonList
          .map((json) => LocalPlaylist.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('✅ [LocalPlaylist] 加载了 ${playlists.length} 个播放列表');
      state = state.copyWith(playlists: playlists, isLoading: false, error: null);
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 加载播放列表失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 刷新播放列表（与 PlaylistProvider API 一致）
  Future<void> refreshPlaylists() async {
    await loadPlaylists();
  }

  /// 保存播放列表到 SharedPreferences
  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.playlists.map((p) => p.toJson()).toList();
      final jsonStr = jsonEncode(jsonList);
      await prefs.setString(_cacheKey, jsonStr);
      debugPrint('💾 [LocalPlaylist] 已保存 ${state.playlists.length} 个播放列表');
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 保存播放列表失败: $e');
    }
  }

  /// 创建播放列表
  Future<void> createPlaylist(String name) async {
    try {
      state = state.copyWith(isLoading: true);

      // 检查名称是否重复
      final exists = state.playlists.any((p) => p.name == name);
      if (exists) {
        throw Exception('播放列表"$name"已存在');
      }

      final newPlaylist = LocalPlaylist.create(name: name);
      final updatedPlaylists = [...state.playlists, newPlaylist];

      state = state.copyWith(playlists: updatedPlaylists, isLoading: false);
      await _savePlaylists();

      debugPrint('✅ [LocalPlaylist] 创建播放列表: $name');
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 创建播放列表失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 删除播放列表（通过名称，与 PlaylistProvider API 一致）
  Future<void> deletePlaylist(String playlistName) async {
    try {
      state = state.copyWith(isLoading: true);

      final updatedPlaylists =
          state.playlists.where((p) => p.name != playlistName).toList();

      state = state.copyWith(playlists: updatedPlaylists, isLoading: false);
      await _savePlaylists();

      debugPrint('✅ [LocalPlaylist] 删除播放列表: $playlistName');
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 删除播放列表失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 添加歌曲到播放列表
  /// [playlistName] 播放列表名称
  /// [songs] 要添加的歌曲列表
  Future<void> addMusicToPlaylist({
    required String playlistName,
    required List<LocalPlaylistSong> songs,
  }) async {
    try {
      state = state.copyWith(isLoading: true);

      final playlistIndex =
          state.playlists.indexWhere((p) => p.name == playlistName);

      if (playlistIndex == -1) {
        throw Exception('播放列表"$playlistName"不存在');
      }

      final playlist = state.playlists[playlistIndex];
      final updatedSongs = [...playlist.songs];

      // 添加歌曲（检查重复）
      int addedCount = 0;
      for (final song in songs) {
        final exists = updatedSongs.any(
          (s) =>
              s.title == song.title &&
              s.artist == song.artist &&
              s.platform == song.platform &&
              s.songId == song.songId,
        );

        if (!exists) {
          updatedSongs.add(song);
          addedCount++;
        } else {
          debugPrint('⚠️ [LocalPlaylist] 歌曲已存在，跳过: ${song.displayName}');
        }
      }

      final updatedPlaylist = playlist.copyWith(
        songs: updatedSongs,
        updatedAt: DateTime.now(),
      );

      final updatedPlaylists = [...state.playlists];
      updatedPlaylists[playlistIndex] = updatedPlaylist;

      state = state.copyWith(playlists: updatedPlaylists, isLoading: false);
      await _savePlaylists();

      debugPrint('✅ [LocalPlaylist] 添加了 $addedCount 首歌曲到 $playlistName');
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 添加歌曲失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 从播放列表删除歌曲
  /// [playlistName] 播放列表名称
  /// [songIndices] 要删除的歌曲索引列表
  Future<void> removeMusicFromPlaylist({
    required String playlistName,
    required List<int> songIndices,
  }) async {
    try {
      state = state.copyWith(isLoading: true);

      final playlistIndex =
          state.playlists.indexWhere((p) => p.name == playlistName);

      if (playlistIndex == -1) {
        throw Exception('播放列表"$playlistName"不存在');
      }

      final playlist = state.playlists[playlistIndex];
      final updatedSongs = [...playlist.songs];

      // 按索引倒序删除（避免索引错乱）
      final sortedIndices = songIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final index in sortedIndices) {
        if (index >= 0 && index < updatedSongs.length) {
          updatedSongs.removeAt(index);
        }
      }

      final updatedPlaylist = playlist.copyWith(
        songs: updatedSongs,
        updatedAt: DateTime.now(),
      );

      final updatedPlaylists = [...state.playlists];
      updatedPlaylists[playlistIndex] = updatedPlaylist;

      state = state.copyWith(playlists: updatedPlaylists, isLoading: false);
      await _savePlaylists();

      debugPrint('✅ [LocalPlaylist] 从 $playlistName 删除了 ${songIndices.length} 首歌曲');
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 删除歌曲失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 获取指定播放列表的歌曲列表
  List<LocalPlaylistSong> getPlaylistSongs(String playlistName) {
    try {
      final playlist = state.playlists.firstWhere(
        (p) => p.name == playlistName,
        orElse: () => throw Exception('播放列表"$playlistName"不存在'),
      );
      return playlist.songs;
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 获取播放列表歌曲失败: $e');
      return [];
    }
  }

  /// 🎯 更新歌曲的缓存URL（6小时有效期）
  /// [playlistName] 播放列表名称
  /// [songIndex] 歌曲在列表中的索引
  /// [cachedUrl] 缓存的播放链接
  Future<void> updateSongCache({
    required String playlistName,
    required int songIndex,
    required String cachedUrl,
  }) async {
    try {
      final playlistIndex =
          state.playlists.indexWhere((p) => p.name == playlistName);

      if (playlistIndex == -1) {
        throw Exception('播放列表"$playlistName"不存在');
      }

      final playlist = state.playlists[playlistIndex];
      if (songIndex < 0 || songIndex >= playlist.songs.length) {
        throw Exception('歌曲索引越界: $songIndex');
      }

      final song = playlist.songs[songIndex];

      // 🎯 更新缓存URL和过期时间（6小时后过期）
      final updatedSong = song.copyWith(
        cachedUrl: cachedUrl,
        urlExpireTime: DateTime.now().add(const Duration(hours: 6)),
      );

      final updatedSongs = [...playlist.songs];
      updatedSongs[songIndex] = updatedSong;

      final updatedPlaylist = playlist.copyWith(
        songs: updatedSongs,
        updatedAt: DateTime.now(),
      );

      final updatedPlaylists = [...state.playlists];
      updatedPlaylists[playlistIndex] = updatedPlaylist;

      state = state.copyWith(playlists: updatedPlaylists);
      await _savePlaylists();

      debugPrint(
        '✅ [LocalPlaylist] 更新歌曲缓存: ${song.displayName}\n'
        '   URL: ${cachedUrl.substring(0, cachedUrl.length > 50 ? 50 : cachedUrl.length)}...\n'
        '   过期时间: ${updatedSong.urlExpireTime}',
      );
    } catch (e) {
      debugPrint('❌ [LocalPlaylist] 更新歌曲缓存失败: $e');
      rethrow;
    }
  }

  /// 清除错误信息
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// 本地播放列表 Provider
final localPlaylistProvider =
    StateNotifierProvider<LocalPlaylistNotifier, LocalPlaylistState>((ref) {
  return LocalPlaylistNotifier();
});
