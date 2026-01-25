import '../models/music.dart';

class MusicListAdapter {
  /// 统一将 /musiclist 响应解析为 List<Music>
  /// 兼容多种字段："所有歌曲"、"全部"、"music_list"、"musicList"、"list"、"songs"、
  /// 以及 data: List 或 data: { list|songs|music_list }
  static List<Music> parse(Map<String, dynamic> response) {
    List<dynamic> musicData = [];

    if (response.containsKey('所有歌曲')) {
      musicData = response['所有歌曲'] as List<dynamic>? ?? [];
    } else if (response.containsKey('全部')) {
      musicData = response['全部'] as List<dynamic>? ?? [];
    } else if (response.containsKey('music_list')) {
      musicData = response['music_list'] as List<dynamic>? ?? [];
    } else if (response.containsKey('musicList')) {
      musicData = response['musicList'] as List<dynamic>? ?? [];
    } else if (response.containsKey('list')) {
      musicData = response['list'] as List<dynamic>? ?? [];
    } else if (response.containsKey('songs')) {
      musicData = response['songs'] as List<dynamic>? ?? [];
    } else if (response.containsKey('data')) {
      final data = response['data'];
      if (data is List) {
        musicData = data;
      } else if (data is Map<String, dynamic>) {
        musicData =
            data['list'] as List<dynamic>? ??
            data['songs'] as List<dynamic>? ??
            data['music_list'] as List<dynamic>? ??
            [];
      }
    } else {
      // 兜底：取第一个非空的 List 字段
      for (final entry in response.entries) {
        if (entry.value is List && (entry.value as List).isNotEmpty) {
          musicData = entry.value as List;
          break;
        }
      }
    }

    return musicData.map((json) {
      if (json is Map<String, dynamic>) {
        return Music.fromJson(json);
      } else if (json is String) {
        return Music(name: json, title: json);
      } else {
        final text = json.toString();
        return Music(name: text, title: text);
      }
    }).toList();
  }
}
