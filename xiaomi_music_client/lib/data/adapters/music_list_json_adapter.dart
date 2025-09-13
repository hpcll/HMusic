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
        {
          "name": playlistName,
          "musics": []
        }
      ]);
    }

    final musics = results.map((result) {
      final musicItem = <String, dynamic>{
        "name": "${result.title} - ${result.author}",
        "url": result.url,
      };

      // 如果有播放链接，添加API标记和请求头
      if (result.url.isNotEmpty) {
        musicItem["api"] = true;
        
        // 合并默认请求头和特定请求头
        final headers = <String, String>{};
        if (defaultHeaders != null) {
          headers.addAll(defaultHeaders);
        }
        
        // 从extra中提取headers
        if (result.extra != null && result.extra!['headers'] != null) {
          final extraHeaders = result.extra!['headers'] as Map<String, dynamic>?;
          if (extraHeaders != null) {
            extraHeaders.forEach((key, value) {
              headers[key] = value.toString();
            });
          }
        }
        
        // 根据音源平台添加特定请求头
        headers.addAll(_getPlatformHeaders(result.platform));
        
        if (headers.isNotEmpty) {
          musicItem["headers"] = headers;
        }
      }

      return musicItem;
    }).toList();

    final musicListJson = [
      {
        "name": playlistName,
        "musics": musics,
      }
    ];

    return jsonEncode(musicListJson);
  }

  /// 从原始搜索结果JSON转换为music_list_json格式
  static String convertFromRawJson({
    required List<Map<String, dynamic>> rawResults,
    String playlistName = "在线播放",
    Map<String, String>? defaultHeaders,
  }) {
    final results = rawResults.map((item) {
      return OnlineMusicResult(
        songId: _extractValue(item, ['id', 'songid', 'song_id']) ?? '',
        title: _extractValue(item, ['title', 'name', 'song_name']) ?? '未知标题',
        author: _extractValue(item, ['artist', 'singer', 'author']) ?? '未知艺术家',
        url: _extractValue(item, ['url', 'link', 'play_url']) ?? '',
        album: _extractValue(item, ['album']) ?? '',
        duration: _parseDuration(_extractValue(item, ['duration', 'time']) ?? '0'),
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

  /// 根据平台获取特定的请求头
  static Map<String, String> _getPlatformHeaders(String platform) {
    switch (platform.toLowerCase()) {
      case 'qq':
      case 'tencent':
        return {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://y.qq.com/',
        };
      case 'netease':
      case '163':
      case 'wy':
        return {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
        };
      case 'kugou':
      case 'kg':
        return {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.kugou.com/',
        };
      case 'kuwo':
      case 'kw':
        return {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.kuwo.cn/',
        };
      case 'migu':
      case 'mg':
        return {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.migu.cn/',
        };
      default:
        return {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
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
        if (!item.containsKey('name') || !item.containsKey('musics')) return false;
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
  }) {
    final musicListJson = [
      {
        "name": playlistName,
        "musics": [
          {
            "name": "$title - $artist",
            "url": url,
            if (url.isNotEmpty) ...{
              "api": true,
              if (headers != null && headers.isNotEmpty) "headers": headers,
            }
          }
        ]
      }
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
        if (item is Map<String, dynamic> && item['name'] == targetPlaylistName) {
          targetPlaylist = item;
          break;
        }
      }
      
      // 如果没有找到目标播放列表，创建一个新的
      if (targetPlaylist == null) {
        targetPlaylist = {
          "name": targetPlaylistName,
          "musics": []
        };
        data.add(targetPlaylist);
      }
      
      // 添加新歌曲
      final musics = targetPlaylist['musics'] as List;
      for (final result in newResults) {
        final musicItem = <String, dynamic>{
          "name": "${result.title} - ${result.author}",
          "url": result.url,
        };
        
        if (result.url.isNotEmpty) {
          musicItem["api"] = true;
          final headers = _getPlatformHeaders(result.platform);
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
