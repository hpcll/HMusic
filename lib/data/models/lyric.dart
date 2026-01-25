import 'package:json_annotation/json_annotation.dart';

part 'lyric.g.dart';

/// 单行歌词
@JsonSerializable()
class LyricLine {
  /// 时间戳(秒)
  final int timestamp;

  /// 歌词文本
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  factory LyricLine.fromJson(Map<String, dynamic> json) => _$LyricLineFromJson(json);
  Map<String, dynamic> toJson() => _$LyricLineToJson(this);
}

/// 歌词数据
@JsonSerializable()
class Lyric {
  /// 歌词行列表
  final List<LyricLine> lines;

  /// 歌曲名称
  final String? songName;

  /// 艺术家
  final String? artist;

  const Lyric({
    required this.lines,
    this.songName,
    this.artist,
  });

  /// 根据当前播放时间获取当前歌词行索引
  int getCurrentLineIndex(int currentTime) {
    if (lines.isEmpty) return -1;

    // 找到最后一个时间戳小于等于当前时间的行
    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].timestamp <= currentTime) {
        return i;
      }
    }
    return -1;
  }

  /// 检查是否有歌词
  bool get hasLyrics => lines.isNotEmpty;

  factory Lyric.fromJson(Map<String, dynamic> json) => _$LyricFromJson(json);
  Map<String, dynamic> toJson() => _$LyricToJson(this);

  /// 创建空歌词
  factory Lyric.empty() => const Lyric(lines: []);
}
