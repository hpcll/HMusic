# 迁移指南：使用新的统一JS运行时服务

## 概述

本指南帮助你将现有代码迁移到新的 `UnifiedJsRuntimeService` 和 `unifiedJsProvider`。

---

## ✅ 已完成的优化

### 1. 创建了统一的JS运行时服务
- **文件**: `lib/data/services/unified_js_runtime_service.dart`
- **特性**: 单例模式、多级缓存、幂等加载

### 2. 创建了统一的状态管理
- **文件**: `lib/presentation/providers/unified_js_provider.dart`
- **Provider**: `unifiedJsProvider`

### 3. 添加了预初始化
- **位置**: `lib/main.dart`
- **效果**: APP启动时就开始初始化JS环境

### 4. 添加了后台预加载
- **位置**: `lib/presentation/widgets/auth_wrapper.dart`
- **效果**: 登录后自动在后台加载JS脚本

### 5. 创建了UI组件
- **文件**: `lib/presentation/widgets/js_loading_indicator.dart`
- **组件**: `JsLoadingIndicator`, `JsStatusBadge`

---

## 🔄 迁移步骤

### 步骤1: 更新音源设置页面

在 `lib/presentation/pages/settings/source_settings_page.dart` 中：

**原代码：**
```dart
// 保存时不做任何操作
await ref.read(sourceSettingsProvider.notifier).updateSettings(...);
```

**新代码：**
```dart
// 保存时同时加载脚本
final settings = await ref.read(sourceSettingsProvider.notifier).updateSettings(...);

if (settings.primarySource == 'js_external') {
  final scriptManager = ref.read(jsScriptManagerProvider.notifier);
  final selectedScript = scriptManager.selectedScript;
  
  if (selectedScript != null) {
    // 使用新的统一服务加载脚本
    final success = await ref.read(unifiedJsProvider.notifier).loadScript(selectedScript);
    
    if (success) {
      if (mounted) {
        AppSnackbar.success(context, '脚本加载成功');
      }
    } else {
      if (mounted) {
        AppSnackbar.error(context, '脚本加载失败');
      }
    }
  }
}
```

### 步骤2: 更新音乐搜索页面

在 `lib/presentation/pages/music_search_page.dart` 中添加加载状态：

**添加导入：**
```dart
import '../widgets/js_loading_indicator.dart';
import '../providers/unified_js_provider.dart';
```

**包装内容：**
```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  return Scaffold(
    appBar: AppBar(title: const Text('音乐搜索')),
    body: JsLoadingIndicator(
      onRetry: () async {
        final script = ref.read(jsScriptManagerProvider.notifier).selectedScript;
        if (script != null) {
          await ref.read(unifiedJsProvider.notifier).reloadScript(script);
        }
      },
      child: _buildSearchContent(context, ref),
    ),
  );
}
```

### 步骤3: 更新音乐搜索Provider

在 `lib/presentation/providers/music_search_provider.dart` 中：

**原代码：**
```dart
final jsService = await ref.read(jsSourceServiceProvider.future);
```

**新代码：**
```dart
// 检查JS是否准备好
final jsState = ref.read(unifiedJsProvider);
if (!jsState.isReady) {
  print('[MusicSearch] JS未准备好');
  return [];
}

// 直接使用统一服务
final service = UnifiedJsRuntimeService();
```

### 步骤4: 在主页添加状态指示

在 `lib/presentation/pages/main_page.dart` 的AppBar中：

```dart
AppBar(
  title: const Text('小爱音乐盒'),
  actions: [
    const JsStatusBadge(), // 添加JS状态指示
    const SizedBox(width: 8),
    // ... 其他按钮
  ],
)
```

---

## 📝 代码示例

### 示例1: 在设置页面切换脚本

```dart
Future<void> _handleScriptChange(JsScript newScript) async {
  // 1. 更新选择
  await ref.read(jsScriptManagerProvider.notifier).selectScript(newScript.id);
  
  // 2. 加载新脚本
  setState(() => _isLoading = true);
  
  try {
    final success = await ref.read(unifiedJsProvider.notifier).loadScript(newScript);
    
    if (success && mounted) {
      AppSnackbar.success(context, '脚本切换成功: ${newScript.name}');
    } else if (mounted) {
      AppSnackbar.error(context, '脚本加载失败');
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
```

### 示例2: 使用JS执行搜索

```dart
Future<List<Map<String, dynamic>>> searchMusic(String keyword) async {
  final jsState = ref.read(unifiedJsProvider);
  
  // 检查状态
  if (!jsState.isReady) {
    print('[Search] JS未准备好');
    return [];
  }
  
  // 构建搜索JS代码
  final searchJs = '''
    (function() {
      try {
        var result = search('qq', '$keyword', 1);
        return JSON.stringify(result);
      } catch(e) {
        console.error('搜索失败:', e);
        return '[]';
      }
    })()
  ''';
  
  // 执行JS
  final jsNotifier = ref.read(unifiedJsProvider.notifier);
  final resultStr = jsNotifier.evaluate(searchJs);
  
  if (resultStr == null) {
    return [];
  }
  
  // 解析结果
  try {
    final List<dynamic> data = jsonDecode(resultStr);
    return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
  } catch (e) {
    print('[Search] 解析结果失败: $e');
    return [];
  }
}
```

### 示例3: 清除缓存

```dart
// 在设置页面添加清除缓存按钮
ElevatedButton(
  onPressed: () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('这将清除所有已缓存的JS脚本，需要重新下载。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await ref.read(unifiedJsProvider.notifier).clearAllCache();
      
      if (mounted) {
        AppSnackbar.success(context, '缓存已清除');
      }
    }
  },
  child: const Text('清除JS缓存'),
)
```

---

## ⚠️ 注意事项

### 1. 不要同时使用旧的Provider
- ❌ `jsSourceServiceProvider` (FutureProvider - 将被废弃)
- ✅ `unifiedJsProvider` (新的统一Provider)

### 2. 检查JS状态后再执行
```dart
// ✅ 正确
final jsState = ref.read(unifiedJsProvider);
if (jsState.isReady) {
  // 执行JS相关操作
}

// ❌ 错误 - 不检查状态直接使用
final result = jsNotifier.evaluate(jsCode); // 可能返回null
```

### 3. 使用幂等的加载方法
```dart
// ✅ 可以安全地多次调用，不会重复加载
await ref.read(unifiedJsProvider.notifier).loadScript(script);
await ref.read(unifiedJsProvider.notifier).loadScript(script); // 第二次直接返回成功

// 如果确实需要重新加载（清除缓存）
await ref.read(unifiedJsProvider.notifier).reloadScript(script);
```

### 4. 错误处理
```dart
final success = await ref.read(unifiedJsProvider.notifier).loadScript(script);

if (!success) {
  // 检查错误信息
  final error = ref.read(unifiedJsProvider).error;
  print('加载失败: $error');
  
  // 显示给用户
  if (mounted) {
    AppSnackbar.error(context, error ?? '未知错误');
  }
}
```

---

## 🧪 测试验证

### 1. 测试缓存机制
```dart
// 第一次加载（从网络下载）
final start1 = DateTime.now();
await ref.read(unifiedJsProvider.notifier).loadScript(script);
final duration1 = DateTime.now().difference(start1);
print('首次加载耗时: ${duration1.inMilliseconds}ms');

// 清除内存状态但保留HTTP缓存
ref.read(unifiedJsProvider.notifier).state = 
  ref.read(unifiedJsProvider).copyWith(loadedScript: null);

// 第二次加载（使用HTTP缓存）
final start2 = DateTime.now();
await ref.read(unifiedJsProvider.notifier).loadScript(script);
final duration2 = DateTime.now().difference(start2);
print('缓存加载耗时: ${duration2.inMilliseconds}ms');

// 第三次加载（幂等，直接返回）
final start3 = DateTime.now();
await ref.read(unifiedJsProvider.notifier).loadScript(script);
final duration3 = DateTime.now().difference(start3);
print('幂等加载耗时: ${duration3.inMilliseconds}ms'); // 应该接近0ms
```

### 2. 测试预加载
```dart
// 在登录页面添加日志
print('[Login] 登录前 - JS状态: ${ref.read(unifiedJsProvider)}');

await login(...);

// 等待一下让预加载完成
await Future.delayed(const Duration(seconds: 2));

print('[Login] 登录后 - JS状态: ${ref.read(unifiedJsProvider)}');
// 应该看到 isReady: true
```

### 3. 性能对比
记录优化前后的启动时间：

**优化前：**
- 登录 → 进入主页 → 可以搜索音乐：~5秒

**优化后：**
- 登录 → 进入主页 → 可以搜索音乐：~0.5秒（JS已预加载）

---

## 🔧 调试技巧

### 查看缓存状态
```dart
// 在设置页面添加调试信息
Text('JS状态: ${ref.watch(unifiedJsProvider)}'),
Text('已加载脚本: ${ref.watch(currentLoadedScriptProvider)?.name ?? "无"}'),
Text('是否就绪: ${ref.watch(jsReadyProvider)}'),
```

### 查看日志
所有JS相关操作都有详细日志，搜索以下前缀：
- `[UnifiedJS]` - 运行时服务日志
- `[UnifiedJsProvider]` - Provider状态变化
- `[AuthWrapper]` - 预加载日志
- `[Main]` - 启动初始化日志

---

## 📞 遇到问题？

如果迁移过程中遇到问题：

1. **检查导入**: 确保导入了新的Provider
2. **查看日志**: 运行时会打印详细的调试信息
3. **清除缓存**: 尝试清除所有缓存重新加载
4. **重置服务**: 完全重置JS服务

```dart
// 紧急重置（开发调试用）
await UnifiedJsRuntimeService().reset();
```

---

生成时间: 2025-10-03