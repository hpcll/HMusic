import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/online_music_result.dart';

/// Transformer for QQ Music to safely parse JSON returned with text/plain
class QQMusicTransformer extends Transformer {
  @override
  Future<String> transformRequest(RequestOptions options) async {
    final data = options.data;
    if (data == null) return '';
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody response,
  ) async {
    final List<int> chunks = <int>[];
    await for (final List<int> chunk in response.stream) {
      chunks.addAll(chunk);
    }
    final responseText = utf8.decode(chunks, allowMalformed: true);

    if (options.uri.host.contains('y.qq.com')) {
      try {
        return jsonDecode(responseText);
      } catch (_) {
        return responseText;
      }
    }

    return responseText;
  }
}

class NativeMusicSearchService {
  NativeMusicSearchService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      )..transformer = QQMusicTransformer();

  final Dio _dio;

  Future<List<OnlineMusicResult>> searchQQ({
    required String query,
    required int page,
  }) async {
    try {
      final apiUrl = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
      final payload = {
        'comm': {
          'ct': 11,
          'cv': '1003006',
          'v': '1003006',
          'os_ver': '12',
          'phonetype': '0',
          'devicelevel': '31',
          'tmeAppID': 'qqmusiclight',
          'nettype': 'NETWORK_WIFI',
        },
        'req': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicLite',
          'param': {
            'query': query,
            'search_type': 0,
            'num_per_page': 30,
            'page_num': page,
            'nqc_flag': 0,
            'grp': 1,
          },
        },
      };

      final response = await _dio.post(
        apiUrl,
        data: payload,
        options: Options(
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
            'Content-Type': 'application/json',
          },
        ),
      );

      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return <OnlineMusicResult>[];
        }
      }

      List<dynamic>? songs;
      if (data is Map &&
          data['req'] != null &&
          data['req']['data'] != null &&
          data['req']['data']['body'] != null &&
          data['req']['data']['body']['item_song'] != null) {
        songs = data['req']['data']['body']['item_song'] as List<dynamic>?;
      }

      if (songs == null || songs.isEmpty) return <OnlineMusicResult>[];

      // ✨ 临时日志：查看第一个结果的完整结构
      print('========== 🖼️  QQ音乐搜索结果示例 ==========');
      print(jsonEncode(songs.first));
      print('============================================');

      return songs.whereType<Map<String, dynamic>>().map((song) {
        final String id =
            (song['mid'] ?? song['songmid'] ?? song['id'] ?? '').toString();
        final String title = (song['title'] ?? song['name'] ?? '').toString();

        String author = '';
        final singers = song['singer'];
        if (singers is List) {
          author = singers
              .map(
                (s) =>
                    (s is Map && s['name'] != null)
                        ? s['name'].toString()
                        : s.toString(),
              )
              .join('/');
        }

        String album = '';
        String? albumPicUrl;
        final al = song['album'];
        if (al is Map) {
          if (al['name'] != null) {
            album = al['name'].toString();
          }
          // ✨ 提取专辑封面图
          // QQ音乐封面图格式：https://y.gtimg.cn/music/photo_new/T002R300x300M000{pmid}.jpg
          final pmid = al['pmid']?.toString() ?? al['mid']?.toString();
          if (pmid != null && pmid.isNotEmpty) {
            albumPicUrl =
                'https://y.gtimg.cn/music/photo_new/T002R300x300M000$pmid.jpg';
          }
        }

        int duration = 0;
        final interval = song['interval'];
        if (interval is int) duration = interval;
        if (interval is String) {
          duration = int.tryParse(interval) ?? 0;
        }

        return OnlineMusicResult(
          songId: id,
          title: title,
          author: author,
          album: album,
          duration: duration,
          platform: 'qq',
          url: '',
          picture: albumPicUrl, // ✨ 添加封面图
          extra: const {},
        );
      }).toList();
    } catch (_) {
      return <OnlineMusicResult>[];
    }
  }

  Future<List<OnlineMusicResult>> searchKuwo({
    required String query,
    required int page,
  }) async {
    try {
      final apiUrl = 'http://search.kuwo.cn/r.s';
      final response = await _dio.get(
        apiUrl,
        queryParameters: {
          'client': 'kt',
          'all': query,
          'pn': (page - 1).toString(),
          'rn': '30',
          'uid': '794762570',
          'ver': 'kwplayer_ar_9.2.2.1',
          'vipver': '1',
          'show_copyright_off': '1',
          'newver': '1',
          'ft': 'music',
          'cluster': '0',
          'strategy': '2012',
          'encoding': 'utf8',
          'rformat': 'json',
          'vermerge': '1',
          'mobi': '1',
          'issubtitle': '1',
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        options: Options(
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
            'Connection': 'Keep-Alive',
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
          },
        ),
      );

      final data = response.data;
      List<dynamic>? songs;
      if (data is Map) {
        songs = data['abslist'] as List<dynamic>?;
      } else if (data is String) {
        try {
          final decoded = jsonDecode(data);
          songs = decoded['abslist'] as List<dynamic>?;
        } catch (_) {
          songs = <dynamic>[];
        }
      }

      if (songs == null || songs.isEmpty) return <OnlineMusicResult>[];

      return songs.whereType<Map<String, dynamic>>().map((song) {
        final String rawId = (song['MUSICRID'] ?? song['rid'] ?? '').toString();
        final String id =
            rawId.startsWith('MUSIC_')
                ? rawId.replaceFirst('MUSIC_', '')
                : rawId;
        final String title = _stripHtmlTags(
          (song['SONGNAME'] ?? song['name'] ?? '').toString(),
        );
        final String author = _stripHtmlTags(
          (song['ARTIST'] ?? song['artist'] ?? '').toString(),
        );
        final String album = _stripHtmlTags(
          (song['ALBUM'] ?? song['album'] ?? '').toString(),
        );
        int duration = 0;
        final d = song['DURATION'] ?? song['duration'];
        if (d is int) duration = d;
        if (d is String) duration = int.tryParse(d) ?? 0;

        return OnlineMusicResult(
          songId: id,
          title: title,
          author: author,
          album: album,
          duration: duration,
          platform: 'kuwo',
          url: '',
          extra: const {},
        );
      }).toList();
    } catch (_) {
      return <OnlineMusicResult>[];
    }
  }

  Future<List<OnlineMusicResult>> searchNetease({
    required String query,
    required int page,
  }) async {
    try {
      final List<String> apiUrls = [
        'https://music.163.com/api/search/get',
        'https://netease-cloud-music-api.vercel.app/search',
        'https://api.imjad.cn/cloudmusic/',
      ];

      Response? resp;
      for (final apiUrl in apiUrls) {
        try {
          if (apiUrl.contains('163.com')) {
            resp = await _dio.get(
              apiUrl,
              queryParameters: {
                's': query,
                'type': 1,
                'limit': 30,
                'offset': (page - 1) * 30,
              },
            );
          } else if (apiUrl.contains('vercel.app')) {
            resp = await _dio.get(
              apiUrl,
              queryParameters: {
                'keywords': query,
                'limit': 30,
                'offset': (page - 1) * 30,
              },
            );
          } else {
            resp = await _dio.get(
              apiUrl,
              queryParameters: {
                'type': 'search',
                's': query,
                'limit': 30,
                'offset': (page - 1) * 30,
              },
            );
          }
          if (resp.statusCode == 200) break;
        } catch (_) {
          continue;
        }
      }

      if (resp == null || resp.data == null) {
        return <OnlineMusicResult>[];
      }

      final data = resp.data;
      List<dynamic>? songs;
      if (data is Map) {
        if (data['result'] != null && data['result']['songs'] != null) {
          songs = data['result']['songs'] as List<dynamic>?;
        } else if (data['songs'] != null) {
          songs = data['songs'] as List<dynamic>?;
        } else if (data['data'] is List) {
          songs = data['data'] as List<dynamic>?;
        }
      }

      if (songs == null || songs.isEmpty) return <OnlineMusicResult>[];

      // ✨ 临时日志：查看第一个结果的完整结构
      print('========== 🖼️  网易云音乐搜索结果示例 ==========');
      print(jsonEncode(songs.first));
      print('===============================================');

      return songs.whereType<Map<String, dynamic>>().map((song) {
        final String id = (song['id'] ?? '').toString();
        final String title = (song['name'] ?? '').toString();

        String author = '';
        final ar = song['ar'] ?? song['artists'];
        if (ar is List) {
          author = ar
              .map(
                (a) =>
                    (a is Map && a['name'] != null)
                        ? a['name'].toString()
                        : a.toString(),
              )
              .join('/');
        }

        String album = '';
        String? albumPicUrl;
        final al = song['al'] ?? song['album'];
        if (al is Map) {
          if (al['name'] != null) {
            album = al['name'].toString();
          }
          // ✨ 提取专辑封面图
          // 网易云音乐直接提供 picUrl
          if (al['picUrl'] != null) {
            albumPicUrl = al['picUrl'].toString();
          }
        }

        int duration = 0;
        final dt = song['dt'] ?? song['duration'];
        if (dt is int) duration = (dt / 1000).round();
        if (dt is String) duration = int.tryParse(dt) ?? 0;

        return OnlineMusicResult(
          songId: id,
          title: title,
          author: author,
          album: album,
          duration: duration,
          platform: 'wangyi',
          url: '',
          picture: albumPicUrl, // ✨ 添加封面图
          extra: const {},
        );
      }).toList();
    } catch (_) {
      return <OnlineMusicResult>[];
    }
  }

  String _stripHtmlTags(String input) {
    return input.replaceAll(RegExp(r'<[^>]+>'), '');
  }
}

final nativeMusicSearchServiceProvider = Provider<NativeMusicSearchService>((
  ref,
) {
  return NativeMusicSearchService();
});
