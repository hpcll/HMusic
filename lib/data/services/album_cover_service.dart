import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'music_api_service.dart';
import 'native_music_search_service.dart';

/// 专辑封面服务
/// 负责从在线音乐平台刮削封面并上传到NAS服务器
class AlbumCoverService {
  final MusicApiService _musicApi;
  final NativeMusicSearchService _nativeSearch;
  final Dio _dio = Dio();

  AlbumCoverService({
    required MusicApiService musicApi,
    required NativeMusicSearchService nativeSearch,
  })  : _musicApi = musicApi,
        _nativeSearch = nativeSearch;

  /// 获取歌曲封面（如果没有则自动刮削并上传）
  ///
  /// 返回值：
  /// - 有封面：返回封面URL（已替换为登录域名）
  /// - 无封面且刮削成功：返回新的封面URL
  /// - 无封面且刮削失败：返回null
  Future<String?> getOrFetchAlbumCover({
    required String musicName,
    required String loginBaseUrl,
    bool autoScrape = true,
  }) async {
    try {
      debugPrint('🖼️ [AlbumCover] 获取封面: $musicName');

      // 1. 先从服务器获取音乐信息
      final musicInfo = await _musicApi.getMusicInfo(musicName, includeTag: true);
      String? pictureUrl = musicInfo['tags']?['picture']?.toString();

      // 2. 如果有封面，替换内网地址后返回
      if (pictureUrl != null && pictureUrl.isNotEmpty) {
        debugPrint('✅ [AlbumCover] 服务器已有封面: $pictureUrl');
        return _replaceWithLoginDomain(pictureUrl, loginBaseUrl);
      }

      // 3. 如果没有封面且允许自动刮削
      if (!autoScrape) {
        debugPrint('⚠️ [AlbumCover] 无封面，跳过刮削');
        return null;
      }

      debugPrint('🔍 [AlbumCover] 无封面，开始在线刮削...');

      // 4. 在线搜索封面和歌词
      final scrapeResult = await _scrapeAlbumCoverAndLyrics(musicName);
      if (scrapeResult == null || scrapeResult.coverUrl == null || scrapeResult.coverUrl!.isEmpty) {
        debugPrint('❌ [AlbumCover] 刮削失败，未找到封面');
        return null;
      }

      final coverUrl = scrapeResult.coverUrl!;
      final lyrics = scrapeResult.lyrics;

      debugPrint('✅ [AlbumCover] 刮削成功: $coverUrl');
      if (lyrics != null) {
        debugPrint('✅ [AlbumCover] 同时获取到歌词');
      }

      // 🚀 新策略：立即返回在线封面URL，后台异步上传到NAS
      // 这样用户不用等下载+上传，立即就能看到封面

      // 5. 后台异步上传到NAS（不阻塞UI）
      _uploadCoverToNasAsync(musicName, coverUrl, lyrics);

      // 6. 立即返回在线封面URL
      debugPrint('🎯 [AlbumCover] 立即返回在线封面，后台上传中...');
      return coverUrl;
    } catch (e) {
      debugPrint('❌ [AlbumCover] 获取封面失败: $e');
      return null;
    }
  }

  /// 在线搜索并获取封面URL和歌词（使用原生QQ音乐API）
  Future<({String? coverUrl, String? lyrics})?> _scrapeAlbumCoverAndLyrics(String musicName) async {
    try {
      // 解析歌曲名（格式：歌曲名 - 歌手名）
      final parts = musicName.split(' - ');
      final songName = parts.isNotEmpty ? parts[0].trim() : musicName;

      debugPrint('🔍 [AlbumCover] 搜索: $songName');

      // 🎯 多平台备选策略：优先QQ音乐，失败后尝试酷我、网易云（与 v2.0.1 顺序一致）
      final platforms = [
        ('QQ音乐', () => _nativeSearch.searchQQ(query: songName, page: 1)),
        ('酷我', () => _nativeSearch.searchKuwo(query: songName, page: 1)),
        ('网易云', () => _nativeSearch.searchNetease(query: songName, page: 1)),
      ];

      for (final (platformName, searchFunc) in platforms) {
        try {
          debugPrint('🔍 [AlbumCover] 尝试平台: $platformName');

          final results = await searchFunc();

          if (results.isEmpty) {
            debugPrint('⚠️ [AlbumCover] $platformName 搜索无结果');
            continue;
          }

          debugPrint('🔍 [AlbumCover] $platformName 返回 ${results.length} 个结果');

          // 遍历搜索结果，找到第一个有封面的结果
          for (int i = 0; i < results.length; i++) {
            final result = results[i];

            debugPrint('🔍 [AlbumCover] $platformName 结果 ${i + 1}/${results.length}:');
            debugPrint('   - 歌曲: ${result.title}');
            debugPrint('   - 歌手: ${result.author}');
            debugPrint('   - 专辑: ${result.album}');
            debugPrint('   - 封面URL: ${result.picture ?? "无"}');

            // OnlineMusicResult 已经包含 picture 字段（封面URL）
            final coverUrl = result.picture;

            if (coverUrl != null && coverUrl.isNotEmpty) {
              // 快速验证URL是否可用
              final isValid = await _quickValidateUrl(coverUrl);
              if (isValid) {
                debugPrint('✅ [AlbumCover] $platformName 找到有效封面，停止搜索');
                debugPrint('   - 最终选择: 结果 ${i + 1}/${results.length}');
                debugPrint('   - 封面URL: $coverUrl');

                // 🎤 尝试获取歌词（仅 QQ 音乐支持）
                String? lyrics;
                if (platformName == 'QQ音乐' && result.songId != null && result.songId!.isNotEmpty) {
                  debugPrint('🎤 [AlbumCover] 尝试获取歌词: ${result.songId}');
                  lyrics = await _nativeSearch.getLyricsQQ(result.songId!);
                  if (lyrics != null && lyrics.isNotEmpty) {
                    debugPrint('✅ [AlbumCover] 歌词获取成功，长度: ${lyrics.length} 字符');
                  } else {
                    debugPrint('⚠️ [AlbumCover] 未获取到歌词');
                  }
                }

                return (coverUrl: coverUrl, lyrics: lyrics);
              } else {
                debugPrint('⚠️ [AlbumCover] $platformName 封面URL验证失败，尝试下一个结果');
              }
            } else {
              debugPrint('⚠️ [AlbumCover] $platformName 结果 ${i + 1} 无封面URL');
            }
          }

          debugPrint('⚠️ [AlbumCover] $platformName 所有结果均无可用封面');
        } catch (e) {
          debugPrint('❌ [AlbumCover] $platformName 搜索失败: $e');
        }
      }

      debugPrint('❌ [AlbumCover] 所有平台均搜索失败');
      return null;
    } catch (e) {
      debugPrint('❌ [AlbumCover] 搜索失败: $e');
      return null;
    }
  }

  /// 🔧 快速验证URL是否可用（优先HEAD，失败则降级为GET）
  Future<bool> _quickValidateUrl(String url) async {
    try {
      debugPrint('🔍 [AlbumCover] 验证URL: $url');

      // 策略1：尝试 HEAD 请求（最快，不下载内容）
      try {
        final response = await _dio.head(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 3),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'https://y.qq.com/',
            },
            validateStatus: (status) => true, // 允许所有状态码，手动判断
          ),
        );

        if (response.statusCode == 200) {
          debugPrint('✅ [AlbumCover] HEAD验证通过: 200');
          return true;
        }

        debugPrint('⚠️ [AlbumCover] HEAD请求失败: ${response.statusCode}，尝试 GET 降级验证');
      } catch (e) {
        debugPrint('⚠️ [AlbumCover] HEAD请求异常: $e，尝试 GET 降级验证');
      }

      // 策略2：如果 HEAD 失败，尝试 GET 前 1KB（某些服务器不支持 HEAD）
      try {
        final response = await _dio.get(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 5),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'https://y.qq.com/',
              'Range': 'bytes=0-1023', // 只请求前 1KB
            },
            responseType: ResponseType.bytes,
            validateStatus: (status) => status == 200 || status == 206, // 206 = Partial Content
          ),
        );

        if (response.statusCode == 200 || response.statusCode == 206) {
          debugPrint('✅ [AlbumCover] GET降级验证通过: ${response.statusCode}');
          return true;
        }

        debugPrint('❌ [AlbumCover] GET请求失败: ${response.statusCode}');
        return false;
      } catch (e) {
        debugPrint('❌ [AlbumCover] GET请求异常: $e');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [AlbumCover] URL验证失败: $e');
      return false; // 验证失败视为无效
    }
  }

  /// 下载封面并转换为base64
  Future<String?> _downloadAndConvertToBase64(String imageUrl) async {
    try {
      debugPrint('📥 [AlbumCover] 下载封面: $imageUrl');

      final response = await _dio.get<Uint8List>(
        imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://y.qq.com/',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final base64String = base64Encode(response.data!);
        debugPrint('✅ [AlbumCover] 转换完成，大小: ${response.data!.length} bytes');
        return base64String;
      }

      debugPrint('❌ [AlbumCover] 下载失败: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ [AlbumCover] 下载异常: $e');
      return null;
    }
  }

  /// 🚀 后台异步上传封面和歌词到NAS（不阻塞UI）
  void _uploadCoverToNasAsync(
    String musicName,
    String coverUrl,
    String? lyrics,
  ) {
    // 异步执行，不阻塞主流程
    Future(() async {
      try {
        debugPrint('🔄 [AlbumCover] 后台开始下载封面: $coverUrl');

        // 1. 下载封面并转换为base64
        final base64Picture = await _downloadAndConvertToBase64(coverUrl);
        if (base64Picture == null) {
          debugPrint('❌ [AlbumCover] 后台下载封面失败');
          return;
        }

        debugPrint('✅ [AlbumCover] 后台下载完成，开始上传...');

        // 2. 上传到服务器
        await _uploadAlbumCover(musicName, base64Picture, lyrics);

        debugPrint('✅ [AlbumCover] 后台上传成功');
        if (lyrics != null && lyrics.isNotEmpty) {
          debugPrint('✅ [AlbumCover] 歌词同时上传成功');
        }
      } catch (e) {
        debugPrint('❌ [AlbumCover] 后台上传异常: $e');
        // 静默失败，不影响用户体验
      }
    });
  }

  /// 上传封面和歌词到NAS服务器
  Future<void> _uploadAlbumCover(
    String musicName,
    String base64Picture, [
    String? lyrics,
  ]) async {
    debugPrint('📤 [AlbumCover] 上传封面到服务器: $musicName');

    final data = <String, dynamic>{
      'musicname': musicName,
      'picture': base64Picture,
    };

    // 如果有歌词，也一起上传
    if (lyrics != null && lyrics.isNotEmpty) {
      data['lyrics'] = lyrics;
      debugPrint('📤 [AlbumCover] 同时上传歌词（${lyrics.length} 字符）');
    }

    await _musicApi.setMusicTag(data);
  }

  /// 将内网地址替换为登录域名
  String _replaceWithLoginDomain(String nasUrl, String loginBaseUrl) {
    try {
      final loginUri = Uri.parse(loginBaseUrl);
      final nasUri = Uri.parse(nasUrl);

      final replacedUri = nasUri.replace(
        scheme: loginUri.scheme,
        host: loginUri.host,
        port: loginUri.port,
      );

      return replacedUri.toString();
    } catch (e) {
      debugPrint('❌ [AlbumCover] URL替换失败: $e');
      return nasUrl;
    }
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }
}
