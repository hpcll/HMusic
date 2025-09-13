import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/music.dart';
import '../../data/models/online_music_result.dart';
import '../../data/services/unified_api_service.dart';
import 'source_settings_provider.dart';
import '../../data/adapters/search_adapter.dart';
import 'js_source_provider.dart';

class MusicSearchState {
  final List<Music> searchResults;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final List<OnlineMusicResult> onlineResults;
  final int currentPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? sourceApiUsed; // 'js_builtin' or 'unified'

  const MusicSearchState({
    this.searchResults = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.onlineResults = const [],
    this.currentPage = 1,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.sourceApiUsed,
  });

  MusicSearchState copyWith({
    List<Music>? searchResults,
    bool? isLoading,
    String? error,
    String? searchQuery,
    List<OnlineMusicResult>? onlineResults,
    int? currentPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? sourceApiUsed,
  }) {
    return MusicSearchState(
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      onlineResults: onlineResults ?? this.onlineResults,
      currentPage: currentPage ?? this.currentPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      sourceApiUsed: sourceApiUsed ?? this.sourceApiUsed,
    );
  }
}

class MusicSearchNotifier extends StateNotifier<MusicSearchState> {
  final Ref ref;

  MusicSearchNotifier(this.ref) : super(const MusicSearchState());

  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: [], searchQuery: '', error: null);
      return;
    }

    // 仅保留统一API，不再依赖本地索引
    // 统一API下无需预先读取服务，这里仅等待设置加载

    try {
      state = state.copyWith(isLoading: true, searchQuery: query, error: null);
      final unified = ref.read(unifiedApiServiceProvider);
      final results = await unified.searchMusic(query: query, platform: 'qq');
      final musicList = SearchAdapter.parse(results);

      state = state.copyWith(
        searchResults: musicList,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        searchResults: [],
      );
    }
  }

  // 第三方在线搜索
  Future<void> searchOnline(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(onlineResults: [], searchQuery: '', error: null);
      return;
    }

    try {
      print('[XMC] 🔍 searchOnline: start query="$query"');
      state = state.copyWith(
        isLoading: true,
        searchQuery: query,
        error: null,
        currentPage: 1,
        isLoadingMore: false,
        hasMore: true,
      );

      // 智能等待音源设置加载，带有超时保护
      final settingsNotifier = ref.read(sourceSettingsProvider.notifier);
      int waitLoops = 0;
      const maxWaitLoops = 40; // 增加等待时间但加入超时保护
      while (!settingsNotifier.isLoaded && waitLoops < maxWaitLoops) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitLoops++;
      }

      if (waitLoops >= maxWaitLoops) {
        print('[XMC] ⚠️ 音源设置加载超时，使用默认设置');
      }

      var settings = ref.read(sourceSettingsProvider);

      print('[XMC] 🔧 [MusicSearch] 主要音源: ${settings.primarySource}');
      // JS音源是否启用由 primarySource 控制，不再单独依赖 enabled
      print(
        '[XMC] 🔧 [MusicSearch] JS音源启用(由primarySource推断): ${settings.primarySource == 'js_external'}',
      );
      print('[XMC] 🔧 [MusicSearch] 使用统一API: ${settings.useUnifiedApi}');
      print('[XMC] 🔧 [MusicSearch] 统一API地址: ${settings.unifiedApiBase}');

      List<OnlineMusicResult> parsed = [];
      String sourceUsed = 'unified';
      String? lastError;

      // 智能音源选择策略
      final bool preferJs = settings.primarySource == 'js_external';
      final bool hasUnifiedApi =
          settings.useUnifiedApi && settings.unifiedApiBase.isNotEmpty;

      print(
        '[XMC] 🎵 [MusicSearch] 音源策略: preferJs=$preferJs, hasUnifiedApi=$hasUnifiedApi',
      );

      // 策略 1：优先使用用户选择的主要音源
      if (preferJs) {
        print('[XMC] 🎵 [MusicSearch] 尝试JS外置音源');
        try {
          parsed = await _searchUsingJsSource(
            query,
            settings,
            ref,
            page: 1,
          ).timeout(const Duration(seconds: 15));
          if (parsed.isNotEmpty) {
            sourceUsed = 'js_builtin';
            print('[XMC] ✅ JS音源搜索成功，结果: ${parsed.length}条');
          }
        } catch (e) {
          lastError = 'JS音源失败: $e';
          print('[XMC] ❌ JS音源搜索失败: $e');
        }
      }

      // 策略 2：如果主要音源失败或无结果，尝试备用音源
      if (parsed.isEmpty && hasUnifiedApi) {
        print('[XMC] 🔄 [MusicSearch] 尝试统一API备用音源');
        try {
          parsed = await _searchUsingUnifiedAPI(
            query,
            settings,
            ref,
            page: 1,
          ).timeout(const Duration(seconds: 12));
          if (parsed.isNotEmpty) {
            sourceUsed = 'unified';
            print('[XMC] ✅ 统一API搜索成功，结果: ${parsed.length}条');
          }
        } catch (e) {
          lastError =
              (lastError != null) ? '$lastError; 统一API失败: $e' : '统一API失败: $e';
          print('[XMC] ❌ 统一API搜索失败: $e');
        }
      }

      // 策略 3：如果主要是统一API但失败，尝试JS作为备用
      if (parsed.isEmpty && !preferJs && settings.primarySource == 'unified') {
        print('[XMC] 🔄 [MusicSearch] 统一API失败，尝试JS备用音源');
        try {
          parsed = await _searchUsingJsSource(
            query,
            settings,
            ref,
            page: 1,
          ).timeout(const Duration(seconds: 10));
          if (parsed.isNotEmpty) {
            sourceUsed = 'js_builtin';
            print('[XMC] ✅ JS备用音源搜索成功，结果: ${parsed.length}条');
          }
        } catch (e) {
          lastError =
              (lastError != null) ? '$lastError; JS备用失败: $e' : 'JS备用失败: $e';
          print('[XMC] ❌ JS备用音源搜索失败: $e');
        }
      }

      // 更新状态，包括错误信息
      state = state.copyWith(
        isLoading: false,
        onlineResults: parsed,
        currentPage: 1,
        hasMore: parsed.isNotEmpty,
        isLoadingMore: false,
        sourceApiUsed: sourceUsed,
        error: parsed.isEmpty ? (lastError ?? '所有音源都无结果') : null,
      );

      if (parsed.isNotEmpty) {
        print('[XMC] ✅ searchOnline: 成功，结果=${parsed.length}条，使用音源=$sourceUsed');
      } else {
        print('[XMC] ❌ searchOnline: 失败，错误=$lastError');
      }
    } catch (e) {
      print('[XMC] 🔍 searchOnline: error=$e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        onlineResults: [],
      );
    }
  }

  // JS音源搜索和统一API搜索

  /// 使用JS音源进行搜索（带重试机制）
  Future<List<OnlineMusicResult>> _searchUsingJsSource(
    String query,
    SourceSettings settings,
    Ref ref, {
    required int page,
  }) async {
    print('🎵 [MusicSearch] JS音源模式');

    // 智能重试机制
    int maxRetries = 2;
    List<String> attemptLog = [];

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          print('[XMC] 🔄 JS音源第${attempt + 1}次尝试...');
          await Future.delayed(Duration(milliseconds: 500 * attempt)); // 递增延迟
        }

        // 尝试 WebView JS
        try {
          final webSvc = await ref
              .read(webviewJsSourceServiceProvider.future)
              .timeout(const Duration(seconds: 3));
          if (webSvc != null) {
            final results = await webSvc
                .search(
                  query,
                  platform: 'auto', // JS 模式下让脚本自适应平台
                  page: page,
                )
                .timeout(
                  Duration(seconds: 15 - attempt * 2), // 递减超时时间
                  onTimeout: () => <Map<String, dynamic>>[],
                );

            if (results.isNotEmpty) {
              print('[XMC] ✅ [MusicSearch] WebView JS返回 ${results.length} 个结果');
              final converted =
                  results.map((item) {
                    return OnlineMusicResult(
                      songId: (item['songmid'] ?? item['id'] ?? '').toString(),
                      title: (item['title'] ?? '未知标题').toString(),
                      author:
                          (item['artist'] ?? item['singer'] ?? '未知艺术家')
                              .toString(),
                      url: (item['url'] ?? item['link'] ?? '').toString(),
                      album: (item['album'] ?? '').toString(),
                      duration: _parseDuration(item['duration']),
                      platform:
                          (item['platform'] ?? settings.platform).toString(),
                      extra: const {'sourceApi': 'js_builtin'},
                    );
                  }).toList();
              return converted;
            } else {
              attemptLog.add('WebView JS无结果');
            }
          }
        } catch (e) {
          attemptLog.add('WebView JS异常: $e');
          print('[XMC] ⚠️ [MusicSearch] WebView JS搜索异常: $e');
        }

        // 回退到 LocalJS
        try {
          final jsService = await ref
              .read(jsSourceServiceProvider.future)
              .timeout(const Duration(seconds: 2));
          if (jsService != null && jsService.isReady) {
            final results = await jsService
                .search(
                  query,
                  platform:
                      settings.platform == 'auto' ? 'qq' : settings.platform,
                  page: page,
                )
                .timeout(
                  Duration(seconds: 12 - attempt * 2),
                  onTimeout: () => <Map<String, dynamic>>[],
                );

            if (results.isNotEmpty) {
              print('[XMC] ✅ [MusicSearch] LocalJS 返回 ${results.length} 个结果');
              final converted =
                  results.map((item) {
                    return OnlineMusicResult(
                      songId: item['id']?.toString() ?? '',
                      title: item['title']?.toString() ?? '未知标题',
                      author: item['artist']?.toString() ?? '未知艺术家',
                      url: item['url']?.toString() ?? '',
                      album: item['album']?.toString() ?? '',
                      duration: _parseDuration(item['duration']),
                      platform: item['platform']?.toString() ?? 'js',
                      extra: const {'sourceApi': 'js_builtin'},
                    );
                  }).toList();
              return converted;
            } else {
              attemptLog.add('LocalJS无结果');
            }
          } else {
            attemptLog.add('LocalJS不可用');
          }
        } catch (e) {
          attemptLog.add('LocalJS异常: $e');
          print('[XMC] ❌ [MusicSearch] LocalJS 搜索异常: $e');
        }
      } catch (e) {
        attemptLog.add('第${attempt + 1}次尝试失败: $e');
        print('[XMC] ❌ [MusicSearch] JS音源第${attempt + 1}次尝试失败: $e');
      }
    }

    // 所有尝试都失败
    print('[XMC] ❌ [MusicSearch] JS音源所有尝试都失败: ${attemptLog.join('; ')}');
    return [];
  }

  /// 解析持续时间
  int _parseDuration(dynamic duration) {
    if (duration == null) return 0;
    if (duration is int) return duration;
    if (duration is double) return duration.round();
    if (duration is String) {
      // 尝试解析 "mm:ss" 格式
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return minutes * 60 + seconds;
      }
      // 尝试直接解析数字
      return int.tryParse(duration) ?? 0;
    }
    return 0;
  }

  /// 使用统一API进行搜索（带重试和平台回退）
  Future<List<OnlineMusicResult>> _searchUsingUnifiedAPI(
    String query,
    SourceSettings settings,
    Ref ref, {
    required int page,
  }) async {
    print('🎵 [MusicSearch] 统一API模式');

    final unifiedService = ref.read(unifiedApiServiceProvider);

    // 智能平台选择和回退策略
    final primaryPlatform =
        settings.platform == 'auto' ? 'qq' : settings.platform;
    final fallbackPlatforms =
        [
          'qq',
          'wangyi',
          'kugou',
          'kuwo',
        ].where((p) => p != primaryPlatform).toList();

    List<String> attemptLog = [];

    // 尝试主要平台
    for (int retry = 0; retry < 2; retry++) {
      try {
        if (retry > 0) {
          print('[XMC] 🔄 统一API主平台($primaryPlatform)第${retry + 1}次重试...');
          await Future.delayed(Duration(milliseconds: 300 * retry));
        }

        final results = await unifiedService
            .searchMusic(query: query, platform: primaryPlatform, page: page)
            .timeout(
              Duration(seconds: 12 - retry * 2),
              onTimeout: () => <OnlineMusicResult>[],
            );

        if (results.isNotEmpty) {
          print(
            '[XMC] ✅ [MusicSearch] 统一API($primaryPlatform)返回 ${results.length} 个结果',
          );
          return results;
        } else {
          attemptLog.add('$primaryPlatform无结果');
        }
      } catch (e) {
        attemptLog.add('$primaryPlatform异常: $e');
        print('[XMC] ⚠️ [MusicSearch] 统一API($primaryPlatform)异常: $e');
      }
    }

    // 尝试备用平台
    for (final platform in fallbackPlatforms.take(2)) {
      // 只尝试前2个备用平台
      try {
        print('[XMC] 🔄 [MusicSearch] 尝试备用平台: $platform');

        final results = await unifiedService
            .searchMusic(query: query, platform: platform, page: page)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => <OnlineMusicResult>[],
            );

        if (results.isNotEmpty) {
          print(
            '[XMC] ✅ [MusicSearch] 备用平台($platform)返回 ${results.length} 个结果',
          );
          return results;
        } else {
          attemptLog.add('$platform无结果');
        }
      } catch (e) {
        attemptLog.add('$platform异常: $e');
        print('[XMC] ⚠️ [MusicSearch] 备用平台($platform)异常: $e');
      }
    }

    print('[XMC] ❌ [MusicSearch] 统一API所有平台都失败: ${attemptLog.join('; ')}');
    return [];
  }

  /// 智能分页加载下一页
  Future<void> loadMore() async {
    final query = state.searchQuery.trim();
    if (query.isEmpty ||
        state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore) {
      print('[XMC] 🔄 跳过分页加载: 条件不满足');
      return;
    }

    final nextPage = state.currentPage + 1;
    print('[XMC] 🔄 开始加载第${nextPage}页...');

    try {
      state = state.copyWith(isLoadingMore: true, error: null);

      // 读取当前设置
      final settings = ref.read(sourceSettingsProvider);

      // 使用与首次搜索相同的音源策略，确保一致性
      final sourceUsed = state.sourceApiUsed ?? 'unified';
      List<OnlineMusicResult> pageResults = [];
      String? loadMoreError;

      // 智能分页策略：优先使用当前成功的音源
      if (sourceUsed == 'js_builtin') {
        print('[XMC] 🔄 使用JS音源加载第${nextPage}页');
        try {
          pageResults = await _searchUsingJsSource(
            query,
            settings,
            ref,
            page: nextPage,
          ).timeout(const Duration(seconds: 10));

          // 如果JS音源无结果，且不是强制JS模式，尝试统一API
          if (pageResults.isEmpty && settings.useUnifiedApi) {
            print('[XMC] 🔄 JS音源无结果，尝试统一API分页');
            pageResults = await _searchUsingUnifiedAPI(
              query,
              settings,
              ref,
              page: nextPage,
            ).timeout(const Duration(seconds: 8));
          }
        } catch (e) {
          loadMoreError = 'JS音源分页失败: $e';
          print('[XMC] ❌ JS音源分页加载失败: $e');
        }
      } else {
        print('[XMC] 🔄 使用统一API加载第${nextPage}页');
        try {
          pageResults = await _searchUsingUnifiedAPI(
            query,
            settings,
            ref,
            page: nextPage,
          ).timeout(const Duration(seconds: 8));
        } catch (e) {
          loadMoreError = '统一API分页失败: $e';
          print('[XMC] ❌ 统一API分页加载失败: $e');
        }
      }

      // 智能去重：避免重复结果
      final existingSongIds =
          state.onlineResults.map((r) => '${r.title}_${r.author}').toSet();

      final uniqueResults =
          pageResults.where((result) {
            final key = '${result.title}_${result.author}';
            return !existingSongIds.contains(key);
          }).toList();

      if (uniqueResults.length < pageResults.length) {
        print(
          '[XMC] 🔄 过滤了 ${pageResults.length - uniqueResults.length} 个重复结果',
        );
      }

      final bool hasMore =
          uniqueResults.isNotEmpty &&
          uniqueResults.length >= 5; // 至少5个结果才认为还有更多
      final List<OnlineMusicResult> merged = List.of(state.onlineResults)
        ..addAll(uniqueResults);

      state = state.copyWith(
        onlineResults: merged,
        isLoadingMore: false,
        hasMore: hasMore,
        currentPage: uniqueResults.isNotEmpty ? nextPage : state.currentPage,
        error: uniqueResults.isEmpty ? loadMoreError : null,
      );

      if (uniqueResults.isNotEmpty) {
        print('[XMC] ✅ 第${nextPage}页加载成功，新增 ${uniqueResults.length} 个结果');
      } else {
        print('[XMC] 📄 第${nextPage}页无更多结果，停止分页');
      }
    } catch (e) {
      print('[XMC] ❌ 分页加载异常: $e');
      state = state.copyWith(
        isLoadingMore: false,
        hasMore: false,
        error: '分页加载失败: $e',
      );
    }
  }

  void clearSearch() {
    state = state.copyWith(searchResults: [], searchQuery: '', error: null);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// 统一API服务Provider
final unifiedApiServiceProvider = Provider<UnifiedApiService>((ref) {
  final settings = ref.watch(sourceSettingsProvider);
  return UnifiedApiService(baseUrl: settings.unifiedApiBase);
});

// 移除YouTube代理Provider，仅保留统一API

final musicSearchProvider =
    StateNotifierProvider<MusicSearchNotifier, MusicSearchState>((ref) {
      return MusicSearchNotifier(ref);
    });
