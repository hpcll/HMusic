import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/music.dart';
import '../../data/models/online_music_result.dart';
import '../../data/services/native_music_search_service.dart';
import 'source_settings_provider.dart';
import 'js_script_manager_provider.dart';
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
  final String? sourceApiUsed;

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

    // 使用原生搜索
    try {
      state = state.copyWith(isLoading: true, searchQuery: query, error: null);
      final native = ref.read(nativeMusicSearchServiceProvider);
      final results = await native.searchQQ(query: query, page: 1);

      // 转换为 Music 列表
      final musicList = results.map((r) => Music(
        name: '${r.title} - ${r.author}',
      )).toList();

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
      const maxWaitLoops = 40;
      while (!settingsNotifier.isLoaded && waitLoops < maxWaitLoops) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitLoops++;
      }

      if (waitLoops >= maxWaitLoops) {
        print('[XMC] ⚠️ 音源设置加载超时，使用默认设置');
      }

      var settings = ref.read(sourceSettingsProvider);

      print('[XMC] 🔧 [MusicSearch] 主要音源: ${settings.primarySource}');
      print('[XMC] 🔧 [MusicSearch] useJsForSearch: ${settings.useJsForSearch}');

      List<OnlineMusicResult> parsed = [];
      String sourceUsed = 'js_builtin';
      String? lastError;

      // 检查是否有可用的JS脚本
      final scripts = ref.read(jsScriptManagerProvider);
      final scriptManager = ref.read(jsScriptManagerProvider.notifier);
      final selectedScript = scriptManager.selectedScript;
      final jsState = ref.read(jsProxyProvider);

      // 智能等待JS脚本管理器加载完成
      int waitCount = 0;
      const maxWait = 20;
      while (scripts.isEmpty && waitCount < maxWait) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
        final currentScripts = ref.read(jsScriptManagerProvider);
        if (currentScripts.isNotEmpty) break;
      }

      if (scripts.isEmpty) {
        throw Exception('未导入JS脚本\n请先在设置中导入JS脚本才能使用音乐搜索功能');
      }
      if (selectedScript == null) {
        throw Exception('未选择JS脚本\n已导入${scripts.length}个脚本，请在设置中选择一个使用');
      }

      // 智能等待JS代理初始化完成
      if (!jsState.isInitialized) {
        print('[XMC] ⚠️ JS代理未初始化，等待初始化...');
        int jsWaitCount = 0;
        const maxJsWait = 30;
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
        print('[XMC] ⚠️ JS脚本未加载，尝试自动加载');
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

      print('[XMC] 🎵 [MusicSearch] JS流程（使用原生搜索 + JS解析播放）');
      try {
        parsed = await _searchUsingNativeByStrategy(
          query: query,
          settings: settings,
          page: 1,
        ).timeout(const Duration(seconds: 15));
        sourceUsed = 'js_builtin';

        if (parsed.isEmpty) {
          lastError = '原生搜索无结果 (策略=${settings.jsSearchStrategy})';
        } else {
          print('[XMC] 🎵 [MusicSearch] 搜索成功，返回 ${parsed.length} 首');
        }
      } catch (e) {
        lastError = '搜索失败: $e';
        print('[XMC] ❌ 搜索失败: $e');
      }

      state = state.copyWith(
        isLoading: false,
        onlineResults: parsed,
        currentPage: 1,
        hasMore: parsed.isNotEmpty,
        isLoadingMore: false,
        sourceApiUsed: sourceUsed,
        error: parsed.isEmpty ? (lastError ?? '搜索无结果') : null,
      );

      if (parsed.isNotEmpty) {
        print('[XMC] ✅ searchOnline: 成功，结果=${parsed.length}条');
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

      final settings = ref.read(sourceSettingsProvider);
      List<OnlineMusicResult> pageResults = [];
      String? loadMoreError;

      print('[XMC] 🔄 使用原生搜索加载第${nextPage}页');
      try {
        pageResults = await _searchUsingNativeByStrategy(
          query: query,
          settings: settings,
          page: nextPage,
        ).timeout(const Duration(seconds: 10));

        if (pageResults.isNotEmpty) {
          print('[XMC] 🔄 分页加载成功: ${pageResults.length} 首');
        }
      } catch (e) {
        loadMoreError = '分页失败: $e';
        print('[XMC] ❌ 分页加载失败: $e');
      }

      // 智能去重
      final existingSongIds =
          state.onlineResults.map((r) => '${r.title}_${r.author}').toSet();

      final uniqueResults =
          pageResults.where((result) {
            final key = '${result.title}_${result.author}';
            return !existingSongIds.contains(key);
          }).toList();

      if (uniqueResults.length < pageResults.length) {
        print('[XMC] 🔄 过滤了 ${pageResults.length - uniqueResults.length} 个重复结果');
      }

      final bool hasMore = uniqueResults.isNotEmpty && uniqueResults.length >= 5;
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

      if (!jsProxyState.isInitialized || jsProxyState.currentScript == null) {
        print('[XMC] ⚠️ [MusicSearch] JS代理未初始化或脚本未加载');
        return results;
      }

      final resolvedResults = await jsProxyNotifier.resolveMultipleResults(
        results,
        preferredQuality: preferredQuality ?? '320k',
        maxConcurrent: 3,
      );

      print('[XMC] ✅ [MusicSearch] JS代理解析完成: ${resolvedResults.length}/${results.length}');
      return resolvedResults.isNotEmpty ? resolvedResults : results;
    } catch (e) {
      print('[XMC] ❌ [MusicSearch] JS代理解析失败: $e');
      return results;
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

      if (!jsProxyState.isInitialized || jsProxyState.currentScript == null) {
        print('[XMC] ⚠️ [MusicSearch] JS代理不可用，返回原始结果');
        return result;
      }

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

final musicSearchProvider =
    StateNotifierProvider<MusicSearchNotifier, MusicSearchState>((ref) {
      return MusicSearchNotifier(ref);
    });
