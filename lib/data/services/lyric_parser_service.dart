import '../models/lyric.dart';

/// LRC格式歌词解析服务
class LyricParserService {
  /// 解析LRC格式歌词文本
  ///
  /// LRC格式示例:
  /// [00:12.00]第一行歌词
  /// [00:17.20]第二行歌词
  /// [ar:艺术家]
  /// [ti:歌曲名]
  Lyric parseLrc(String lrcContent) {
    if (lrcContent.trim().isEmpty) {
      return Lyric.empty();
    }

    final lines = <LyricLine>[];
    String? songName;
    String? artist;

    // 按行分割
    final lrcLines = lrcContent.split('\n');

    for (final line in lrcLines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      // 解析元数据标签
      if (trimmedLine.startsWith('[ti:')) {
        songName = _extractMetadata(trimmedLine, 'ti');
        continue;
      }
      if (trimmedLine.startsWith('[ar:')) {
        artist = _extractMetadata(trimmedLine, 'ar');
        continue;
      }

      // 解析时间戳和歌词
      final match = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)').firstMatch(trimmedLine);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = int.parse(match.group(3)!.padRight(3, '0'));
        final text = match.group(4)?.trim() ?? '';

        // 转换为秒
        final timestamp = minutes * 60 + seconds;

        lines.add(LyricLine(
          timestamp: timestamp,
          text: text,
        ));
      }
    }

    // 按时间戳排序
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Lyric(
      lines: lines,
      songName: songName,
      artist: artist,
    );
  }

  /// 提取元数据
  String? _extractMetadata(String line, String tag) {
    final regex = RegExp('\\[$tag:(.*)\\]');
    final match = regex.firstMatch(line);
    return match?.group(1)?.trim();
  }

  /// 将Lyric对象转换为LRC格式文本
  String toLrc(Lyric lyric) {
    final buffer = StringBuffer();

    // 添加元数据
    if (lyric.artist != null) {
      buffer.writeln('[ar:${lyric.artist}]');
    }
    if (lyric.songName != null) {
      buffer.writeln('[ti:${lyric.songName}]');
    }

    // 添加歌词行
    for (final line in lyric.lines) {
      final minutes = line.timestamp ~/ 60;
      final seconds = line.timestamp % 60;
      final timeTag = '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.00]';
      buffer.writeln('$timeTag${line.text}');
    }

    return buffer.toString();
  }
}
