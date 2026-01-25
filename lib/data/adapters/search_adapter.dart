import '../models/music.dart';

class SearchAdapter {
  /// 将 /searchmusic 返回的 List<dynamic> 统一为 List<Music>
  static List<Music> parse(List<dynamic> results) {
    return results.map((json) {
      if (json is Map<String, dynamic>) return Music.fromJson(json);
      if (json is String) return Music(name: json, title: json);
      final text = json.toString();
      return Music(name: text, title: text);
    }).toList();
  }
}
