class OnlineMusicResult {
  final String title;
  final String author;
  final String url;
  final String? picture;
  final String? link;
  final String? platform; // e.g. 'qq', 'kg', 'kw', 'wy', 'mg'
  final String? songId; // qq: songmid; kg: hash; others: id
  final String? album; // 专辑名称
  final int? duration; // 歌曲时长（秒）
  final Map<String, dynamic>? extra; // 额外信息，用于标记来源等

  const OnlineMusicResult({
    required this.title,
    required this.author,
    required this.url,
    this.picture,
    this.link,
    this.platform,
    this.songId,
    this.album,
    this.duration,
    this.extra,
  });

  factory OnlineMusicResult.fromTxqqPro(Map<String, dynamic> json) {
    return OnlineMusicResult(
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      picture: json['pic']?.toString(),
      link: json['link']?.toString(),
      platform: (json['type']?.toString() ?? 'qq'),
      songId: json['songid']?.toString(),
    );
  }

  factory OnlineMusicResult.fromYouTubeProxy(Map<String, dynamic> json) {
    // 解析时长
    final durationStr = json['duration']?.toString() ?? '0:00';
    final duration = _parseDuration(durationStr);

    // 从标题提取艺术家和歌曲名
    final title = json['title']?.toString() ?? '未知标题';
    final artist = _extractArtistFromTitle(title);
    final cleanTitle = _cleanTitle(title);

    return OnlineMusicResult(
      title: cleanTitle,
      author: artist,
      url: json['url']?.toString() ?? '',
      picture: json['thumbnail']?.toString(),
      platform: 'youtube',
      songId: json['videoId']?.toString() ?? '',
      album: '',
      duration: duration,
      extra: {
        'sourceApi': 'youtube_proxy',
        'videoId': json['videoId']?.toString() ?? '',
        'views': json['views']?.toString() ?? '',
        'originalTitle': title,
        'youtubeUrl': json['url']?.toString() ?? '',
        'needsProxy': true,
      },
    );
  }

  /// 解析时长字符串 (如 "4:24" -> 264秒)
  static int _parseDuration(String duration) {
    try {
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final seconds = int.parse(parts[1]);
        return minutes * 60 + seconds;
      } else if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final seconds = int.parse(parts[2]);
        return hours * 3600 + minutes * 60 + seconds;
      }
    } catch (e) {
      // 静默处理解析错误
    }
    return 0;
  }

  /// 从标题中提取艺术家信息
  static String _extractArtistFromTitle(String title) {
    // 常见的分隔符模式
    final patterns = [
      RegExp(r'(.+?)\s*[-–—]\s*(.+?)(?:\s*\[|\s*\(|$)'), // Artist - Title
      RegExp(r'(.+?)\s*[【\[]\s*(.+?)\s*[】\]]'), // Artist【Title】
      RegExp(r'(.+?)\s*『(.+?)』'), // Artist『Title』
      RegExp(r'(.+?)\s*《(.+?)》'), // Artist《Title》
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(title);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)?.trim() ?? '未知艺术家';
      }
    }

    // 如果没有匹配到模式，查找常见的艺术家标识
    if (title.contains('Jay Chou') || title.contains('周杰伦')) return '周杰伦';
    if (title.contains('Taylor Swift')) return 'Taylor Swift';

    return '未知艺术家';
  }

  /// 清理标题，移除多余信息
  static String _cleanTitle(String title) {
    // 移除常见的后缀
    final suffixPatterns = [
      RegExp(r'\s*-?\s*Official\s+(Music\s+)?Video', caseSensitive: false),
      RegExp(r'\s*\(Official\s+(Music\s+)?Video\)', caseSensitive: false),
      RegExp(r'\s*\[Official\s+(Music\s+)?Video\]', caseSensitive: false),
      RegExp(r'\s*MV\s*$', caseSensitive: false),
      RegExp(r'\s*4K\s*$', caseSensitive: false),
      RegExp(r'\s*HD\s*$', caseSensitive: false),
      RegExp(r'\s*\d+p\s*$', caseSensitive: false),
    ];

    String cleanTitle = title;
    for (final pattern in suffixPatterns) {
      cleanTitle = cleanTitle.replaceFirst(pattern, '');
    }

    // 提取【】或[]中的歌曲名
    final titleMatch = RegExp(r'[【\[]([^】\]]+)[】\]]').firstMatch(cleanTitle);
    if (titleMatch != null) {
      return titleMatch.group(1)?.trim() ?? cleanTitle.trim();
    }

    // 提取引号中的歌曲名
    final quoteMatch = RegExp(r'["""]([^"""]+)["""]').firstMatch(cleanTitle);
    if (quoteMatch != null) {
      return quoteMatch.group(1)?.trim() ?? cleanTitle.trim();
    }

    return cleanTitle.trim();
  }
}
