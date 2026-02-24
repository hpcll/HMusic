import 'package:flutter/material.dart';

/// 使用统一参数显示模态底部弹窗。
///
/// 所有基础参数（useSafeArea 等）由全局主题和此方法统一管理，
/// 确保应用内所有底部弹窗行为一致。
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    builder: builder,
  );
}

/// 统一的底部弹窗容器，提供可选的标题行和一致的视觉样式。
///
/// 结构：`拖拽条（全局主题） → 标题行（可选） → 内容区`
///
/// ```dart
/// showAppBottomSheet(
///   context: context,
///   builder: (_) => AppBottomSheet(
///     title: '选择设备',
///     trailing: IconButton(...),
///     child: ListView(...),
///   ),
/// );
/// ```
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    this.title,
    this.centerTitle = false,
    this.trailing,
    required this.child,
  });

  /// 顶部标题文字。传 null 则不显示标题行（如简单操作菜单）。
  final String? title;

  /// 是否居中显示标题。默认左对齐。
  final bool centerTitle;

  /// 标题行尾部控件（如刷新按钮、取消按钮等）。
  final Widget? trailing;

  /// 标题下方的主内容区域。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                trailing != null ? 8 : 20,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign:
                          centerTitle ? TextAlign.center : TextAlign.start,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Flexible(child: child),
        ],
      ),
    );
  }
}
