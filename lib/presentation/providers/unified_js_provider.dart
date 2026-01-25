import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/unified_js_runtime_service.dart';
import '../../data/models/js_script.dart';

/// 统一JS运行时状态
class UnifiedJsState {
  final bool isInitialized;
  final bool isLoading;
  final JsScript? loadedScript;
  final String? error;
  final DateTime? lastLoadTime;
  
  const UnifiedJsState({
    this.isInitialized = false,
    this.isLoading = false,
    this.loadedScript,
    this.error,
    this.lastLoadTime,
  });
  
  UnifiedJsState copyWith({
    bool? isInitialized,
    bool? isLoading,
    JsScript? loadedScript,
    String? error,
    DateTime? lastLoadTime,
    bool clearError = false,
  }) {
    return UnifiedJsState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      loadedScript: loadedScript ?? this.loadedScript,
      error: clearError ? null : (error ?? this.error),
      lastLoadTime: lastLoadTime ?? this.lastLoadTime,
    );
  }
  
  /// 是否已准备好使用
  bool get isReady => isInitialized && loadedScript != null && !isLoading;
  
  @override
  String toString() {
    return 'UnifiedJsState(initialized: $isInitialized, loading: $isLoading, '
           'script: ${loadedScript?.name}, error: $error)';
  }
}

/// 统一JS运行时Provider
class UnifiedJsNotifier extends StateNotifier<UnifiedJsState> {
  final UnifiedJsRuntimeService _service = UnifiedJsRuntimeService();
  
  UnifiedJsNotifier() : super(const UnifiedJsState()) {
    _initialize();
  }
  
  /// 初始化JS运行时
  Future<void> _initialize() async {
    print('[UnifiedJsProvider] 🔧 开始初始化...');
    
    try {
      await _service.initialize();
      
      state = state.copyWith(
        isInitialized: true,
        clearError: true,
      );
      
      print('[UnifiedJsProvider] ✅ 初始化成功');
    } catch (e) {
      state = state.copyWith(
        isInitialized: false,
        error: '初始化失败: $e',
      );
      
      print('[UnifiedJsProvider] ❌ 初始化失败: $e');
    }
  }
  
  /// 加载JS脚本（幂等操作）
  /// 
  /// 如果脚本已加载，直接返回成功
  /// 如果是新脚本，则加载并更新状态
  Future<bool> loadScript(JsScript script, {String? cookieNetease, String? cookieTencent}) async {
    // 如果已经加载了同一个脚本，直接返回成功
    if (state.loadedScript?.id == script.id && !state.isLoading) {
      print('[UnifiedJsProvider] ✅ 脚本已加载: ${script.name}');
      return true;
    }
    
    // 确保已初始化
    if (!state.isInitialized) {
      print('[UnifiedJsProvider] ⚠️ 运行时未初始化，先初始化...');
      await _initialize();
      
      if (!state.isInitialized) {
        print('[UnifiedJsProvider] ❌ 初始化失败，无法加载脚本');
        return false;
      }
    }
    
    print('[UnifiedJsProvider] 📥 开始加载脚本: ${script.name}');
    
    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );
    
    try {
      final success = await _service.loadScript(
        script,
        cookieNetease: cookieNetease,
        cookieTencent: cookieTencent,
      );
      
      if (success) {
        state = state.copyWith(
          isLoading: false,
          loadedScript: script,
          lastLoadTime: DateTime.now(),
          clearError: true,
        );
        
        print('[UnifiedJsProvider] ✅ 脚本加载成功: ${script.name}');
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: '脚本加载失败，请检查脚本内容',
        );
        
        print('[UnifiedJsProvider] ❌ 脚本加载失败');
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '加载异常: $e',
      );
      
      print('[UnifiedJsProvider] ❌ 加载异常: $e');
      return false;
    }
  }
  
  /// 重新加载当前脚本（清除缓存）
  Future<bool> reloadCurrentScript() async {
    final script = state.loadedScript;
    if (script == null) {
      print('[UnifiedJsProvider] ⚠️ 没有已加载的脚本可重新加载');
      return false;
    }
    
    return await reloadScript(script);
  }
  
  /// 重新加载指定脚本（清除缓存）
  Future<bool> reloadScript(JsScript script, {String? cookieNetease, String? cookieTencent}) async {
    print('[UnifiedJsProvider] 🔄 清除缓存并重新加载: ${script.name}');
    
    try {
      // 清除缓存
      await _service.clearCache();
      
      // 重新加载
      state = state.copyWith(loadedScript: null);
      return await loadScript(script, cookieNetease: cookieNetease, cookieTencent: cookieTencent);
      
    } catch (e) {
      state = state.copyWith(
        error: '重新加载失败: $e',
      );
      
      print('[UnifiedJsProvider] ❌ 重新加载失败: $e');
      return false;
    }
  }
  
  /// 清除所有缓存
  Future<void> clearAllCache() async {
    print('[UnifiedJsProvider] 🧹 清除所有缓存');
    
    try {
      await _service.clearCache();
      
      state = state.copyWith(
        loadedScript: null,
        lastLoadTime: null,
        clearError: true,
      );
      
      print('[UnifiedJsProvider] ✅ 缓存已清除');
    } catch (e) {
      print('[UnifiedJsProvider] ⚠️ 清除缓存失败: $e');
    }
  }
  
  /// 清除错误状态
  void clearError() {
    state = state.copyWith(clearError: true);
  }
  
  /// 执行JS代码
  String? evaluate(String jsCode) {
    if (!state.isReady) {
      print('[UnifiedJsProvider] ⚠️ 运行时未准备好');
      return null;
    }
    
    return _service.evaluateToString(jsCode);
  }
  
  /// 检查脚本是否已加载
  bool isScriptLoaded(String scriptId) {
    return state.loadedScript?.id == scriptId;
  }
  
  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

/// 统一JS运行时Provider
final unifiedJsProvider = StateNotifierProvider<UnifiedJsNotifier, UnifiedJsState>((ref) {
  return UnifiedJsNotifier();
});

/// 便捷访问：是否已准备好
final jsReadyProvider = Provider<bool>((ref) {
  final state = ref.watch(unifiedJsProvider);
  return state.isReady;
});

/// 便捷访问：当前加载的脚本
final currentLoadedScriptProvider = Provider<JsScript?>((ref) {
  final state = ref.watch(unifiedJsProvider);
  return state.loadedScript;
});