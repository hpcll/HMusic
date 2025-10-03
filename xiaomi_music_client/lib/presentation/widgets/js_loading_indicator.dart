import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/unified_js_provider.dart';
import '../providers/source_settings_provider.dart';

/// JS加载状态指示器组件
/// 
/// 用法：
/// ```dart
/// JsLoadingIndicator(
///   child: YourContentWidget(),
///   onRetry: () => ref.read(unifiedJsProvider.notifier).reloadCurrentScript(),
/// )
/// ```
class JsLoadingIndicator extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onRetry;
  final bool showLoadingOverlay;
  
  const JsLoadingIndicator({
    super.key,
    required this.child,
    this.onRetry,
    this.showLoadingOverlay = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(sourceSettingsProvider);
    final jsState = ref.watch(unifiedJsProvider);
    
    // 如果不是JS音源，直接显示内容
    if (settings.primarySource != 'js_external') {
      return child;
    }
    
    // 显示错误状态
    if (jsState.error != null) {
      return _buildErrorView(context, ref, jsState.error!);
    }
    
    // 显示加载状态
    if (jsState.isLoading) {
      if (showLoadingOverlay) {
        return _buildLoadingOverlay(context, jsState);
      } else {
        return _buildLoadingInline(context, jsState);
      }
    }
    
    // JS未准备好但也不在加载中（可能还未开始加载）
    if (!jsState.isReady && !jsState.isLoading) {
      return _buildNotReadyView(context, ref);
    }
    
    // 正常显示内容
    return child;
  }
  
  /// 构建加载覆盖层
  Widget _buildLoadingOverlay(BuildContext context, UnifiedJsState state) {
    return Stack(
      children: [
        // 半透明背景
        Positioned.fill(
          child: Container(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
          ),
        ),
        
        // 加载指示器
        Center(
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    '正在加载JS音源脚本...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (state.loadedScript != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.loadedScript!.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  /// 构建内联加载指示器
  Widget _buildLoadingInline(BuildContext context, UnifiedJsState state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在加载JS音源脚本...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (state.loadedScript != null) ...[
            const SizedBox(height: 8),
            Text(
              state.loadedScript!.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
  
  /// 构建错误视图
  Widget _buildErrorView(BuildContext context, WidgetRef ref, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'JS脚本加载失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onRetry != null) ...[
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                  const SizedBox(width: 12),
                ],
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(unifiedJsProvider.notifier).clearError();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('忽略'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建未准备好视图
  Widget _buildNotReadyView(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'JS音源未加载',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '请在设置中选择并加载JS脚本',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/settings/source');
              },
              icon: const Icon(Icons.settings),
              label: const Text('前往设置'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 简化版：仅显示加载和错误状态的小部件
class JsStatusBadge extends ConsumerWidget {
  const JsStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(sourceSettingsProvider);
    final jsState = ref.watch(unifiedJsProvider);
    
    // 如果不是JS音源，不显示
    if (settings.primarySource != 'js_external') {
      return const SizedBox.shrink();
    }
    
    Color color;
    IconData icon;
    String tooltip;
    
    if (jsState.error != null) {
      color = Theme.of(context).colorScheme.error;
      icon = Icons.error;
      tooltip = 'JS加载失败: ${jsState.error}';
    } else if (jsState.isLoading) {
      color = Theme.of(context).colorScheme.primary;
      icon = Icons.hourglass_empty;
      tooltip = '正在加载JS脚本...';
    } else if (jsState.isReady) {
      color = Colors.green;
      icon = Icons.check_circle;
      tooltip = 'JS脚本已就绪: ${jsState.loadedScript?.name ?? "未知"}';
    } else {
      color = Theme.of(context).colorScheme.outline;
      icon = Icons.warning;
      tooltip = 'JS未加载';
    }
    
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              jsState.isLoading ? '加载中' : 
              jsState.isReady ? 'JS已就绪' :
              jsState.error != null ? 'JS错误' : 'JS未加载',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}