import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_id.dart';
import '../models/local_playlist.dart';
import '../../presentation/providers/local_playlist_provider.dart';

enum ImportStage { identifying, resolving, fetching, cleaning, saving }

enum ImportAction { freshImport, mergeUpdate, reimport, cancel }

enum ImportError {
  unsupportedPlatform,
  invalidUrl,
  playlistNotFound,
  fetchFailed,
  alreadyImported,
  cancelled,
}

enum SkipReason { emptyTitle, duplicate, truncated }

class ImportException implements Exception {
  final ImportError error;
  final String? platform;
  final String? detail;
  final String? debugInfo;

  const ImportException(
    this.error, {
    this.platform,
    this.detail,
    this.debugInfo,
  });

  String get userMessage {
    switch (error) {
      case ImportError.fetchFailed:
        return '${PlatformId.toDisplayName(platform ?? '')}歌单获取失败，请稍后重试';
      case ImportError.playlistNotFound:
        return '歌单不存在或已被删除';
      case ImportError.invalidUrl:
        return '链接格式无法识别，请粘贴 QQ音乐/酷我/网易云 的歌单链接';
      case ImportError.unsupportedPlatform:
        return '暂不支持该平台';
      case ImportError.alreadyImported:
        return '该歌单已导入';
      case ImportError.cancelled:
        return '已取消导入';
    }
  }

  @override
  String toString() =>
      'ImportException($error, platform=$platform, detail=$detail, debug=$debugInfo)';
}

class ImportResult {
  final bool success;
  final String? playlistName;
  final int importedCount;
  final int totalCount;
  final int mergedCount;
  final int? truncatedCount;
  final Map<SkipReason, int> skippedReasons;
  final ImportError? error;

  const ImportResult({
    required this.success,
    this.playlistName,
    this.importedCount = 0,
    this.totalCount = 0,
    this.mergedCount = 0,
    this.truncatedCount,
    this.skippedReasons = const {},
    this.error,
  });
}

class CleanResult {
  final List<LocalPlaylistSong> songs;
  final Map<SkipReason, int> skippedReasons;
  final int truncatedCount;

  const CleanResult({
    required this.songs,
    required this.skippedReasons,
    required this.truncatedCount,
  });
}

class ImportedPlaylist {
  final String name;
  final String platform;
  final String playlistId;
  final int totalCount;
  final List<LocalPlaylistSong> songs;

  const ImportedPlaylist({
    required this.name,
    required this.platform,
    required this.playlistId,
    required this.totalCount,
    required this.songs,
  });
}

class ImportedPlaylistSummary {
  final String name;
  final String platform;
  final String playlistId;
  final int totalCount;
  final String? existingPlaylistName;

  const ImportedPlaylistSummary({
    required this.name,
    required this.platform,
    required this.playlistId,
    required this.totalCount,
    this.existingPlaylistName,
  });
}

class _UrlPickResult {
  final String? url;
  final bool hasMultiple;

  const _UrlPickResult(this.url, this.hasMultiple);
}

class PlaylistImportService {
  PlaylistImportService(this._ref, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
                'Accept': 'application/json, text/plain, */*',
              },
            ),
          );

  final Ref _ref;
  final Dio _dio;
  static const int _maxImportSongs = 500;

  Future<ImportResult> importFromUrl(
    String text, {
    String modeScope = 'xiaomusic',
    CancelToken? cancelToken,
    void Function(ImportStage stage)? onStageChanged,
    void Function(String message)? onInfo,
    Future<bool> Function(ImportedPlaylistSummary summary)?
    onNeedLargePlaylistConfirm,
    Future<ImportAction> Function(ImportedPlaylistSummary summary)?
    onImportedConflict,
  }) async {
    try {
      onStageChanged?.call(ImportStage.identifying);
      _checkCancelled(cancelToken);

      final picked = _extractBestUrl(text);
      final url = picked.url;
      if (url == null || url.isEmpty) {
        throw const ImportException(ImportError.invalidUrl);
      }
      if (picked.hasMultiple) {
        onInfo?.call('检测到多个链接，已自动选择音乐平台链接');
      }

      final platform = identifyPlatform(url);
      if (platform == null) {
        throw const ImportException(ImportError.unsupportedPlatform);
      }

      onStageChanged?.call(ImportStage.resolving);
      _checkCancelled(cancelToken);

      final playlistId = await extractPlaylistId(url, platform, cancelToken);
      if (playlistId == null || playlistId.isEmpty) {
        throw const ImportException(ImportError.invalidUrl);
      }

      final notifier = _ref.read(localPlaylistProvider.notifier);
      final existingName = notifier.isPlaylistImported(
        modeScope,
        platform,
        playlistId,
      );

      onStageChanged?.call(ImportStage.fetching);
      _checkCancelled(cancelToken);

      final fetchedSummary = await fetchPlaylistSummary(
        platform,
        playlistId,
        cancelToken: cancelToken,
      );
      final summary = ImportedPlaylistSummary(
        name: fetchedSummary.name,
        platform: fetchedSummary.platform,
        playlistId: fetchedSummary.playlistId,
        totalCount: fetchedSummary.totalCount,
        existingPlaylistName: existingName,
      );

      if (summary.totalCount > _maxImportSongs) {
        final accepted =
            await onNeedLargePlaylistConfirm?.call(summary) ?? true;
        if (!accepted) {
          return const ImportResult(
            success: false,
            error: ImportError.cancelled,
          );
        }
      }

      ImportAction action = ImportAction.freshImport;
      if (existingName != null) {
        action = await onImportedConflict?.call(summary) ?? ImportAction.cancel;
        if (action == ImportAction.cancel) {
          return const ImportResult(
            success: false,
            error: ImportError.alreadyImported,
          );
        }
      }

      onStageChanged?.call(ImportStage.fetching);
      _checkCancelled(cancelToken);

      final imported = await fetchPlaylistDetail(
        platform,
        playlistId,
        cancelToken: cancelToken,
      );

      onStageChanged?.call(ImportStage.cleaning);
      _checkCancelled(cancelToken);

      final cleanResult = _cleanImportedSongs(imported.songs);
      if (cleanResult.songs.isEmpty) {
        throw const ImportException(
          ImportError.playlistNotFound,
          detail: '歌单内没有可导入的有效歌曲',
        );
      }

      onStageChanged?.call(ImportStage.saving);
      _checkCancelled(cancelToken);

      if (action == ImportAction.mergeUpdate && existingName != null) {
        final added = await notifier.mergePlaylistSongs(
          playlistName: existingName,
          newSongs: cleanResult.songs,
        );
        return ImportResult(
          success: true,
          playlistName: existingName,
          importedCount: cleanResult.songs.length,
          totalCount: imported.totalCount,
          mergedCount: added,
          truncatedCount:
              cleanResult.truncatedCount > 0
                  ? cleanResult.truncatedCount
                  : null,
          skippedReasons: cleanResult.skippedReasons,
        );
      }

      if (action == ImportAction.reimport && existingName != null) {
        await notifier.deletePlaylist(existingName, modeScope: modeScope);
      }

      await notifier.importPlaylist(
        name: imported.name,
        sourcePlatform: imported.platform,
        sourcePlaylistId: imported.playlistId,
        sourceUrl: url,
        importedAt: DateTime.now(),
        songs: cleanResult.songs,
        modeScope: modeScope,
      );

      final finalName =
          notifier.isPlaylistImported(
            modeScope,
            imported.platform,
            imported.playlistId,
          ) ??
          imported.name;

      return ImportResult(
        success: true,
        playlistName: finalName,
        importedCount: cleanResult.songs.length,
        totalCount: imported.totalCount,
        truncatedCount:
            cleanResult.truncatedCount > 0 ? cleanResult.truncatedCount : null,
        skippedReasons: cleanResult.skippedReasons,
      );
    } on ImportException catch (e) {
      debugPrint('❌ [Import] $e');
      return ImportResult(success: false, error: e.error);
    } catch (e) {
      debugPrint('❌ [Import] 未知异常: $e');
      return const ImportResult(success: false, error: ImportError.fetchFailed);
    }
  }

  _UrlPickResult _extractBestUrl(String text) {
    final matches = RegExp("https?://[^\\s<>\"']+").allMatches(text).toList();
    if (matches.isEmpty) return const _UrlPickResult(null, false);

    final urls = matches.map((m) => _sanitizeUrl(m.group(0)!)).toList();
    final musicUrls = urls.where((u) => identifyPlatform(u) != null).toList();

    if (musicUrls.isNotEmpty) {
      return _UrlPickResult(musicUrls.first, musicUrls.length > 1);
    }
    return _UrlPickResult(urls.first, urls.length > 1);
  }

  String? identifyPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('y.qq.com') ||
        lower.contains('i.y.qq.com') ||
        lower.contains('c.y.qq.com')) {
      return PlatformId.tx;
    }
    if (lower.contains('kuwo.cn')) return PlatformId.kw;
    if (lower.contains('163cn.tv') ||
        lower.contains('163.com') ||
        lower.contains('netease')) {
      return PlatformId.wy;
    }
    return null;
  }

  Future<String?> extractPlaylistId(
    String url,
    String platform,
    CancelToken? cancelToken,
  ) async {
    switch (platform) {
      case PlatformId.tx:
        final uri = Uri.parse(url);
        final queryId = uri.queryParameters['id'];
        if (queryId != null && queryId.isNotEmpty) return queryId;
        final pathMatch = RegExp(
          r'/(?:playlist|playsquare|details)/(\d+)',
        ).firstMatch(uri.path);
        if (pathMatch != null) return pathMatch.group(1);
        final segments = uri.pathSegments.where(
          (s) => RegExp(r'^\d{6,}$').hasMatch(s),
        );
        return segments.isNotEmpty ? segments.last : null;
      case PlatformId.kw:
        final match = RegExp(r'playlist_detail/(\d+)').firstMatch(url);
        if (match != null) return match.group(1);
        return Uri.parse(url).queryParameters['pid'];
      case PlatformId.wy:
        var realUrl = url;
        if (url.contains('163cn.tv')) {
          realUrl = await _followRedirect(url, cancelToken);
        }
        final uri = Uri.parse(realUrl.replaceFirst('#/', ''));
        return uri.queryParameters['id'];
      default:
        return null;
    }
  }

  Future<ImportedPlaylist> fetchPlaylistDetail(
    String platform,
    String playlistId, {
    CancelToken? cancelToken,
  }) async {
    switch (platform) {
      case PlatformId.tx:
        return _fetchQQ(playlistId, cancelToken);
      case PlatformId.kw:
        return _fetchKuwo(playlistId, cancelToken);
      case PlatformId.wy:
        return _fetchNetease(playlistId, cancelToken);
      default:
        throw const ImportException(ImportError.unsupportedPlatform);
    }
  }

  Future<ImportedPlaylistSummary> fetchPlaylistSummary(
    String platform,
    String playlistId, {
    CancelToken? cancelToken,
  }) async {
    switch (platform) {
      case PlatformId.tx:
        return _fetchQQSummary(playlistId, cancelToken);
      case PlatformId.kw:
        return _fetchKuwoSummary(playlistId, cancelToken);
      case PlatformId.wy:
        return _fetchNeteaseSummary(playlistId, cancelToken);
      default:
        throw const ImportException(ImportError.unsupportedPlatform);
    }
  }

  Future<ImportedPlaylistSummary> _fetchQQSummary(
    String id,
    CancelToken? cancelToken,
  ) {
    return _withFallback(
      platform: PlatformId.tx,
      operation: '歌单摘要',
      primary: () => _fetchQQSummaryPrimary(id, cancelToken),
      fallback: () => _fetchQQSummaryFallback(id, cancelToken),
    );
  }

  Future<ImportedPlaylistSummary> _fetchQQSummaryPrimary(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(headers: const {'Referer': 'https://y.qq.com/'});
    try {
      final resp = await _dio.get(
        'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
        queryParameters: {
          'type': 1,
          'json': 1,
          'utf8': 1,
          'onlysong': 1,
          'disstid': id,
          'format': 'json',
        },
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final cdList = (data['cdlist'] as List?) ?? const [];
      if (cdList.isEmpty) {
        final directSongNumRaw = data['songnum'] ?? data['total_song_num'];
        final directSongNum =
            directSongNumRaw is int
                ? directSongNumRaw
                : int.tryParse('${directSongNumRaw ?? ''}');
        if ((directSongNum ?? 0) > 0) {
          return ImportedPlaylistSummary(
            name: (data['dissname'] ?? data['dirname'] ?? data['title'] ?? 'QQ歌单')
                .toString(),
            platform: PlatformId.tx,
            playlistId: id,
            totalCount: directSongNum ?? 0,
          );
        }
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.tx,
          detail: 'QQ摘要主接口返回空cdlist',
          debugInfo: 'response=${resp.data}',
        );
      }

      final first = Map<String, dynamic>.from(cdList.first as Map);
      final songNumRaw = first['songnum'] ?? first['song_num'] ?? first['total'];
      final songNum =
          songNumRaw is int ? songNumRaw : int.tryParse('${songNumRaw ?? ''}');
      return ImportedPlaylistSummary(
        name: (first['dissname'] ?? first['title'] ?? 'QQ歌单').toString(),
        platform: PlatformId.tx,
        playlistId: id,
        totalCount: songNum ?? 0,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.tx,
        operation: 'QQ音乐歌单摘要获取失败',
      );
    }
  }

  Future<ImportedPlaylistSummary> _fetchQQSummaryFallback(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(headers: const {'Referer': 'https://y.qq.com/'});
    try {
      final resp = await _dio.get(
        'https://i.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
        queryParameters: {
          'type': 1,
          'json': 1,
          'utf8': 1,
          'onlysong': 1,
          'disstid': id,
          'format': 'json',
        },
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final cdList = (data['cdlist'] as List?) ?? const [];
      if (cdList.isEmpty) {
        final directSongNumRaw = data['songnum'] ?? data['total_song_num'];
        final directSongNum =
            directSongNumRaw is int
                ? directSongNumRaw
                : int.tryParse('${directSongNumRaw ?? ''}');
        if ((directSongNum ?? 0) > 0) {
          return ImportedPlaylistSummary(
            name: (data['dissname'] ?? data['dirname'] ?? data['title'] ?? 'QQ歌单')
                .toString(),
            platform: PlatformId.tx,
            playlistId: id,
            totalCount: directSongNum ?? 0,
          );
        }
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.tx,
          detail: 'QQ摘要备用接口返回空cdlist',
          debugInfo: 'response=${resp.data}',
        );
      }

      final first = Map<String, dynamic>.from(cdList.first as Map);
      final songNumRaw = first['songnum'] ?? first['song_num'] ?? first['total'];
      final songNum =
          songNumRaw is int ? songNumRaw : int.tryParse('${songNumRaw ?? ''}');
      return ImportedPlaylistSummary(
        name: (first['dissname'] ?? first['title'] ?? 'QQ歌单').toString(),
        platform: PlatformId.tx,
        playlistId: id,
        totalCount: songNum ?? 0,
      );
    } catch (e) {
      debugPrint('⚠️ [Import] QQ c/i 接口摘要失败，尝试 musicu: $e');
      return _fetchQQSummaryMusicu(id, cancelToken);
    }
  }

  Future<ImportedPlaylistSummary> _fetchQQSummaryMusicu(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(headers: const {'Referer': 'https://y.qq.com/'});
    try {
      final body = {
        'comm': {'ct': 24, 'cv': 0},
        'playlist': {
          'module': 'music.srfDissInfo.aiDissInfo',
          'method': 'fcg_musiclist_getinfo_cp',
          'param': {'disstid': int.tryParse(id) ?? id, 'song_begin': 0, 'song_num': 1},
        },
      };
      final resp = await _dio.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        data: body,
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final playlist =
          data['playlist'] is Map
              ? Map<String, dynamic>.from(data['playlist'] as Map)
              : <String, dynamic>{};
      final inner =
          playlist['data'] is Map
              ? Map<String, dynamic>.from(playlist['data'] as Map)
              : <String, dynamic>{};
      final songNumRaw = inner['songnum'] ?? inner['song_num'] ?? inner['total_song_num'];
      final songNum =
          songNumRaw is int ? songNumRaw : int.tryParse('${songNumRaw ?? ''}');
      if (inner.isEmpty || (songNum ?? 0) <= 0) {
        throw ImportException(
          ImportError.playlistNotFound,
          platform: PlatformId.tx,
          detail: 'QQ musicu 摘要为空',
          debugInfo: 'response=${resp.data}',
        );
      }
      return ImportedPlaylistSummary(
        name: (inner['dissname'] ?? inner['title'] ?? 'QQ歌单').toString(),
        platform: PlatformId.tx,
        playlistId: id,
        totalCount: songNum ?? 0,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.tx,
        operation: 'QQ musicu 摘要获取失败',
      );
    }
  }

  Future<ImportedPlaylistSummary> _fetchKuwoSummary(
    String id,
    CancelToken? cancelToken,
  ) {
    return _withFallback(
      platform: PlatformId.kw,
      operation: '歌单摘要',
      primary: () => _fetchKuwoSummaryPrimary(id, cancelToken),
      fallback: () => _fetchKuwoSummaryFallback(id, cancelToken),
    );
  }

  Future<ImportedPlaylistSummary> _fetchKuwoSummaryPrimary(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = await _buildKuwoOptions(cancelToken: cancelToken);
    try {
      final resp = await _dio.get(
        'https://www.kuwo.cn/api/www/playlist/playListInfo',
        queryParameters: {'pid': id, 'pn': 1, 'rn': 1},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final dataObj =
          data['data'] is Map
              ? Map<String, dynamic>.from(data['data'] as Map)
              : <String, dynamic>{};
      if (dataObj.isEmpty) {
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.kw,
          detail: '酷我歌单摘要返回空数据（可能触发反爬）',
          debugInfo: 'response=${resp.data}',
        );
      }

      final totalRaw = dataObj['total'] ?? dataObj['totalNum'] ?? dataObj['num'];
      final total =
          totalRaw is int ? totalRaw : int.tryParse('${totalRaw ?? ''}');
      return ImportedPlaylistSummary(
        name: (dataObj['name'] ?? dataObj['title'] ?? '酷我歌单').toString(),
        platform: PlatformId.kw,
        playlistId: id,
        totalCount: total ?? 0,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.kw,
        operation: '酷我歌单摘要获取失败',
      );
    }
  }

  Future<ImportedPlaylistSummary> _fetchKuwoSummaryFallback(
    String id,
    CancelToken? cancelToken,
  ) async {
    try {
      final options = await _buildKuwoOptions(
        cancelToken: cancelToken,
        forceRefreshToken: true,
      );
      final resp = await _dio.get(
        'https://www.kuwo.cn/api/www/playlist/playListInfo',
        queryParameters: {'pid': id, 'pn': 1, 'rn': 1},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final dataObj =
          data['data'] is Map
              ? Map<String, dynamic>.from(data['data'] as Map)
              : <String, dynamic>{};
      if (dataObj.isEmpty) {
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.kw,
          detail: '酷我歌单摘要备用接口返回空数据',
          debugInfo: 'response=${resp.data}',
        );
      }

      final totalRaw = dataObj['total'] ?? dataObj['totalNum'] ?? dataObj['num'];
      final total =
          totalRaw is int ? totalRaw : int.tryParse('${totalRaw ?? ''}');
      return ImportedPlaylistSummary(
        name: (dataObj['name'] ?? dataObj['title'] ?? '酷我歌单').toString(),
        platform: PlatformId.kw,
        playlistId: id,
        totalCount: total ?? 0,
      );
    } catch (e) {
      debugPrint('⚠️ [Import] 酷我新接口摘要失败，尝试老接口: $e');
      return _fetchKuwoSummaryLegacy(id, cancelToken);
    }
  }

  Future<ImportedPlaylistSummary> _fetchNeteaseSummary(
    String id,
    CancelToken? cancelToken,
  ) {
    return _withFallback(
      platform: PlatformId.wy,
      operation: '歌单摘要',
      primary: () => _fetchNeteaseSummaryPrimary(id, cancelToken),
      fallback: () => _fetchNeteaseSummaryFallback(id, cancelToken),
    );
  }

  Future<ImportedPlaylistSummary> _fetchNeteaseSummaryPrimary(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(
      headers: const {'Referer': 'https://music.163.com/'},
    );
    try {
      final resp = await _dio.get(
        'https://music.163.com/api/playlist/detail',
        queryParameters: {'id': id, 'n': 1},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final playlist =
          data['playlist'] is Map
              ? Map<String, dynamic>.from(data['playlist'] as Map)
              : <String, dynamic>{};
      if (playlist.isEmpty) {
        throw const ImportException(ImportError.playlistNotFound);
      }
      final countRaw = playlist['trackCount'] ?? playlist['track_count'];
      final total =
          countRaw is int ? countRaw : int.tryParse('${countRaw ?? ''}');
      return ImportedPlaylistSummary(
        name: (playlist['name'] ?? '网易云歌单').toString(),
        platform: PlatformId.wy,
        playlistId: id,
        totalCount: total ?? 0,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.wy,
        operation: '网易云歌单摘要获取失败',
      );
    }
  }

  Future<ImportedPlaylistSummary> _fetchNeteaseSummaryFallback(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(
      headers: const {'Referer': 'https://music.163.com/'},
    );
    try {
      final resp = await _dio.get(
        'https://music.163.com/api/v6/playlist/detail',
        queryParameters: {'id': id, 'n': 1},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final playlist =
          data['playlist'] is Map
              ? Map<String, dynamic>.from(data['playlist'] as Map)
              : <String, dynamic>{};
      if (playlist.isEmpty) {
        throw const ImportException(ImportError.playlistNotFound);
      }
      final countRaw = playlist['trackCount'] ?? playlist['track_count'];
      final total =
          countRaw is int ? countRaw : int.tryParse('${countRaw ?? ''}');
      return ImportedPlaylistSummary(
        name: (playlist['name'] ?? '网易云歌单').toString(),
        platform: PlatformId.wy,
        playlistId: id,
        totalCount: total ?? 0,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.wy,
        operation: '网易云歌单摘要备用接口获取失败',
      );
    }
  }

  Future<ImportedPlaylist> _fetchQQ(String id, CancelToken? cancelToken) {
    return _withFallback(
      platform: PlatformId.tx,
      operation: '歌单详情',
      primary: () => _fetchQQPrimary(id, cancelToken),
      fallback: () => _fetchQQFallback(id, cancelToken),
    );
  }

  Future<ImportedPlaylist> _fetchQQPrimary(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(headers: const {'Referer': 'https://y.qq.com/'});

    try {
      final resp = await _dio.get(
        'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
        queryParameters: {
          'type': 1,
          'json': 1,
          'utf8': 1,
          'onlysong': 0,
          'disstid': id,
          'format': 'json',
        },
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final cdList = (data['cdlist'] as List?) ?? const [];
      if (cdList.isEmpty) {
        final directSongs = (data['songlist'] as List?) ?? const [];
        if (directSongs.isNotEmpty) {
          final songs =
              directSongs
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .map((song) {
                    final songId =
                        (song['songmid'] ?? song['mid'] ?? song['id'] ?? '')
                            .toString();
                    final title =
                        (song['songname'] ?? song['title'] ?? '').toString();
                    final singers = (song['singer'] as List?) ?? const [];
                    final artist = singers
                        .whereType<Map>()
                        .map((e) => e['name']?.toString() ?? '')
                        .where((e) => e.isNotEmpty)
                        .join('/');
                    final coverMid =
                        (song['albummid'] ?? song['albumMid'] ?? '').toString();
                    final cover =
                        coverMid.isEmpty
                            ? null
                            : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$coverMid.jpg';
                    final interval = song['interval'];
                    final duration =
                        interval is int
                            ? interval
                            : int.tryParse('${interval ?? ''}');
                    return LocalPlaylistSong.fromOnlineMusic(
                      title: title,
                      artist: artist,
                      platform: PlatformId.tx,
                      songId: songId,
                      coverUrl: cover,
                      duration: duration,
                    );
                  })
                  .toList();
          return ImportedPlaylist(
            name:
                (data['dissname'] ?? data['dirname'] ?? data['title'] ?? 'QQ歌单')
                    .toString(),
            platform: PlatformId.tx,
            playlistId: id,
            totalCount: songs.length,
            songs: songs,
          );
        }
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.tx,
          detail: 'QQ详情主接口返回空cdlist',
          debugInfo: 'response=${resp.data}',
        );
      }
      final first = Map<String, dynamic>.from(cdList.first as Map);
      final songs =
          ((first['songlist'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .map((song) {
                final songId =
                    (song['songmid'] ?? song['mid'] ?? song['id'] ?? '')
                        .toString();
                final title =
                    (song['songname'] ?? song['title'] ?? '').toString();
                final singers = (song['singer'] as List?) ?? const [];
                final artist = singers
                    .whereType<Map>()
                    .map((e) => e['name']?.toString() ?? '')
                    .where((e) => e.isNotEmpty)
                    .join('/');
                final coverMid =
                    (song['albummid'] ?? song['albumMid'] ?? '').toString();
                final cover =
                    coverMid.isEmpty
                        ? null
                        : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$coverMid.jpg';
                final interval = song['interval'];
                final duration =
                    interval is int
                        ? interval
                        : int.tryParse('${interval ?? ''}');
                return LocalPlaylistSong.fromOnlineMusic(
                  title: title,
                  artist: artist,
                  platform: PlatformId.tx,
                  songId: songId,
                  coverUrl: cover,
                  duration: duration,
                );
              })
              .toList();

      return ImportedPlaylist(
        name: (first['dissname'] ?? first['title'] ?? 'QQ歌单').toString(),
        platform: PlatformId.tx,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.tx,
        operation: 'QQ音乐歌单获取失败',
      );
    }
  }

  Future<ImportedPlaylist> _fetchQQFallback(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(headers: const {'Referer': 'https://y.qq.com/'});

    try {
      final resp = await _dio.get(
        'https://i.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
        queryParameters: {
          'type': 1,
          'json': 1,
          'utf8': 1,
          'onlysong': 0,
          'disstid': id,
          'format': 'json',
        },
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final cdList = (data['cdlist'] as List?) ?? const [];
      if (cdList.isEmpty) {
        final directSongs = (data['songlist'] as List?) ?? const [];
        if (directSongs.isNotEmpty) {
          final songs =
              directSongs
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .map((song) {
                    final songId =
                        (song['songmid'] ?? song['mid'] ?? song['id'] ?? '')
                            .toString();
                    final title =
                        (song['songname'] ?? song['title'] ?? '').toString();
                    final singers = (song['singer'] as List?) ?? const [];
                    final artist = singers
                        .whereType<Map>()
                        .map((e) => e['name']?.toString() ?? '')
                        .where((e) => e.isNotEmpty)
                        .join('/');
                    final coverMid =
                        (song['albummid'] ?? song['albumMid'] ?? '').toString();
                    final cover =
                        coverMid.isEmpty
                            ? null
                            : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$coverMid.jpg';
                    final interval = song['interval'];
                    final duration =
                        interval is int
                            ? interval
                            : int.tryParse('${interval ?? ''}');
                    return LocalPlaylistSong.fromOnlineMusic(
                      title: title,
                      artist: artist,
                      platform: PlatformId.tx,
                      songId: songId,
                      coverUrl: cover,
                      duration: duration,
                    );
                  })
                  .toList();
          return ImportedPlaylist(
            name:
                (data['dissname'] ?? data['dirname'] ?? data['title'] ?? 'QQ歌单')
                    .toString(),
            platform: PlatformId.tx,
            playlistId: id,
            totalCount: songs.length,
            songs: songs,
          );
        }
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.tx,
          detail: 'QQ详情备用接口返回空cdlist',
          debugInfo: 'response=${resp.data}',
        );
      }
      final first = Map<String, dynamic>.from(cdList.first as Map);
      final songs =
          ((first['songlist'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .map((song) {
                final songId =
                    (song['songmid'] ?? song['mid'] ?? song['id'] ?? '')
                        .toString();
                final title =
                    (song['songname'] ?? song['title'] ?? '').toString();
                final singers = (song['singer'] as List?) ?? const [];
                final artist = singers
                    .whereType<Map>()
                    .map((e) => e['name']?.toString() ?? '')
                    .where((e) => e.isNotEmpty)
                    .join('/');
                final coverMid =
                    (song['albummid'] ?? song['albumMid'] ?? '').toString();
                final cover =
                    coverMid.isEmpty
                        ? null
                        : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$coverMid.jpg';
                final interval = song['interval'];
                final duration =
                    interval is int
                        ? interval
                        : int.tryParse('${interval ?? ''}');
                return LocalPlaylistSong.fromOnlineMusic(
                  title: title,
                  artist: artist,
                  platform: PlatformId.tx,
                  songId: songId,
                  coverUrl: cover,
                  duration: duration,
                );
              })
              .toList();

      return ImportedPlaylist(
        name: (first['dissname'] ?? first['title'] ?? 'QQ歌单').toString(),
        platform: PlatformId.tx,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      debugPrint('⚠️ [Import] QQ c/i 接口详情失败，尝试 musicu: $e');
      return _fetchQQDetailMusicu(id, cancelToken);
    }
  }

  Future<ImportedPlaylist> _fetchQQDetailMusicu(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(headers: const {'Referer': 'https://y.qq.com/'});
    try {
      final body = {
        'comm': {'ct': 24, 'cv': 0},
        'playlist': {
          'module': 'music.srfDissInfo.aiDissInfo',
          'method': 'fcg_musiclist_getinfo_cp',
          'param': {'disstid': int.tryParse(id) ?? id, 'song_begin': 0, 'song_num': 1000},
        },
      };
      final resp = await _dio.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        data: body,
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final playlist =
          data['playlist'] is Map
              ? Map<String, dynamic>.from(data['playlist'] as Map)
              : <String, dynamic>{};
      final inner =
          playlist['data'] is Map
              ? Map<String, dynamic>.from(playlist['data'] as Map)
              : <String, dynamic>{};
      final rawSongs = (inner['songlist'] as List?) ?? const [];
      if (rawSongs.isEmpty) {
        throw ImportException(
          ImportError.playlistNotFound,
          platform: PlatformId.tx,
          detail: 'QQ musicu 详情为空',
          debugInfo: 'response=${resp.data}',
        );
      }
      final songs =
          rawSongs.map((e) => Map<String, dynamic>.from(e as Map)).map((song) {
            final singers = (song['singer'] as List?) ?? const [];
            final artist = singers
                .whereType<Map>()
                .map((e) => e['name']?.toString() ?? '')
                .where((e) => e.isNotEmpty)
                .join('/');
            final songId =
                (song['songmid'] ?? song['mid'] ?? song['id'] ?? '').toString();
            final title = (song['songname'] ?? song['title'] ?? '').toString();
            final coverMid =
                (song['albummid'] ?? song['albumMid'] ?? '').toString();
            final cover =
                coverMid.isEmpty
                    ? null
                    : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$coverMid.jpg';
            final interval = song['interval'];
            final duration =
                interval is int ? interval : int.tryParse('${interval ?? ''}');
            return LocalPlaylistSong.fromOnlineMusic(
              title: title,
              artist: artist,
              platform: PlatformId.tx,
              songId: songId,
              coverUrl: cover,
              duration: duration,
            );
          }).toList();
      return ImportedPlaylist(
        name: (inner['dissname'] ?? inner['title'] ?? 'QQ歌单').toString(),
        platform: PlatformId.tx,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.tx,
        operation: 'QQ musicu 详情获取失败',
      );
    }
  }

  Future<ImportedPlaylist> _fetchKuwo(
    String id,
    CancelToken? cancelToken,
  ) {
    return _withFallback(
      platform: PlatformId.kw,
      operation: '歌单详情',
      primary: () => _fetchKuwoPrimary(id, cancelToken),
      fallback: () => _fetchKuwoFallback(id, cancelToken),
    );
  }

  Future<ImportedPlaylist> _fetchKuwoPrimary(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = await _buildKuwoOptions(cancelToken: cancelToken);
    try {
      final resp = await _dio.get(
        'https://www.kuwo.cn/api/www/playlist/playListInfo',
        queryParameters: {'pid': id, 'pn': 1, 'rn': 1000},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final dataObj =
          data['data'] is Map
              ? Map<String, dynamic>.from(data['data'] as Map)
              : <String, dynamic>{};
      final musicList = (dataObj['musicList'] as List?) ?? const [];
      if (musicList.isEmpty) {
        throw const ImportException(ImportError.playlistNotFound);
      }
      final songs =
          musicList.map((e) => Map<String, dynamic>.from(e as Map)).map((song) {
            final songId = (song['rid'] ?? song['musicrid'] ?? '').toString();
            final normalizedId =
                songId.startsWith('MUSIC_') ? songId.substring(6) : songId;
            final durationRaw = song['duration'] ?? song['DURATION'];
            final duration =
                durationRaw is int
                    ? durationRaw
                    : int.tryParse('${durationRaw ?? ''}');
            return LocalPlaylistSong.fromOnlineMusic(
              title: (song['name'] ?? song['songName'] ?? '').toString(),
              artist: (song['artist'] ?? song['artistName'] ?? '').toString(),
              platform: PlatformId.kw,
              songId: normalizedId,
              coverUrl: song['pic']?.toString(),
              duration: duration,
            );
          }).toList();

      return ImportedPlaylist(
        name: (dataObj['name'] ?? dataObj['title'] ?? '酷我歌单').toString(),
        platform: PlatformId.kw,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.kw,
        operation: '酷我歌单获取失败',
      );
    }
  }

  Future<ImportedPlaylist> _fetchKuwoFallback(
    String id,
    CancelToken? cancelToken,
  ) async {
    try {
      final options = await _buildKuwoOptions(
        cancelToken: cancelToken,
        forceRefreshToken: true,
      );
      final resp = await _dio.get(
        'https://www.kuwo.cn/api/www/playlist/playListInfo',
        queryParameters: {'pid': id, 'pn': 1, 'rn': 1000},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final dataObj =
          data['data'] is Map
              ? Map<String, dynamic>.from(data['data'] as Map)
              : <String, dynamic>{};
      final musicList = (dataObj['musicList'] as List?) ?? const [];
      if (musicList.isEmpty) {
        throw const ImportException(ImportError.playlistNotFound);
      }
      final songs =
          musicList.map((e) => Map<String, dynamic>.from(e as Map)).map((song) {
            final songId = (song['rid'] ?? song['musicrid'] ?? '').toString();
            final normalizedId =
                songId.startsWith('MUSIC_') ? songId.substring(6) : songId;
            final durationRaw = song['duration'] ?? song['DURATION'];
            final duration =
                durationRaw is int
                    ? durationRaw
                    : int.tryParse('${durationRaw ?? ''}');
            return LocalPlaylistSong.fromOnlineMusic(
              title: (song['name'] ?? song['songName'] ?? '').toString(),
              artist: (song['artist'] ?? song['artistName'] ?? '').toString(),
              platform: PlatformId.kw,
              songId: normalizedId,
              coverUrl: song['pic']?.toString(),
              duration: duration,
            );
          }).toList();

      return ImportedPlaylist(
        name: (dataObj['name'] ?? dataObj['title'] ?? '酷我歌单').toString(),
        platform: PlatformId.kw,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      debugPrint('⚠️ [Import] 酷我新接口详情失败，尝试老接口: $e');
      return _fetchKuwoDetailLegacy(id, cancelToken);
    }
  }

  Future<ImportedPlaylistSummary> _fetchKuwoSummaryLegacy(
    String id,
    CancelToken? cancelToken,
  ) async {
    try {
      final resp = await _dio.get(
        'https://nplserver.kuwo.cn/pl.svc',
        queryParameters: {
          'op': 'getlistinfo',
          'pid': id,
          'pn': 0,
          'rn': 1,
          'encode': 'utf8',
          'keyset': 'pl2012',
          'vipver': 'MUSIC_9.0.5.0_W1',
          'newver': 1,
        },
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      if (data.isEmpty) {
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.kw,
          detail: '酷我老接口摘要返回空数据',
          debugInfo: 'response=${resp.data}',
        );
      }

      final totalRaw = data['total'] ?? data['totalnum'] ?? data['num'];
      final total =
          totalRaw is int ? totalRaw : int.tryParse('${totalRaw ?? ''}');
      return ImportedPlaylistSummary(
        name: (data['name'] ?? data['title'] ?? '酷我歌单').toString(),
        platform: PlatformId.kw,
        playlistId: id,
        totalCount: total ?? 0,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.kw,
        operation: '酷我老接口摘要获取失败',
      );
    }
  }

  Future<ImportedPlaylist> _fetchKuwoDetailLegacy(
    String id,
    CancelToken? cancelToken,
  ) async {
    try {
      final resp = await _dio.get(
        'https://nplserver.kuwo.cn/pl.svc',
        queryParameters: {
          'op': 'getlistinfo',
          'pid': id,
          'pn': 0,
          'rn': 1000,
          'encode': 'utf8',
          'keyset': 'pl2012',
          'vipver': 'MUSIC_9.0.5.0_W1',
          'newver': 1,
        },
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      if (data.isEmpty) {
        throw ImportException(
          ImportError.fetchFailed,
          platform: PlatformId.kw,
          detail: '酷我老接口详情返回空数据',
          debugInfo: 'response=${resp.data}',
        );
      }
      final rawList = (data['musiclist'] as List?) ?? (data['musicList'] as List?) ?? const [];
      if (rawList.isEmpty) {
        throw ImportException(
          ImportError.playlistNotFound,
          platform: PlatformId.kw,
          detail: '酷我老接口未返回歌曲列表',
          debugInfo: 'response=${resp.data}',
        );
      }
      final songs =
          rawList.map((e) => Map<String, dynamic>.from(e as Map)).map((song) {
            final songId =
                (song['id'] ?? song['rid'] ?? song['musicrid'] ?? '').toString();
            final duration = _parseDurationSeconds(
              song['duration'] ?? song['songTimeMinutes'],
            );
            return LocalPlaylistSong.fromOnlineMusic(
              title: (song['name'] ?? song['songName'] ?? '').toString(),
              artist: (song['artist'] ?? song['artistName'] ?? '').toString(),
              platform: PlatformId.kw,
              songId: songId,
              coverUrl: (song['pic'] ?? song['pic100'] ?? song['albumpic'])?.toString(),
              duration: duration,
            );
          }).toList();

      return ImportedPlaylist(
        name: (data['name'] ?? data['title'] ?? '酷我歌单').toString(),
        platform: PlatformId.kw,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.kw,
        operation: '酷我老接口详情获取失败',
      );
    }
  }

  Future<ImportedPlaylist> _fetchNetease(
    String id,
    CancelToken? cancelToken,
  ) {
    return _withFallback(
      platform: PlatformId.wy,
      operation: '歌单详情',
      primary: () => _fetchNeteasePrimary(id, cancelToken),
      fallback: () => _fetchNeteaseFallback(id, cancelToken),
    );
  }

  Future<ImportedPlaylist> _fetchNeteasePrimary(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(
      headers: const {'Referer': 'https://music.163.com/'},
    );
    try {
      final resp = await _dio.get(
        'https://music.163.com/api/playlist/detail',
        queryParameters: {'id': id},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final playlist =
          data['playlist'] is Map
              ? Map<String, dynamic>.from(data['playlist'] as Map)
              : <String, dynamic>{};
      final tracks = (playlist['tracks'] as List?) ?? const [];
      if (tracks.isEmpty) {
        throw const ImportException(ImportError.playlistNotFound);
      }
      final songs =
          tracks.map((e) => Map<String, dynamic>.from(e as Map)).map((song) {
            final artists =
                (song['ar'] as List?) ?? (song['artists'] as List?) ?? const [];
            final artist = artists
                .whereType<Map>()
                .map((e) => e['name']?.toString() ?? '')
                .where((e) => e.isNotEmpty)
                .join('/');
            final album =
                song['al'] is Map
                    ? Map<String, dynamic>.from(song['al'] as Map)
                    : <String, dynamic>{};
            final dt = song['dt'] ?? song['duration'];
            int? duration;
            if (dt is int) {
              duration = (dt / 1000).round();
            } else {
              duration = int.tryParse('${dt ?? ''}');
            }
            return LocalPlaylistSong.fromOnlineMusic(
              title: (song['name'] ?? '').toString(),
              artist: artist,
              platform: PlatformId.wy,
              songId: (song['id'] ?? '').toString(),
              coverUrl: album['picUrl']?.toString(),
              duration: duration,
            );
          }).toList();

      return ImportedPlaylist(
        name: (playlist['name'] ?? '网易云歌单').toString(),
        platform: PlatformId.wy,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.wy,
        operation: '网易云歌单获取失败',
      );
    }
  }

  Future<ImportedPlaylist> _fetchNeteaseFallback(
    String id,
    CancelToken? cancelToken,
  ) async {
    final options = Options(
      headers: const {'Referer': 'https://music.163.com/'},
    );
    try {
      final resp = await _dio.get(
        'https://music.163.com/api/v6/playlist/detail',
        queryParameters: {'id': id},
        options: options,
        cancelToken: cancelToken,
      );
      final data = _decodeData(resp.data);
      final playlist =
          data['playlist'] is Map
              ? Map<String, dynamic>.from(data['playlist'] as Map)
              : <String, dynamic>{};
      final tracks = (playlist['tracks'] as List?) ?? const [];
      if (tracks.isEmpty) {
        throw const ImportException(ImportError.playlistNotFound);
      }
      final songs =
          tracks.map((e) => Map<String, dynamic>.from(e as Map)).map((song) {
            final artists =
                (song['ar'] as List?) ?? (song['artists'] as List?) ?? const [];
            final artist = artists
                .whereType<Map>()
                .map((e) => e['name']?.toString() ?? '')
                .where((e) => e.isNotEmpty)
                .join('/');
            final album =
                song['al'] is Map
                    ? Map<String, dynamic>.from(song['al'] as Map)
                    : <String, dynamic>{};
            final dt = song['dt'] ?? song['duration'];
            int? duration;
            if (dt is int) {
              duration = (dt / 1000).round();
            } else {
              duration = int.tryParse('${dt ?? ''}');
            }
            return LocalPlaylistSong.fromOnlineMusic(
              title: (song['name'] ?? '').toString(),
              artist: artist,
              platform: PlatformId.wy,
              songId: (song['id'] ?? '').toString(),
              coverUrl: album['picUrl']?.toString(),
              duration: duration,
            );
          }).toList();

      return ImportedPlaylist(
        name: (playlist['name'] ?? '网易云歌单').toString(),
        platform: PlatformId.wy,
        playlistId: id,
        totalCount: songs.length,
        songs: songs,
      );
    } catch (e) {
      throw _normalizeImportException(
        e,
        platform: PlatformId.wy,
        operation: '网易云歌单备用接口获取失败',
      );
    }
  }

  CleanResult _cleanImportedSongs(List<LocalPlaylistSong> raw) {
    final seen = <String>{};
    final cleaned = <LocalPlaylistSong>[];
    final skipped = <SkipReason, int>{};

    for (final song in raw) {
      if ((song.title).trim().isEmpty) {
        skipped[SkipReason.emptyTitle] =
            (skipped[SkipReason.emptyTitle] ?? 0) + 1;
        continue;
      }
      if (song.songId == null || song.songId!.isEmpty) {
        skipped[SkipReason.emptyTitle] =
            (skipped[SkipReason.emptyTitle] ?? 0) + 1;
        continue;
      }
      final key = '${PlatformId.normalize(song.platform ?? '')}:${song.songId}';
      if (!seen.add(key)) {
        skipped[SkipReason.duplicate] =
            (skipped[SkipReason.duplicate] ?? 0) + 1;
        continue;
      }
      cleaned.add(song);
    }

    int truncated = 0;
    if (cleaned.length > _maxImportSongs) {
      truncated = cleaned.length - _maxImportSongs;
      cleaned.removeRange(_maxImportSongs, cleaned.length);
      skipped[SkipReason.truncated] = truncated;
    }

    return CleanResult(
      songs: cleaned,
      skippedReasons: skipped,
      truncatedCount: truncated,
    );
  }

  Future<String> _followRedirect(
    String shortUrl,
    CancelToken? cancelToken,
  ) async {
    final client = Dio(
      BaseOptions(
        followRedirects: false,
        validateStatus: (s) => s != null && s >= 200 && s < 400,
      ),
    );
    var current = shortUrl;
    for (int i = 0; i < 5; i++) {
      final resp = await client.get(current, cancelToken: cancelToken);
      final location = resp.headers.value('location');
      if (location == null || location.isEmpty) break;
      if (location.startsWith('http')) {
        current = location;
      } else {
        final base = Uri.parse(current);
        current = base.resolve(location).toString();
      }
    }
    return current;
  }

  Map<String, dynamic> _decodeData(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      final trimmed = raw.trim();
      try {
        return jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        final jsonp = RegExp(r'^[^(]*\((.*)\)\s*;?$').firstMatch(trimmed);
        if (jsonp != null) {
          return jsonDecode(jsonp.group(1)!) as Map<String, dynamic>;
        }
      }
    }
    return <String, dynamic>{};
  }

  String _sanitizeUrl(String url) {
    var result = url.replaceAll(RegExp(r'''[)）\]】》>,，。、；;！!？?"'“”’`]+$'''), '');
    result = _fixBracketPairing(result, '(', ')');
    result = _fixBracketPairing(result, '（', '）');
    return result;
  }

  String _fixBracketPairing(String url, String open, String close) {
    final openCount = open.allMatches(url).length;
    final closeCount = close.allMatches(url).length;
    var result = url;
    for (int i = 0; i < closeCount - openCount; i++) {
      if (result.endsWith(close)) {
        result = result.substring(0, result.length - close.length);
      }
    }
    return result;
  }

  int? _parseDurationSeconds(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final plain = int.tryParse(text);
    if (plain != null) return plain;
    final parts = text.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m != null && s != null) return m * 60 + s;
    }
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final s = int.tryParse(parts[2]);
      if (h != null && m != null && s != null) return h * 3600 + m * 60 + s;
    }
    return null;
  }

  Future<T> _withFallback<T>({
    required String platform,
    required String operation,
    required Future<T> Function() primary,
    required Future<T> Function() fallback,
  }) async {
    try {
      return await primary();
    } catch (e) {
      final primaryError = _normalizeImportException(
        e,
        platform: platform,
        operation: '$operation 主接口失败',
      );
      if (primaryError.error == ImportError.cancelled ||
          primaryError.error == ImportError.unsupportedPlatform) {
        throw primaryError;
      }

      debugPrint(
        '⚠️ [Import] ${PlatformId.toDisplayName(platform)}$operation主接口失败，尝试备用接口: ${primaryError.detail ?? primaryError.debugInfo ?? e}',
      );
      try {
        return await fallback();
      } catch (e2) {
        throw _normalizeImportException(
          e2,
          platform: platform,
          operation: '$operation 备用接口失败',
        );
      }
    }
  }

  ImportException _normalizeImportException(
    Object error, {
    required String platform,
    required String operation,
  }) {
    if (error is ImportException) {
      if (error.platform != null && error.detail != null) {
        return error;
      }
      return ImportException(
        error.error,
        platform: error.platform ?? platform,
        detail: error.detail ?? operation,
        debugInfo: error.debugInfo,
      );
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel ||
          CancelToken.isCancel(error)) {
        return const ImportException(ImportError.cancelled);
      }
      final status = error.response?.statusCode;
      if (status == 404 || status == 410) {
        return const ImportException(ImportError.playlistNotFound);
      }
      final type = error.type.name;
      final body = error.response?.data?.toString() ?? '';
      final hasIllegal =
          body.toLowerCase().contains('illegal') ||
          body.contains('request is illegal');
      return ImportException(
        ImportError.fetchFailed,
        platform: platform,
        detail:
            hasIllegal
                ? '$operation（酷我接口触发风控）'
                : '$operation（HTTP ${status ?? '-'} / $type）',
        debugInfo: 'message=${error.message}; body=$body',
      );
    }

    return ImportException(
      ImportError.fetchFailed,
      platform: platform,
      detail: operation,
      debugInfo: error.toString(),
    );
  }

  void _checkCancelled(CancelToken? token) {
    if (token?.isCancelled == true) {
      throw const ImportException(ImportError.cancelled);
    }
  }

  Future<Options> _buildKuwoOptions({
    CancelToken? cancelToken,
    bool forceRefreshToken = false,
  }) async {
    String? kwToken;
    if (forceRefreshToken) {
      kwToken = await _fetchKuwoToken(cancelToken: cancelToken);
    } else {
      kwToken = await _fetchKuwoToken(cancelToken: cancelToken);
    }
    final token = kwToken ?? DateTime.now().millisecondsSinceEpoch.toString();
    return Options(
      headers: {
        'Referer': 'https://www.kuwo.cn/',
        'Origin': 'https://www.kuwo.cn',
        'Cookie': 'kw_token=$token',
        'csrf': token,
      },
    );
  }

  Future<String?> _fetchKuwoToken({CancelToken? cancelToken}) async {
    try {
      final resp = await _dio.get(
        'https://www.kuwo.cn/',
        options: Options(
          headers: const {
            'Referer': 'https://www.kuwo.cn/',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
        cancelToken: cancelToken,
      );
      final setCookies = resp.headers['set-cookie'] ?? const [];
      for (final item in setCookies) {
        final match = RegExp(r'kw_token=([^;]+)').firstMatch(item);
        if (match != null && (match.group(1)?.isNotEmpty ?? false)) {
          return match.group(1);
        }
      }
    } catch (_) {
      // ignore and fallback to generated token
    }
    return null;
  }
}

final playlistImportServiceProvider = Provider<PlaylistImportService>((ref) {
  final injectedDio = ref.watch(playlistImportDioProvider);
  return PlaylistImportService(ref, dio: injectedDio);
});

final playlistImportDioProvider = Provider<Dio?>((ref) => null);
