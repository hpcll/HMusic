import 'package:flutter/foundation.dart';
import '../models/lyric.dart';
import '../models/online_music_result.dart';
import 'lyric_parser_service.dart';
import 'music_api_service.dart';
import 'native_music_search_service.dart';

/// 歌词服务
/// 负责获取和解析歌词
class LyricService {
  final MusicApiService _musicApi;
  final NativeMusicSearchService _nativeSearch;
  final LyricParserService _parser = LyricParserService();

  LyricService({
    required MusicApiService musicApi,
    required NativeMusicSearchService nativeSearch,
  })  : _musicApi = musicApi,
        _nativeSearch = nativeSearch;

  /// 获取歌词
  ///
  /// 优先从服务器获取,如果没有则从在线音乐平台刮削
  ///
  /// [musicName] 歌曲名称
  /// [autoScrape] 如果服务器没有歌词,是否自动从在线平台刮削
  Future<Lyric> getLyrics({
    required String musicName,
    bool autoScrape = true,
  }) async {
    try {
      debugPrint('🎤 [Lyric] 获取歌词: $musicName');

      // 1. 先从服务器获取
      final serverLyrics = await _getLyricsFromServer(musicName);
      if (serverLyrics != null && serverLyrics.hasLyrics) {
        debugPrint('✅ [Lyric] 从服务器获取到歌词');
        return serverLyrics;
      }

      // 2. 如果没有且允许刮削,从在线平台获取
      if (!autoScrape) {
        debugPrint('⚠️ [Lyric] 服务器无歌词,跳过刮削');
        return Lyric.empty();
      }

      debugPrint('🔍 [Lyric] 服务器无歌词,开始在线刮削...');
      final scrapedLyrics = await _scrapeLyricsFromOnline(musicName);

      if (scrapedLyrics != null && scrapedLyrics.hasLyrics) {
        debugPrint('✅ [Lyric] 刮削成功,后台上传到服务器');
        // 后台异步上传到服务器
        _uploadLyricsToServerAsync(musicName, scrapedLyrics);
        return scrapedLyrics;
      }

      debugPrint('⚠️ [Lyric] 刮削失败,无歌词');
      return Lyric.empty();
    } catch (e) {
      debugPrint('❌ [Lyric] 获取歌词失败: $e');
      return Lyric.empty();
    }
  }

  /// 从服务器获取歌词
  Future<Lyric?> _getLyricsFromServer(String musicName) async {
    try {
      final musicInfo = await _musicApi.getMusicInfo(musicName, includeTag: true);
      final lyricsText = musicInfo['tags']?['lyrics']?.toString();

      if (lyricsText != null && lyricsText.isNotEmpty) {
        debugPrint('✅ [Lyric] 服务器返回歌词,长度: ${lyricsText.length}');
        return _parser.parseLrc(lyricsText);
      }

      return null;
    } catch (e) {
      debugPrint('❌ [Lyric] 从服务器获取歌词失败: $e');
      return null;
    }
  }

  /// 从在线平台刮削歌词
  Future<Lyric?> _scrapeLyricsFromOnline(String musicName) async {
    try {
      // 解析歌曲名,支持两种格式:
      // 1. "歌名 - 歌手" (标准格式)
      // 2. "歌手 - 歌名" (部分本地文件格式)
      final parts = musicName.split(' - ');
      String songName;
      String? artistName;

      if (parts.length >= 2) {
        // 尝试两种格式进行搜索
        songName = parts[0].trim();
        artistName = parts[1].trim();
        debugPrint('🔍 [Lyric] 解析: 部分1="$songName", 部分2="$artistName"');
      } else {
        songName = musicName;
        artistName = null;
        debugPrint('🔍 [Lyric] 解析: 单一名称="$songName"');
      }

      debugPrint('🔍 [Lyric] 开始搜索歌词...');

      // 优先使用QQ音乐获取歌词(QQ音乐歌词质量最好)
      try {
        // 先尝试用第一部分作为歌名搜索
        var results = await _nativeSearch.searchQQ(query: songName, page: 1);

        // 如果没有结果且有第二部分,尝试用第二部分作为歌名搜索
        if (results.isEmpty && artistName != null) {
          debugPrint('⚠️ [Lyric] 第一次搜索无结果,尝试反转格式搜索');
          results = await _nativeSearch.searchQQ(query: artistName, page: 1);
          // 交换歌名和艺术家名
          final temp = songName;
          songName = artistName;
          artistName = temp;
          debugPrint('🔄 [Lyric] 使用反转格式: 歌名="$songName", 艺术家="$artistName"');
        }

        if (results.isEmpty) {
          debugPrint('⚠️ [Lyric] QQ音乐搜索无结果');
          return null;
        }

        // 🎯 智能匹配:同时考虑歌名和艺术家
        OnlineMusicResult? bestMatch;
        OnlineMusicResult? fallbackMatch;

        debugPrint('🔍 [Lyric] 搜索结果数量: ${results.length}');

        for (final result in results) {
          debugPrint('  - ${result.title} - ${result.author} (songId: ${result.songId})');

          if (result.songId == null || result.songId!.isEmpty) continue;

          // 如果有艺术家名称,优先匹配艺术家
          if (artistName != null && artistName.isNotEmpty) {
            final resultArtist = result.author.toLowerCase().trim();
            final resultTitle = result.title.toLowerCase().trim();
            final targetArtist = artistName.toLowerCase().trim();
            final targetSong = songName.toLowerCase().trim();

            // 策略1: 艺术家名称匹配
            final artistMatch = resultArtist == targetArtist ||
                resultArtist.contains(targetArtist) ||
                targetArtist.contains(resultArtist);

            // 策略2: 歌名匹配
            final songMatch = resultTitle == targetSong ||
                resultTitle.contains(targetSong) ||
                targetSong.contains(resultTitle);

            // 最佳匹配: 艺术家和歌名都匹配
            if (artistMatch && songMatch) {
              bestMatch = result;
              debugPrint('✅ [Lyric] 找到完美匹配(艺术家+歌名): ${result.title} - ${result.author}');
              break;
            }

            // 次优匹配: 艺术家匹配
            if (artistMatch && bestMatch == null) {
              bestMatch = result;
              debugPrint('✅ [Lyric] 找到艺术家匹配: ${result.title} - ${result.author}');
            }
          }

          // 记录第一个有效结果作为备选
          fallbackMatch ??= result;
        }

        // 使用最佳匹配,如果没有则使用备选
        final selectedResult = bestMatch ?? fallbackMatch;

        if (bestMatch != null) {
          debugPrint('🎯 [Lyric] 使用匹配结果');
        } else if (fallbackMatch != null) {
          debugPrint('⚠️ [Lyric] 未找到精确匹配,使用第一个结果作为备选');
        }

        if (selectedResult != null) {
          debugPrint('🎤 [Lyric] 获取歌词: ${selectedResult.title} - ${selectedResult.author}');

          final lyricsText = await _nativeSearch.getLyricsQQ(selectedResult.songId!);
          if (lyricsText != null && lyricsText.isNotEmpty) {
            debugPrint('✅ [Lyric] 获取到歌词,长度: ${lyricsText.length}');
            return _parser.parseLrc(lyricsText);
          }
        }

        debugPrint('⚠️ [Lyric] 未找到可用歌词');
        return null;
      } catch (e) {
        debugPrint('❌ [Lyric] QQ音乐获取歌词失败: $e');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [Lyric] 刮削歌词失败: $e');
      return null;
    }
  }

  /// 后台异步上传歌词到服务器
  void _uploadLyricsToServerAsync(String musicName, Lyric lyric) {
    Future(() async {
      try {
        debugPrint('🔄 [Lyric] 后台上传歌词到服务器: $musicName');

        final lrcText = _parser.toLrc(lyric);
        await _musicApi.setMusicTag({
          'musicname': musicName,
          'lyrics': lrcText,
        });

        debugPrint('✅ [Lyric] 后台上传歌词成功');
      } catch (e) {
        debugPrint('❌ [Lyric] 后台上传歌词失败: $e');
        // 静默失败,不影响用户体验
      }
    });
  }
}
