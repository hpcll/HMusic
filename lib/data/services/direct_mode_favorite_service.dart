import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 🎵 直连模式收藏服务
///
/// 用于在直连模式下管理本地收藏列表（因为小米IoT API不支持收藏功能）
/// 收藏数据保存在 SharedPreferences 中
class DirectModeFavoriteService {
  static const String _favoritesKey = 'direct_mode_favorites';
  static const String _favoriteDetailsKey = 'direct_mode_favorite_details';

  /// ⭐ 添加歌曲到收藏
  ///
  /// [songName] 歌曲名称
  /// [albumCoverUrl] 专辑封面URL（可选）
  Future<bool> addFavorite(String songName, {String? albumCoverUrl}) async {
    if (songName.isEmpty) {
      debugPrint('⚠️ [收藏服务] 歌曲名称为空');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // 获取当前收藏列表
      final favorites = prefs.getStringList(_favoritesKey) ?? [];

      // 检查是否已收藏
      if (favorites.contains(songName)) {
        debugPrint('ℹ️ [收藏服务] 歌曲已在收藏列表中: $songName');
        return false;
      }

      // 添加到收藏列表
      favorites.add(songName);
      await prefs.setStringList(_favoritesKey, favorites);

      // 如果有封面URL，保存详细信息
      if (albumCoverUrl != null && albumCoverUrl.isNotEmpty) {
        final details = prefs.getString(_favoriteDetailsKey);
        final Map<String, dynamic> detailsMap = details != null
            ? Map<String, dynamic>.from(
                // ignore: avoid_dynamic_calls
                (Uri.decodeComponent(details) as Map).cast<String, dynamic>(),
              )
            : {};

        detailsMap[songName] = {
          'name': songName,
          'coverUrl': albumCoverUrl,
          'addedAt': DateTime.now().toIso8601String(),
        };

        await prefs.setString(
          _favoriteDetailsKey,
          Uri.encodeComponent(detailsMap.toString()),
        );
      }

      debugPrint('✅ [收藏服务] 已添加到收藏: $songName (共${favorites.length}首)');
      return true;
    } catch (e) {
      debugPrint('❌ [收藏服务] 添加收藏失败: $e');
      return false;
    }
  }

  /// 💔 从收藏中移除歌曲
  Future<bool> removeFavorite(String songName) async {
    if (songName.isEmpty) {
      debugPrint('⚠️ [收藏服务] 歌曲名称为空');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // 获取当前收藏列表
      final favorites = prefs.getStringList(_favoritesKey) ?? [];

      // 检查是否在收藏列表中
      if (!favorites.contains(songName)) {
        debugPrint('ℹ️ [收藏服务] 歌曲不在收藏列表中: $songName');
        return false;
      }

      // 从列表中移除
      favorites.remove(songName);
      await prefs.setStringList(_favoritesKey, favorites);

      // 移除详细信息
      final details = prefs.getString(_favoriteDetailsKey);
      if (details != null) {
        final Map<String, dynamic> detailsMap = Map<String, dynamic>.from(
          // ignore: avoid_dynamic_calls
          (Uri.decodeComponent(details) as Map).cast<String, dynamic>(),
        );

        detailsMap.remove(songName);

        await prefs.setString(
          _favoriteDetailsKey,
          Uri.encodeComponent(detailsMap.toString()),
        );
      }

      debugPrint('✅ [收藏服务] 已从收藏移除: $songName (剩余${favorites.length}首)');
      return true;
    } catch (e) {
      debugPrint('❌ [收藏服务] 移除收藏失败: $e');
      return false;
    }
  }

  /// ❓ 检查歌曲是否已收藏
  Future<bool> isFavorite(String songName) async {
    if (songName.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList(_favoritesKey) ?? [];
      return favorites.contains(songName);
    } catch (e) {
      debugPrint('❌ [收藏服务] 检查收藏状态失败: $e');
      return false;
    }
  }

  /// 📋 获取所有收藏的歌曲
  Future<List<String>> getAllFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList(_favoritesKey) ?? [];
      debugPrint('📋 [收藏服务] 获取收藏列表: ${favorites.length}首');
      return favorites;
    } catch (e) {
      debugPrint('❌ [收藏服务] 获取收藏列表失败: $e');
      return [];
    }
  }

  /// 🗑️ 清空所有收藏
  Future<bool> clearAllFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_favoritesKey);
      await prefs.remove(_favoriteDetailsKey);
      debugPrint('🗑️ [收藏服务] 已清空所有收藏');
      return true;
    } catch (e) {
      debugPrint('❌ [收藏服务] 清空收藏失败: $e');
      return false;
    }
  }

  /// 📊 获取收藏数量
  Future<int> getFavoriteCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList(_favoritesKey) ?? [];
      return favorites.length;
    } catch (e) {
      debugPrint('❌ [收藏服务] 获取收藏数量失败: $e');
      return 0;
    }
  }
}
