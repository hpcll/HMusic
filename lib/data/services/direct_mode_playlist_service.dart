import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/local_playlist_model.dart';

/// 🎵 直连模式本地歌单服务
///
/// 用于在直连模式下管理本地歌单（因为小米IoT API不支持歌单功能）
/// 歌单数据保存在 SharedPreferences 中
class DirectModePlaylistService {
  static const String _playlistsKey = 'direct_mode_playlists';
  static const String _favoritePlaylistId = 'favorite_playlist'; // 收藏歌单的固定ID

  /// 📋 获取所有歌单
  Future<List<LocalPlaylistModel>> getAllPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_playlistsKey);

      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('📋 [歌单服务] 没有保存的歌单，返回空列表');
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
      final playlists = jsonList
          .map((json) => LocalPlaylistModel.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('📋 [歌单服务] 获取到 ${playlists.length} 个歌单');
      return playlists;
    } catch (e) {
      debugPrint('❌ [歌单服务] 获取歌单列表失败: $e');
      return [];
    }
  }

  /// 🎵 根据ID获取歌单
  Future<LocalPlaylistModel?> getPlaylistById(String id) async {
    try {
      final playlists = await getAllPlaylists();
      return playlists.firstWhere(
        (p) => p.id == id,
        orElse: () => throw Exception('歌单不存在'),
      );
    } catch (e) {
      debugPrint('❌ [歌单服务] 获取歌单失败: $e');
      return null;
    }
  }

  /// 🎵 根据名称获取歌单
  Future<LocalPlaylistModel?> getPlaylistByName(String name) async {
    try {
      final playlists = await getAllPlaylists();
      return playlists.firstWhere(
        (p) => p.name == name,
        orElse: () => throw Exception('歌单不存在'),
      );
    } catch (e) {
      debugPrint('❌ [歌单服务] 获取歌单失败: $e');
      return null;
    }
  }

  /// ✨ 创建新歌单
  Future<bool> createPlaylist({
    required String name,
    String? description,
    String? coverUrl,
    List<String>? initialSongs,
  }) async {
    if (name.isEmpty) {
      debugPrint('⚠️ [歌单服务] 歌单名称不能为空');
      return false;
    }

    try {
      final playlists = await getAllPlaylists();

      // 检查是否已存在同名歌单
      if (playlists.any((p) => p.name == name)) {
        debugPrint('⚠️ [歌单服务] 歌单名称已存在: $name');
        return false;
      }

      // 创建新歌单
      final now = DateTime.now();
      final newPlaylist = LocalPlaylistModel(
        id: now.millisecondsSinceEpoch.toString(), // 使用时间戳作为ID
        name: name,
        songs: initialSongs ?? [],
        coverUrl: coverUrl,
        createdAt: now,
        updatedAt: now,
        description: description,
      );

      // 添加到列表
      playlists.add(newPlaylist);

      // 保存
      await _savePlaylists(playlists);

      debugPrint('✅ [歌单服务] 已创建歌单: $name (共${playlists.length}个歌单)');
      return true;
    } catch (e) {
      debugPrint('❌ [歌单服务] 创建歌单失败: $e');
      return false;
    }
  }

  /// 🔄 更新歌单
  Future<bool> updatePlaylist(LocalPlaylistModel playlist) async {
    try {
      final playlists = await getAllPlaylists();
      final index = playlists.indexWhere((p) => p.id == playlist.id);

      if (index == -1) {
        debugPrint('⚠️ [歌单服务] 歌单不存在: ${playlist.id}');
        return false;
      }

      // 更新时间
      final updatedPlaylist = playlist.copyWith(updatedAt: DateTime.now());
      playlists[index] = updatedPlaylist;

      // 保存
      await _savePlaylists(playlists);

      debugPrint('✅ [歌单服务] 已更新歌单: ${playlist.name}');
      return true;
    } catch (e) {
      debugPrint('❌ [歌单服务] 更新歌单失败: $e');
      return false;
    }
  }

  /// 🗑️ 删除歌单
  Future<bool> deletePlaylist(String id) async {
    try {
      final playlists = await getAllPlaylists();
      final initialLength = playlists.length;

      // 删除指定歌单
      playlists.removeWhere((p) => p.id == id);

      if (playlists.length == initialLength) {
        debugPrint('⚠️ [歌单服务] 歌单不存在: $id');
        return false;
      }

      // 保存
      await _savePlaylists(playlists);

      debugPrint('✅ [歌单服务] 已删除歌单 (剩余${playlists.length}个)');
      return true;
    } catch (e) {
      debugPrint('❌ [歌单服务] 删除歌单失败: $e');
      return false;
    }
  }

  /// ➕ 添加歌曲到歌单
  Future<bool> addSongToPlaylist(String playlistId, String songName) async {
    if (songName.isEmpty) {
      debugPrint('⚠️ [歌单服务] 歌曲名称不能为空');
      return false;
    }

    try {
      final playlist = await getPlaylistById(playlistId);
      if (playlist == null) {
        debugPrint('⚠️ [歌单服务] 歌单不存在: $playlistId');
        return false;
      }

      // 检查是否已存在
      if (playlist.songs.contains(songName)) {
        debugPrint('ℹ️ [歌单服务] 歌曲已在歌单中: $songName');
        return false;
      }

      // 添加歌曲
      final updatedSongs = [...playlist.songs, songName];
      final updatedPlaylist = playlist.copyWith(songs: updatedSongs);

      // 更新歌单
      await updatePlaylist(updatedPlaylist);

      debugPrint('✅ [歌单服务] 已添加歌曲到歌单: $songName (共${updatedSongs.length}首)');
      return true;
    } catch (e) {
      debugPrint('❌ [歌单服务] 添加歌曲失败: $e');
      return false;
    }
  }

  /// ➖ 从歌单中移除歌曲
  Future<bool> removeSongFromPlaylist(String playlistId, String songName) async {
    try {
      final playlist = await getPlaylistById(playlistId);
      if (playlist == null) {
        debugPrint('⚠️ [歌单服务] 歌单不存在: $playlistId');
        return false;
      }

      // 检查是否存在
      if (!playlist.songs.contains(songName)) {
        debugPrint('ℹ️ [歌单服务] 歌曲不在歌单中: $songName');
        return false;
      }

      // 移除歌曲
      final updatedSongs = playlist.songs.where((s) => s != songName).toList();
      final updatedPlaylist = playlist.copyWith(songs: updatedSongs);

      // 更新歌单
      await updatePlaylist(updatedPlaylist);

      debugPrint('✅ [歌单服务] 已从歌单移除歌曲: $songName (剩余${updatedSongs.length}首)');
      return true;
    } catch (e) {
      debugPrint('❌ [歌单服务] 移除歌曲失败: $e');
      return false;
    }
  }

  /// 🔗 从收藏列表同步创建"我的收藏"歌单
  Future<bool> syncFavoritesToPlaylist(List<String> favoriteSongs) async {
    try {
      // 查找或创建"我的收藏"歌单
      var favoritePlaylist = await getPlaylistById(_favoritePlaylistId);

      if (favoritePlaylist == null) {
        // 创建"我的收藏"歌单
        await createPlaylist(
          name: '我的收藏',
          description: '从收藏功能自动同步',
          initialSongs: favoriteSongs,
        );

        // 重新获取（因为创建时ID是自动生成的，需要手动设置为固定ID）
        final playlists = await getAllPlaylists();
        final index = playlists.indexWhere((p) => p.name == '我的收藏');
        if (index != -1) {
          playlists[index] = playlists[index].copyWith(id: _favoritePlaylistId);
          await _savePlaylists(playlists);
        }

        debugPrint('✅ [歌单服务] 已创建"我的收藏"歌单');
      } else {
        // 更新现有歌单
        final updatedPlaylist = favoritePlaylist.copyWith(songs: favoriteSongs);
        await updatePlaylist(updatedPlaylist);

        debugPrint('✅ [歌单服务] 已同步"我的收藏"歌单 (${favoriteSongs.length}首)');
      }

      return true;
    } catch (e) {
      debugPrint('❌ [歌单服务] 同步收藏歌单失败: $e');
      return false;
    }
  }

  /// 💾 保存歌单列表到本地
  Future<void> _savePlaylists(List<LocalPlaylistModel> playlists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = playlists.map((p) => p.toJson()).toList();
      final jsonStr = jsonEncode(jsonList);

      await prefs.setString(_playlistsKey, jsonStr);
      debugPrint('💾 [歌单服务] 已保存 ${playlists.length} 个歌单');
    } catch (e) {
      debugPrint('❌ [歌单服务] 保存歌单失败: $e');
      rethrow;
    }
  }

  /// 🗑️ 清空所有歌单
  Future<bool> clearAllPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_playlistsKey);
      debugPrint('🗑️ [歌单服务] 已清空所有歌单');
      return true;
    } catch (e) {
      debugPrint('❌ [歌单服务] 清空歌单失败: $e');
      return false;
    }
  }

  /// 📊 获取歌单数量
  Future<int> getPlaylistCount() async {
    try {
      final playlists = await getAllPlaylists();
      return playlists.length;
    } catch (e) {
      debugPrint('❌ [歌单服务] 获取歌单数量失败: $e');
      return 0;
    }
  }
}
