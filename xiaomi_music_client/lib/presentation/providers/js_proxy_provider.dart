import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/enhanced_js_proxy_executor_service.dart';
import '../../data/models/online_music_result.dart';
import '../../data/models/js_script.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../providers/source_settings_provider.dart';
import '../providers/js_script_manager_provider.dart';

class JSProxyScriptReader {
  Future<String?> readLocal(String path) async {
    try {
      // Defer to js_script_manager logic if needed; simple read here
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }
}
// duplicate removed

/// JS代理执行器状态
class JSProxyState {
  final bool isInitialized;
  final bool isLoading;
  final String? currentScript;
  final Map<String, dynamic> supportedSources;
  final String? error;

  const JSProxyState({
    this.isInitialized = false,
    this.isLoading = false,
    this.currentScript,
    this.supportedSources = const {},
    this.error,
  });

  JSProxyState copyWith({
    bool? isInitialized,
    bool? isLoading,
    String? currentScript,
    Map<String, dynamic>? supportedSources,
    String? error,
  }) {
    return JSProxyState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      currentScript: currentScript ?? this.currentScript,
      supportedSources: supportedSources ?? this.supportedSources,
      error: error,
    );
  }
}

/// JS代理执行器Provider
class JSProxyNotifier extends StateNotifier<JSProxyState> {
  final Ref _ref;

  JSProxyNotifier(this._ref) : super(const JSProxyState()) {
    _initializeService();
  }

  final EnhancedJSProxyExecutorService _service = EnhancedJSProxyExecutorService();

  /// 初始化服务
  Future<void> _initializeService() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      await _service.initialize();

      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        error: null,
      );

      print('[JSProxyProvider] ✅ JS代理服务初始化完成');

      // 延迟自动加载，等待其他provider初始化完成
      Future.delayed(const Duration(milliseconds: 1000), () async {
        await _autoLoadSelectedScript();
      });
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '初始化失败: $e');
      print('[JSProxyProvider] ❌ 初始化失败: $e');
    }
  }

  /// 自动加载已选脚本
  Future<void> _autoLoadSelectedScript() async {
    try {
      final settings = _ref.read(sourceSettingsProvider);
      print(
        '[JSProxyProvider] 📋 检查自动加载条件: primarySource=${settings.primarySource}',
      );

      if (settings.primarySource == 'js_external') {
        final scripts = _ref.read(jsScriptManagerProvider);
        final manager = _ref.read(jsScriptManagerProvider.notifier);
        final selected = manager.selectedScript;

        print('[JSProxyProvider] 📋 脚本列表数量: ${scripts.length}');
        print('[JSProxyProvider] 📋 当前选中ID: ${manager.selectedScriptId}');
        print('[JSProxyProvider] 📋 选中脚本: ${selected?.name ?? 'null'}');

        if (selected != null) {
          print('[JSProxyProvider] 🚀 自动加载已选脚本: ${selected.name}');
          final success = await loadScriptByScript(selected);
          print('[JSProxyProvider] 📊 自动加载结果: $success');
        } else {
          print('[JSProxyProvider] ⚠️ 未选择脚本或脚本管理器未加载，跳过自动加载');
        }
      } else {
        print('[JSProxyProvider] ℹ️ 不是JS流程，跳过自动加载');
      }
    } catch (e) {
      print('[JSProxyProvider] ❌ 自动加载脚本异常: $e');
    }
  }

  /// 加载JS脚本
  Future<bool> loadScript(String scriptContent, {String? scriptName}) async {
    if (!state.isInitialized) {
      print('[JSProxyProvider] ⚠️ 服务未初始化');
      return false;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      final success = await _service.loadScript(scriptContent);

      if (success) {
        final sources = _service.getSupportedSources();

        state = state.copyWith(
          isLoading: false,
          currentScript: scriptName ?? '已加载脚本',
          supportedSources: sources,
          error: null,
        );

        print('[JSProxyProvider] ✅ 脚本加载成功: ${scriptName ?? '未命名脚本'}');
        print('[JSProxyProvider] 📋 支持的音源: ${sources.keys.join(', ')}');
        return true;
      } else {
        state = state.copyWith(isLoading: false, error: '脚本加载失败');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载异常: $e');
      print('[JSProxyProvider] ❌ 脚本加载异常: $e');
      return false;
    }
  }

  /// 根据 JsScript 条目加载脚本（支持URL/本地文件/内置）
  Future<bool> loadScriptByScript(JsScript script) async {
    try {
      String? content;
      String scriptName = script.name;

      if (script.source == JsScriptSource.localFile) {
        // 读取本地文件内容
        final manager = JSProxyScriptReader();
        content = await manager.readLocal(script.content);
      } else {
        // 视为URL，直接下载文本
        final url = script.content;
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200) {
          content = resp.body;
        }
      }

      if (content == null || content.trim().isEmpty) {
        print('[JSProxyProvider] ❌ 读取脚本内容失败');
        return false;
      }
      return await loadScript(content, scriptName: scriptName);
    } catch (e) {
      print('[JSProxyProvider] ❌ loadScriptByScript 异常: $e');
      return false;
    }
  }

  /// 从URL加载JS脚本
  Future<bool> loadScriptFromUrl(String url) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // 这里可以使用现有的网络服务获取脚本内容
      // 暂时先用简单的方式
      print('[JSProxyProvider] 🌐 从URL加载脚本: $url');

      // TODO: 实现从URL获取脚本内容的逻辑
      // final scriptContent = await fetchScriptFromUrl(url);
      // return await loadScript(scriptContent, scriptName: url);

      state = state.copyWith(isLoading: false, error: '从URL加载脚本功能待实现');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '从URL加载失败: $e');
      return false;
    }
  }

  /// 获取音乐播放链接
  Future<String?> getMusicUrl({
    required String source,
    required String songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!state.isInitialized || state.currentScript == null) {
      print('[JSProxyProvider] ⚠️ 服务未初始化或脚本未加载');
      return null;
    }

    // 检查是否支持该音源
    print('[JSProxyProvider] 🔍 当前状态检查:');
    print('[JSProxyProvider] 🔍 isInitialized: ${state.isInitialized}');
    print('[JSProxyProvider] 🔍 currentScript: ${state.currentScript}');
    print(
      '[JSProxyProvider] 🔍 supportedSources count: ${state.supportedSources.length}',
    );
    print(
      '[JSProxyProvider] 🔍 supportedSources keys: ${state.supportedSources.keys.join(', ')}',
    );

    // 尝试重新获取音源（以防状态不同步）
    if (state.supportedSources.isEmpty && state.isInitialized) {
      print('[JSProxyProvider] 🔄 音源列表为空，尝试重新获取...');
      final freshSources = _service.getSupportedSources();
      print('[JSProxyProvider] 🔄 重新获取的音源: ${freshSources.keys.join(', ')}');
      if (freshSources.isNotEmpty) {
        state = state.copyWith(supportedSources: freshSources);
        print('[JSProxyProvider] 🔄 已更新状态中的音源列表');
      }
    }

    if (!state.supportedSources.containsKey(source)) {
      print('[JSProxyProvider] ⚠️ 不支持的音源: $source');
      print(
        '[JSProxyProvider] 📋 支持的音源: ${state.supportedSources.keys.join(', ')}',
      );
      return null;
    }

    try {
      print('[JSProxyProvider] 🎵 获取音乐链接: $source/$songId/$quality');

      final url = await _service.getMusicUrl(
        source: source,
        songId: songId,
        quality: quality,
        musicInfo: musicInfo,
      );

      if (url != null) {
        print('[JSProxyProvider] ✅ 成功获取音乐链接');
        return url;
      } else {
        print('[JSProxyProvider] ❌ 获取音乐链接失败');
        return null;
      }
    } catch (e) {
      print('[JSProxyProvider] ❌ 获取音乐链接异常: $e');
      return null;
    }
  }

  /// 解析OnlineMusicResult为播放链接
  Future<OnlineMusicResult?> resolveOnlineMusicResult(
    OnlineMusicResult result, {
    String? preferredQuality,
  }) async {
    if (!state.isInitialized || state.currentScript == null) {
      return null;
    }

    try {
      // 确定使用的音质
      final quality = preferredQuality ?? '320k';

      // 使用JS代理获取真实播放链接
      final resolvedUrl = await getMusicUrl(
        source: result.platform ?? 'unknown',
        songId: result.songId ?? 'unknown',
        quality: quality,
        musicInfo: {
          'title': result.title,
          'artist': result.author,
          'album': result.album,
        },
      );

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        // 返回解析后的结果，创建新的OnlineMusicResult
        return OnlineMusicResult(
          songId: result.songId ?? '',
          title: result.title,
          author: result.author,
          url: resolvedUrl, // 使用解析后的URL
          album: result.album,
          duration: result.duration,
          platform: result.platform ?? 'unknown',
          extra: result.extra,
        );
      }

      return null;
    } catch (e) {
      print('[JSProxyProvider] ❌ 解析OnlineMusicResult失败: $e');
      return null;
    }
  }

  /// 批量解析音乐结果
  Future<List<OnlineMusicResult>> resolveMultipleResults(
    List<OnlineMusicResult> results, {
    String? preferredQuality,
    int maxConcurrent = 3,
  }) async {
    if (!state.isInitialized || state.currentScript == null) {
      return [];
    }

    final resolvedResults = <OnlineMusicResult>[];

    // 分批处理，避免过多并发请求
    for (int i = 0; i < results.length; i += maxConcurrent) {
      final batch = results.skip(i).take(maxConcurrent).toList();

      final futures = batch.map(
        (result) => resolveOnlineMusicResult(
          result,
          preferredQuality: preferredQuality,
        ),
      );

      final batchResults = await Future.wait(futures);

      // 添加成功解析的结果
      for (final resolved in batchResults) {
        if (resolved != null) {
          resolvedResults.add(resolved);
        }
      }

      // 短暂延迟，避免请求过于频繁
      if (i + maxConcurrent < results.length) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    print(
      '[JSProxyProvider] 📊 批量解析完成: ${resolvedResults.length}/${results.length}',
    );
    return resolvedResults;
  }

  /// 获取支持的音源列表
  List<String> getSupportedSourcesList() {
    return state.supportedSources.keys.toList();
  }

  /// 检查是否支持指定音源
  bool supportsSource(String source) {
    return state.supportedSources.containsKey(source);
  }

  /// 获取音源支持的音质列表
  List<String> getSupportedQualities(String source) {
    final sourceInfo = state.supportedSources[source];
    if (sourceInfo is Map && sourceInfo.containsKey('qualitys')) {
      return List<String>.from(sourceInfo['qualitys'] ?? []);
    }
    return ['128k', '320k', 'flac']; // 默认音质
  }

  /// 清除当前脚本
  void clearScript() {
    state = state.copyWith(
      currentScript: null,
      supportedSources: {},
      error: null,
    );
    print('[JSProxyProvider] 🧹 已清除当前脚本');
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

/// JS代理执行器Provider
final jsProxyProvider = StateNotifierProvider<JSProxyNotifier, JSProxyState>((
  ref,
) {
  return JSProxyNotifier(ref);
});
