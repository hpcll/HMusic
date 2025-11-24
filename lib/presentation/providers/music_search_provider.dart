import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/music.dart';
import '../../data/models/online_music_result.dart';
import '../../data/services/unified_api_service.dart';
import '../../data/services/native_music_search_service.dart';
import 'source_settings_provider.dart';
import 'js_script_manager_provider.dart';
import '../../data/adapters/search_adapter.dart';
// import 'js_source_provider.dart'; // JS 搜索路径已移除
import 'js_proxy_provider.dart';
import 'js_proxy_provider.dart';

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
      print(
        '[XMC] 🔧 [MusicSearch] useJsForSearch: ${settings.useJsForSearch}',
      );
      print('[XMC] 🔧 [MusicSearch] 使用统一API: ${settings.useUnifiedApi}');
      print('[XMC] 🔧 [MusicSearch] 统一API地址: ${settings.unifiedApiBase}');

      List<OnlineMusicResult> parsed = [];
      String sourceUsed = 'unified';
      String? lastError;

      // 音源选择策略（两套流程完全分离）
      // JS 流：primarySource == 'js_external' 时，搜索一律走原生（qq/酷我/网易），播放用JS解析
      final bool preferJs = settings.primarySource == 'js_external';
      final bool preferUnified = settings.primarySource == 'unified';

      print(
        '[XMC] 🎵 [MusicSearch] 音源策略: preferJs=$preferJs, preferUnified=$preferUnified',
      );

      // 🎯 如果用户选择了JS音源，检查是否有可用的脚本（统一使用 EnhancedJSProxyExecutorService）
      if (preferJs) {
        final scripts = ref.read(jsScriptManagerProvider);
        final scriptManager = ref.read(jsScriptManagerProvider.notifier);
        final selectedScript = scriptManager.selectedScript;
        final jsState = ref.read(jsProxyProvider);

        // 🎯 智能等待JS脚本管理器加载完成
        int waitCount = 0;
        const maxWait = 20; // 最多等待2秒
        while (scripts.isEmpty && waitCount < maxWait) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitCount++;
          // 重新读取脚本列表
          final currentScripts = ref.read(jsScriptManagerProvider);
          if (currentScripts.isNotEmpty) break;
        }

        if (scripts.isEmpty) {
          throw Exception('未导入JS脚本\n请先在设置中导入JS脚本才能使用JS音源搜索');
        }
        if (selectedScript == null) {
          throw Exception('未选择JS脚本\n已导入${scripts.length}个脚本，请在设置中选择一个使用');
        }

        // 🎯 智能等待JS代理初始化完成
        if (!jsState.isInitialized) {
          print('[XMC] ⚠️ JS代理未初始化，等待初始化...');
          int jsWaitCount = 0;
          const maxJsWait = 30; // 最多等待3秒
          while (!jsState.isInitialized && jsWaitCount < maxJsWait) {
            await Future.delayed(const Duration(milliseconds: 100));
            jsWaitCount++;
            final currentJsState = ref.read(jsProxyProvider);
            if (currentJsState.isInitialized) break;
          }
          if (!jsState.isInitialized) {
            throw Exception('JS运行时未初始化\n请稍候或重启应用');
          }
        }

        if (jsState.currentScript == null) {
          print('[XMC] ⚠️ JS脚本未加载，尝试自动加载(EnhancedJSProxy)');
          // 🎯 增加重试机制，最多尝试3次
          bool loadSuccess = false;
          for (int retry = 0; retry < 3 && !loadSuccess; retry++) {
            if (retry > 0) {
              print('[XMC] 🔄 第${retry + 1}次重试加载JS脚本...');
              await Future.delayed(const Duration(milliseconds: 500));
            }
            loadSuccess = await ref.read(jsProxyProvider.notifier).loadScriptByScript(selectedScript);
          }
          if (!loadSuccess) throw Exception('JS脚本加载失败\n请检查脚本内容或网络');
          print('[XMC] ✅ JS脚本自动加载成功');
        }
      }

      if (preferJs) {
        print('[XMC] 🎵 [MusicSearch] JS流程（使用原生搜索 + JS解析播放）');
        try {
          // 1. 原生搜索获取基础信息
          parsed = await _searchUsingNativeByStrategy(
            query: query,
            settings: settings,
            page: 1,
          ).timeout(const Duration(seconds: 15));
          sourceUsed = 'js_builtin';

          if (parsed.isEmpty) {
            lastError = '原生搜索无结果 (策略=${settings.jsSearchStrategy})';
          } else {
            // 搜索成功，返回结果
            // 播放时再按需解析URL（点击哪个解析哪个）
            print(
              '[XMC] 🎵 [MusicSearch] 搜索成功，返回 ${parsed.length} 首（点击播放时按需解析URL）',
            );
          }
        } catch (e) {
          lastError = 'JS流程搜索失败: $e';
          print('[XMC] ❌ JS流程搜索失败: $e');
        }
      } else if (preferUnified) {
        print('[XMC] 🎵 [MusicSearch] 统一API流程');
        try {
          parsed = await _searchUsingUnifiedAPI(
            query,
            settings,
            ref,
            page: 1,
          ).timeout(const Duration(seconds: 12));
          sourceUsed = 'unified';
        } catch (e) {
          lastError = '统一API搜索失败: $e';
          print('[XMC] ❌ 统一API搜索失败: $e');
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

  Future<List<OnlineMusicResult>> _searchUsingNativeByStrategy({
    required String query,
    required SourceSettings settings,
    required int page,
  }) async {
    final native = ref.read(nativeMusicSearchServiceProvider);
    final String strategy = settings.jsSearchStrategy;

    Future<List<OnlineMusicResult>> searchOnce(String key) async {
      switch (key) {
        case 'qq':
          return await native.searchQQ(query: query, page: page);
        case 'kuwo':
          return await native.searchKuwo(query: query, page: page);
        case 'netease':
          return await native.searchNetease(query: query, page: page);
        default:
          return <OnlineMusicResult>[];
      }
    }

    List<String> plan;
    switch (strategy) {
      case 'qqOnly':
        plan = ['qq'];
        break;
      case 'kuwoOnly':
        plan = ['kuwo'];
        break;
      case 'neteaseOnly':
        plan = ['netease'];
        break;
      case 'kuwoFirst':
        plan = ['kuwo', 'qq', 'netease'];
        break;
      case 'neteaseFirst':
        plan = ['netease', 'qq', 'kuwo'];
        break;
      case 'qqFirst':
      default:
        plan = ['qq', 'kuwo', 'netease'];
        break;
    }

    for (final key in plan) {
      try {
        final results = await searchOnce(key).timeout(
          const Duration(seconds: 10),
          onTimeout: () => <OnlineMusicResult>[],
        );
        if (results.isNotEmpty) return results;
      } catch (_) {}
    }
    return <OnlineMusicResult>[];
  }

  // JS 搜索路径已被原生搜索替代（按 jsSearchStrategy），不再保留旧的 JS 搜索实现

  // _parseDuration 已不再需要（旧JS搜索路径专用），移除

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
      final sourceUsed =
          state.sourceApiUsed ??
          (settings.primarySource == 'js_external' ? 'js_builtin' : 'unified');
      List<OnlineMusicResult> pageResults = [];
      String? loadMoreError;

      // 智能分页策略：优先使用当前成功的音源
      if (sourceUsed == 'js_builtin') {
        print('[XMC] 🔄 使用JS流程（原生搜索）加载第${nextPage}页');
        try {
          pageResults = await _searchUsingNativeByStrategy(
            query: query,
            settings: settings,
            page: nextPage,
          ).timeout(const Duration(seconds: 10));

          // 分页结果也采用后台预解析策略
          if (pageResults.isNotEmpty) {
            print('[XMC] 🔄 分页加载成功: ${pageResults.length} 首（稍后按需解析）');
          }
        } catch (e) {
          loadMoreError = 'JS流程分页失败: $e';
          print('[XMC] ❌ JS流程分页加载失败: $e');
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

  /// 使用JS代理解析音乐播放链接
  Future<List<OnlineMusicResult>> resolveWithJSProxy(
    List<OnlineMusicResult> results, {
    String? preferredQuality,
  }) async {
    try {
      print('[XMC] 🎵 [MusicSearch] 使用JS代理解析音乐链接');

      final jsProxyNotifier = ref.read(jsProxyProvider.notifier);
      final jsProxyState = ref.read(jsProxyProvider);

      // 检查JS代理是否可用
      if (!jsProxyState.isInitialized || jsProxyState.currentScript == null) {
        print('[XMC] ⚠️ [MusicSearch] JS代理未初始化或脚本未加载');
        return results; // 返回原始结果
      }

      // 批量解析音乐链接
      final resolvedResults = await jsProxyNotifier.resolveMultipleResults(
        results,
        preferredQuality: preferredQuality ?? '320k',
        maxConcurrent: 3,
      );

      print(
        '[XMC] ✅ [MusicSearch] JS代理解析完成: ${resolvedResults.length}/${results.length}',
      );
      return resolvedResults.isNotEmpty ? resolvedResults : results;
    } catch (e) {
      print('[XMC] ❌ [MusicSearch] JS代理解析失败: $e');
      return results; // 解析失败时返回原始结果
    }
  }

  /// 为单个结果解析播放链接
  Future<OnlineMusicResult?> resolveSingleResult(
    OnlineMusicResult result, {
    String? preferredQuality,
  }) async {
    try {
      print('[XMC] 🎵 [MusicSearch] 解析单个音乐链接: ${result.title}');

      final jsProxyNotifier = ref.read(jsProxyProvider.notifier);
      final jsProxyState = ref.read(jsProxyProvider);

      // 检查JS代理是否可用
      if (!jsProxyState.isInitialized || jsProxyState.currentScript == null) {
        print('[XMC] ⚠️ [MusicSearch] JS代理不可用，返回原始结果');
        return result;
      }

      // 解析单个结果
      final resolvedResult = await jsProxyNotifier.resolveOnlineMusicResult(
        result,
        preferredQuality: preferredQuality ?? '320k',
      );

      if (resolvedResult != null) {
        print('[XMC] ✅ [MusicSearch] 单个结果解析成功');
        return resolvedResult;
      } else {
        print('[XMC] ⚠️ [MusicSearch] 单个结果解析失败，返回原始结果');
        return result;
      }
    } catch (e) {
      print('[XMC] ❌ [MusicSearch] 单个结果解析异常: $e');
      return result;
    }
  }
}

// 统一API服务Provider
final unifiedApiServiceProvider = Provider<UnifiedApiService>((ref) {
  final settings = ref.watch(sourceSettingsProvider);
  return UnifiedApiService(baseUrl: settings.unifiedApiBase);
});

// 公开版本仅使用统一API，不包含YouTube代理功能

final musicSearchProvider =
    StateNotifierProvider<MusicSearchNotifier, MusicSearchState>((ref) {
      return MusicSearchNotifier(ref);
    });
