import 'dart:convert';
import '../models/online_music_result.dart';

/// 音乐列表JSON格式适配器
/// 用于将不同格式的搜索结果转换为xiaomusic后端能识别的music_list_json格式
class MusicListJsonAdapter {
  /// 将在线搜索结果转换为xiaomusic的music_list_json格式
  ///
  /// 支持多种输入格式：
  /// - OnlineMusicResult 对象列表
  /// - 原始JSON数据
  ///
  /// 输出标准格式：
  /// ```json
  /// [
  ///   {
  ///     "name": "在线播放",
  ///     "musics": [
  ///       {
  ///         "name": "歌曲名 - 艺术家",
  ///         "url": "播放链接",
  ///         "api": true,
  ///         "headers": {...}
  ///       }
  ///     ]
  ///   }
  /// ]
  /// ```
  static String convertToMusicListJson({
    required List<OnlineMusicResult> results,
    String playlistName = "在线播放",
    Map<String, String>? defaultHeaders,
  }) {
    if (results.isEmpty) {
      return jsonEncode([
        {"name": playlistName, "musics": []},
      ]);
    }

    final musics =
        results.map((result) {
          final musicItem = <String, dynamic>{
            "name": "${result.title} - ${result.author}",
            "url": result.url,
          };

          // 智能判断是否需要API标记和请求头
          if (result.url.isNotEmpty) {
            // 判断URL是否为API接口（需要额外处理）还是直接音乐链接
            final needsApiCall = isApiUrl(result.url);

            if (needsApiCall) {
              // API接口链接，需要添加api标记和请求头
              musicItem["api"] = true;

              // 合并默认请求头和特定请求头
              final headers = <String, String>{};
              if (defaultHeaders != null) {
                headers.addAll(defaultHeaders);
              }

              // 从extra中提取headers
              if (result.extra != null && result.extra!['headers'] != null) {
                final extraHeaders =
                    result.extra!['headers'] as Map<String, dynamic>?;
                if (extraHeaders != null) {
                  extraHeaders.forEach((key, value) {
                    headers[key] = value.toString();
                  });
                }
              }

              // 根据音源平台添加特定请求头
              headers.addAll(_getPlatformHeaders(result.platform ?? 'unknown'));

              if (headers.isNotEmpty) {
                musicItem["headers"] = headers;
              }
            }
            // 如果是直接音乐链接，不添加api和headers字段
          }

          return musicItem;
        }).toList();

    final musicListJson = [
      {"name": playlistName, "musics": musics},
    ];

    return jsonEncode(musicListJson);
  }

  /// 从原始搜索结果JSON转换为music_list_json格式
  static String convertFromRawJson({
    required List<Map<String, dynamic>> rawResults,
    String playlistName = "在线播放",
    Map<String, String>? defaultHeaders,
  }) {
    final results =
        rawResults.map((item) {
          return OnlineMusicResult(
            songId: _extractValue(item, ['id', 'songid', 'song_id']) ?? '',
            title:
                _extractValue(item, ['title', 'name', 'song_name']) ?? '未知标题',
            author:
                _extractValue(item, ['artist', 'singer', 'author']) ?? '未知艺术家',
            url: _extractValue(item, ['url', 'link', 'play_url']) ?? '',
            album: _extractValue(item, ['album']) ?? '',
            duration: _parseDuration(
              _extractValue(item, ['duration', 'time']) ?? '0',
            ),
            platform: _extractValue(item, ['platform', 'source']) ?? 'unknown',
            extra: {'rawData': item},
          );
        }).toList();

    return convertToMusicListJson(
      results: results,
      playlistName: playlistName,
      defaultHeaders: defaultHeaders,
    );
  }

  /// 判断URL是否为需要API调用的接口链接
  ///
  /// API链接特征：
  /// - 包含 '/url/' 路径
  /// - 包含 '/api/' 路径
  /// - 不是直接的音频文件扩展名结尾
  /// - 包含特定的API域名
  static bool isApiUrl(String url) {
    if (url.isEmpty) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // 检查是否为直接音频文件链接
    final path = uri.path.toLowerCase();
    final directAudioExtensions = [
      '.mp3',
      '.m4a',
      '.flac',
      '.wav',
      '.aac',
      '.ogg',
    ];
    final isDirectAudio = directAudioExtensions.any(
      (ext) => path.endsWith(ext),
    );

    if (isDirectAudio) {
      return false; // 直接音频文件不需要API处理
    }

    // 检查是否为已知的API接口域名或路径
    final host = uri.host.toLowerCase();
    final apiIndicators = [
      // API路径特征
      '/url/', '/api/', '/proxy/', '/stream/',
      // 已知API域名
      'lxmusicapi', 'musicapi', 'api.', 'proxy.',
    ];

    // 检查路径中是否包含API特征
    final hasApiPath = apiIndicators.any(
      (indicator) => url.toLowerCase().contains(indicator),
    );

    // 检查是否为已知的音乐API域名
    final knownApiDomains = [
      'musicapi.lxmusic.org',
      'api.lxmusic.org',
    ];

    final isKnownApiDomain = knownApiDomains.any(
      (domain) => host.contains(domain),
    );

    return hasApiPath || isKnownApiDomain;
  }

  /// 根据平台获取特定的请求头
  static Map<String, String> _getPlatformHeaders(String platform) {
    switch (platform.toLowerCase()) {
      case 'qq':
      case 'tencent':
        return {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://y.qq.com/',
        };
      case 'netease':
      case '163':
      case 'wy':
        return {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
        };
      case 'kugou':
      case 'kg':
        return {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.kugou.com/',
        };
      case 'kuwo':
      case 'kw':
        return {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.kuwo.cn/',
        };
      case 'migu':
      case 'mg':
        return {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.migu.cn/',
        };
      default:
        return {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        };
    }
  }

  /// 从多个可能的字段中提取值
  static String? _extractValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key) && data[key] != null) {
        return data[key].toString();
      }
    }
    return null;
  }

  /// 解析持续时间
  static int _parseDuration(String duration) {
    if (duration.isEmpty) return 0;

    // 尝试解析 "mm:ss" 格式
    if (duration.contains(':')) {
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return minutes * 60 + seconds;
      }
    }

    // 尝试直接解析数字（秒）
    return int.tryParse(duration) ?? 0;
  }

  /// 验证music_list_json格式是否正确
  static bool validateMusicListJson(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      if (data is! List) return false;

      for (final item in data) {
        if (item is! Map<String, dynamic>) return false;
        if (!item.containsKey('name') || !item.containsKey('musics'))
          return false;
        if (item['musics'] is! List) return false;

        for (final music in item['musics'] as List) {
          if (music is! Map<String, dynamic>) return false;
          if (!music.containsKey('name')) return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 创建单首歌曲的music_list_json
  static String createSingleSongJson({
    required String title,
    required String artist,
    required String url,
    String playlistName = "在线播放",
    Map<String, String>? headers,
    bool? forceApi, // 强制设置是否为API调用
  }) {
    final musicItem = <String, dynamic>{"name": "$title - $artist", "url": url};

    // 智能判断或强制设置是否需要API处理
    final needsApi = forceApi ?? (url.isNotEmpty && isApiUrl(url));

    if (needsApi) {
      musicItem["api"] = true;
      if (headers != null && headers.isNotEmpty) {
        musicItem["headers"] = headers;
      }
    }

    final musicListJson = [
      {
        "name": playlistName,
        "musics": [musicItem],
      },
    ];

    return jsonEncode(musicListJson);
  }

  /// 从现有的music_list_json中添加歌曲
  static String addToExistingJson({
    required String existingJson,
    required List<OnlineMusicResult> newResults,
    String targetPlaylistName = "在线播放",
  }) {
    try {
      final data = jsonDecode(existingJson) as List;

      // 查找目标播放列表
      Map<String, dynamic>? targetPlaylist;
      for (final item in data) {
        if (item is Map<String, dynamic> &&
            item['name'] == targetPlaylistName) {
          targetPlaylist = item;
          break;
        }
      }

      // 如果没有找到目标播放列表，创建一个新的
      if (targetPlaylist == null) {
        targetPlaylist = {"name": targetPlaylistName, "musics": []};
        data.add(targetPlaylist);
      }

      // 添加新歌曲
      final musics = targetPlaylist['musics'] as List;
      for (final result in newResults) {
        final musicItem = <String, dynamic>{
          "name": "${result.title} - ${result.author}",
          "url": result.url,
        };

        // 智能判断是否需要API处理
        if (result.url.isNotEmpty && isApiUrl(result.url)) {
          musicItem["api"] = true;
          final headers = _getPlatformHeaders(result.platform ?? 'unknown');
          if (headers.isNotEmpty) {
            musicItem["headers"] = headers;
          }
        }

        musics.add(musicItem);
      }

      return jsonEncode(data);
    } catch (e) {
      // 如果解析失败，返回新的JSON
      return convertToMusicListJson(
        results: newResults,
        playlistName: targetPlaylistName,
      );
    }
  }
}
