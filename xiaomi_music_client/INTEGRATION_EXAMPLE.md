# 集成示例：音乐搜索页面使用新的统一JS服务

## 概述

本文档展示如何在音乐搜索页面中集成新的 `UnifiedJsRuntimeService`。

---

## 完整代码示例

### 1. 更新搜索页面构建方法

在 `lib/presentation/pages/music_search_page.dart` 中：

```dart
import '../widgets/js_loading_indicator.dart';
import '../providers/unified_js_provider.dart';

@override
Widget build(BuildContext context) {
  final searchState = ref.watch(musicSearchProvider);
  
  return Scaffold(
    key: const ValueKey('music_search_scaffold'),
    resizeToAvoidBottomInset: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: JsLoadingIndicator(
        // 添加重试回调
        onRetry: () async {
          final script = ref.read(jsScriptManagerProvider.notifier).selectedScript;
          if (script != null) {
            await ref.read(unifiedJsProvider.notifier).reloadScript(script);
          }
        },
        // 包装原有内容
        child: _buildContent(searchState),
      ),
    ),
  );
}
```

### 2. 在AppBar添加JS状态指示

```dart
AppBar(
  title: const Text('音乐搜索'),
  actions: [
    // 添加JS状态徽章
    const JsStatusBadge(),
    const SizedBox(width: 8),
    // ... 其他按钮
  ],
)
```

---

## 更新音乐搜索Provider

### 方式A：完全使用新服务（推荐）

创建一个新的搜索实现：

```dart
// lib/data/services/unified_music_search_service.dart

import 'dart:convert';
import 'unified_js_runtime_service.dart';

class UnifiedMusicSearchService {
  final UnifiedJsRuntimeService _jsService = UnifiedJsRuntimeService();
  
  /// 搜索音乐
  Future<List<Map<String, dynamic>>> search({
    required String keyword,
    String platform = 'auto',
    int page = 1,
  }) async {
    // 确保JS已初始化
    if (!_jsService.isInitialized) {
      print('[UnifiedSearch] JS未初始化');
      return [];
    }
    
    // 构建搜索JS代码
    final searchJs = _buildSearchScript(keyword, platform, page);
    
    // 执行搜索
    final resultStr = _jsService.evaluateToString(searchJs);
    
    if (resultStr == null || resultStr == '[]') {
      print('[UnifiedSearch] 搜索无结果');
      return [];
    }
    
    // 解析结果
    try {
      final List<dynamic> data = jsonDecode(resultStr);
      return data
          .where((e) => e is Map)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (e) {
      print('[UnifiedSearch] 解析结果失败: $e');
      return [];
    }
  }
  
  String _buildSearchScript(String keyword, String platform, int page) {
    // 安全的关键词转义
    final safeKeyword = keyword.replaceAll("'", "\\'").replaceAll('"', '\\"');
    
    // 平台列表
    final platforms = platform == 'auto' 
        ? ['qq', 'netease', 'kuwo', 'kugou', 'migu']
        : [platform];
    
    return '''
      (function(){
        try {
          var platforms = ${jsonEncode(platforms)};
          var keyword = '$safeKeyword';
          var page = $page;
          
          // 尝试标准搜索函数
          var searchFunctions = ['search', 'musicSearch', 'searchMusic'];
          
          for (var i = 0; i < searchFunctions.length; i++) {
            var funcName = searchFunctions[i];
            try {
              var func = (typeof eval === 'function') ? eval(funcName) : null;
              if (typeof func === 'function') {
                for (var j = 0; j < platforms.length; j++) {
                  var result = func(platforms[j], keyword, page);
                  
                  // 处理不同的结果格式
                  if (Array.isArray(result) && result.length > 0) {
                    return JSON.stringify(result);
                  } else if (result && result.data && Array.isArray(result.data)) {
                    return JSON.stringify(result.data);
                  } else if (result && result.list && Array.isArray(result.list)) {
                    return JSON.stringify(result.list);
                  }
                }
              }
            } catch(e) {
              console.warn('[Search] 函数', funcName, '执行失败:', e);
            }
          }
          
          // 尝试module.exports格式
          if (typeof module !== 'undefined' && module.exports) {
            if (typeof module.exports.search === 'function') {
              var query = { keyword: keyword, page: page, type: 'music' };
              var res = module.exports.search(query);
              if (res && res.data && Array.isArray(res.data)) {
                return JSON.stringify(res.data);
              }
            }
          }
          
          console.warn('[Search] 所有搜索方法都失败');
          return '[]';
          
        } catch(e) {
          console.error('[Search] 搜索脚本异常:', e);
          return '[]';
        }
      })()
    ''';
  }
}
```

### 方式B：在现有Provider中集成

更新 `lib/presentation/providers/music_search_provider.dart`:

```dart
import '../../../data/services/unified_music_search_service.dart';
import '../unified_js_provider.dart';

class MusicSearchNotifier extends StateNotifier<MusicSearchState> {
  final Ref _ref;
  final UnifiedMusicSearchService _searchService = UnifiedMusicSearchService();
  
  // ... 其他代码 ...
  
  Future<void> searchOnline(String keyword, {String? platform}) async {
    if (keyword.trim().isEmpty) return;
    
    state = state.copyWith(
      isLoading: true,
      error: null,
      onlineResults: [],
    );
    
    try {
      // 检查JS是否准备好
      final jsState = _ref.read(unifiedJsProvider);
      if (!jsState.isReady) {
        state = state.copyWith(
          isLoading: false,
          error: 'JS音源未加载，请稍候或检查设置',
        );
        return;
      }
      
      // 执行搜索
      final results = await _searchService.search(
        keyword: keyword.trim(),
        platform: platform ?? 'auto',
        page: 1,
      );
      
      // 转换为OnlineMusicResult
      final musicResults = results.map((item) {
        return OnlineMusicResult(
          songId: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? item['name']?.toString() ?? '',
          author: item['artist']?.toString() ?? item['singer']?.toString() ?? '',
          album: item['album']?.toString() ?? '',
          duration: _parseDuration(item['duration']),
          platform: item['platform']?.toString() ?? platform ?? 'unknown',
          url: item['url']?.toString() ?? '',
          extra: item,
        );
      }).toList();
      
      state = state.copyWith(
        isLoading: false,
        onlineResults: musicResults,
        error: null,
      );
      
      print('[MusicSearch] 搜索完成，找到 ${musicResults.length} 个结果');
      
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '搜索失败: $e',
      );
      
      print('[MusicSearch] 搜索异常: $e');
    }
  }
  
  int? _parseDuration(dynamic duration) {
    if (duration == null) return null;
    if (duration is int) return duration;
    if (duration is String) {
      return int.tryParse(duration);
    }
    return null;
  }
}
```

---

## 在设置页面添加脚本管理

### 添加脚本加载按钮

在 `lib/presentation/pages/settings/source_settings_page.dart` 中：

```dart
Widget _buildJsScriptCard(
  BuildContext context,
  List<JsScript> scripts,
  JsScript? selectedScript,
  JsScriptManager scriptManager,
) {
  final jsState = ref.watch(unifiedJsProvider);
  
  return Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'JS脚本',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 显示JS状态
              const JsStatusBadge(),
            ],
          ),
          const SizedBox(height: 16),
          
          // 脚本列表
          if (scripts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '暂无脚本，请导入JS脚本',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ...scripts.map((script) {
              final isSelected = script.id == selectedScript?.id;
              final isLoaded = jsState.loadedScript?.id == script.id;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Radio<String>(
                    value: script.id,
                    groupValue: selectedScript?.id,
                    onChanged: (value) async {
                      if (value != null) {
                        await _handleScriptChange(script);
                      }
                    },
                  ),
                  title: Row(
                    children: [
                      Text(script.name),
                      if (isLoaded) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green, width: 1),
                          ),
                          child: const Text(
                            '已加载',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    script.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      switch (value) {
                        case 'reload':
                          await _reloadScript(script);
                          break;
                        case 'delete':
                          await _deleteScript(script);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'reload',
                        child: Row(
                          children: [
                            Icon(Icons.refresh),
                            SizedBox(width: 8),
                            Text('重新加载'),
                          ],
                        ),
                      ),
                      if (!script.isBuiltIn)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('删除', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          
          const SizedBox(height: 16),
          
          // 导入按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _importScriptFromFile(),
                  icon: const Icon(Icons.file_upload),
                  label: const Text('从文件导入'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _importScriptFromUrl(),
                  icon: const Icon(Icons.link),
                  label: const Text('从URL导入'),
                ),
              ),
            ],
          ),
          
          // 缓存管理
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _clearCache(),
            icon: const Icon(Icons.clear_all),
            label: const Text('清除JS缓存'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    ),
  );
}

// 处理脚本切换
Future<void> _handleScriptChange(JsScript newScript) async {
  setState(() => _isChangingScript = true);
  
  try {
    // 1. 更新选择
    await ref.read(jsScriptManagerProvider.notifier).selectScript(newScript.id);
    
    // 2. 加载新脚本
    final success = await ref.read(unifiedJsProvider.notifier).loadScript(newScript);
    
    if (success && mounted) {
      AppSnackbar.success(context, '脚本切换成功: ${newScript.name}');
    } else if (mounted) {
      AppSnackbar.error(context, '脚本加载失败，请检查脚本内容');
    }
  } catch (e) {
    if (mounted) {
      AppSnackbar.error(context, '切换失败: $e');
    }
  } finally {
    if (mounted) {
      setState(() => _isChangingScript = false);
    }
  }
}

// 重新加载脚本
Future<void> _reloadScript(JsScript script) async {
  try {
    AppSnackbar.info(context, '正在重新加载脚本...');
    
    final success = await ref.read(unifiedJsProvider.notifier).reloadScript(script);
    
    if (success && mounted) {
      AppSnackbar.success(context, '脚本重新加载成功');
    } else if (mounted) {
      AppSnackbar.error(context, '脚本重新加载失败');
    }
  } catch (e) {
    if (mounted) {
      AppSnackbar.error(context, '重新加载失败: $e');
    }
  }
}

// 清除缓存
Future<void> _clearCache() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清除缓存'),
      content: const Text(
        '这将清除所有已缓存的JS脚本，下次加载时需要重新下载。\n\n确定继续吗？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  
  if (confirmed == true) {
    try {
      await ref.read(unifiedJsProvider.notifier).clearAllCache();
      
      if (mounted) {
        AppSnackbar.success(context, '缓存已清除');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, '清除缓存失败: $e');
      }
    }
  }
}
```

---

## 调试和日志

### 启用详细日志

所有JS操作都会打印详细日志，查找以下前缀：

```dart
// 在main.dart中
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 启用详细日志
  debugPrint('[App] 启动应用');
  
  // ... 其他代码
}
```

### 查看日志示例

```
[Main] ✅ JS运行时预初始化完成
[AuthWrapper] 🔑 检测到登录成功，准备预加载JS
[AuthWrapper] 🚀 开始后台预加载JS脚本: 小球音源
[UnifiedJS] ✅ 运行时已初始化，跳过
[UnifiedJS] 💾 使用HTTP缓存 (15分钟前)
[UnifiedJS] ✅ 脚本已加载，跳过: 小球音源
[AuthWrapper] ✅ JS脚本预加载完成
[MusicSearch] 搜索完成，找到 20 个结果
```

---

## 性能监控

添加性能监控代码：

```dart
// 在搜索开始时
final searchStartTime = DateTime.now();

// 搜索完成后
final searchDuration = DateTime.now().difference(searchStartTime);
print('[Performance] 搜索耗时: ${searchDuration.inMilliseconds}ms');

// 预期结果：
// 首次搜索: 100-300ms (JS已预加载)
// 后续搜索: 50-150ms (内存缓存)
```

---

生成时间: 2025-10-03