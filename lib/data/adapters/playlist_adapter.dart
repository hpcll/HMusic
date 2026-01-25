import '../models/playlist.dart';

class PlaylistAdapter {
  /// 提取服务端真实播放列表名称（用于判定哪些可删除）
  static List<String> extractNames(dynamic playlistNamesResponse) {
    return _normalizeNames(playlistNamesResponse);
  }

  /// 将 /playlistnames 响应与 /musiclist 聚合为 Playlist 列表
  static List<Playlist> mergeToPlaylists(
    dynamic playlistNamesResponse,
    Map<String, dynamic> musicListResponse,
  ) {
    List<String> names = _normalizeNames(playlistNamesResponse);
    final Set<String> allNames = {
      ...names,
      ...musicListResponse.keys.map((k) => k.toString()),
    }..addAll({'临时搜索列表', '收藏', '全部'});

    final List<Playlist> playlists =
        allNames.map((n) {
            int? count;
            List<String>? musicList;
            final v = musicListResponse[n];
            if (v is List) {
              count = v.length;
              // 将歌曲列表转换为字符串列表
              musicList = v.map((e) => e.toString()).toList();
            }
            return Playlist(name: n, count: count, musicList: musicList);
          })
          // 过滤掉没有歌曲的系统内置列表（不可删除且无歌曲的列表）
          .where((playlist) {
            final isDeletable = names.contains(playlist.name);
            final isEmpty = playlist.count == null || playlist.count == 0;
            // 如果是系统内置列表（不可删除）且为空，则隐藏
            return isDeletable || !isEmpty;
          })
          .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return playlists;
  }

  static List<String> _normalizeNames(dynamic data) {
    if (data is List) {
      return data
          .map((e) => e is Map ? (e['name'] ?? e['title'] ?? e.toString()) : e)
          .map((e) => e.toString())
          .toList();
    }
    if (data is Map) {
      final map = data;
      if (map.containsKey('playlists')) {
        final playlistsField = map['playlists'];
        if (playlistsField is List) return _normalizeNames(playlistsField);
        if (playlistsField is Map) {
          return playlistsField.keys.map((e) => e.toString()).toList();
        }
      }
      final candidates = [
        'playlist_names',
        'playlistNames',
        'names',
        'list',
        'data',
        'items',
      ];
      for (final key in candidates) {
        if (map.containsKey(key)) {
          final value = map[key];
          if (value is List || value is Map) return _normalizeNames(value);
        }
      }
      for (final entry in map.entries) {
        if (entry.value is Map) {
          return (entry.value as Map).keys.map((e) => e.toString()).toList();
        }
      }
      return map.values
          .where((v) => v is String)
          .map((v) => v.toString())
          .toList();
    }
    return <String>[];
  }
}
