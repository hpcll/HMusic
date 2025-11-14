import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 赞赏提示对话框
class SponsorPromptDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool showNeverAskAgain;

  const SponsorPromptDialog({
    super.key,
    required this.title,
    required this.message,
    this.showNeverAskAgain = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withOpacity(0.3),
              colorScheme.secondaryContainer.withOpacity(0.3),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_rounded,
                size: 40,
                color: Colors.pink.shade400,
              ),
            ),

            const SizedBox(height: 16),

            // 标题
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // 消息
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.8),
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // 按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 稍后按钮
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    '稍后',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // 赞赏按钮
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                    context.push('/settings/sponsor');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.favorite_rounded, size: 18),
                  label: const Text('赞赏支持'),
                ),
              ],
            ),

            // "不再提醒"选项
            if (showNeverAskAgain) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop('never'),
                child: Text(
                  '不再提醒',
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 显示播放里程碑提示
  static Future<dynamic> showPlaysMilestone(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '🎉 恭喜解锁成就！',
        message: '您已经用 HMusic 播放了 50 首歌曲！\n如果这个应用对您有帮助，\n欢迎赞赏支持开发者继续改进',
        showNeverAskAgain: false,
      ),
    );
  }

  /// 显示歌词里程碑提示
  static Future<dynamic> showLyricsMilestone(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '✨ 歌词大师！',
        message: '已为您自动获取了 20 条歌词！\n喜欢这个功能吗？\n您的支持是开发者最大的动力',
        showNeverAskAgain: false,
      ),
    );
  }

  /// 显示使用天数里程碑提示
  static Future<dynamic> showDaysMilestone(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '❤️ 感谢陪伴！',
        message: '您已经使用 HMusic 一周啦！\n感谢您的信任和支持\n如果觉得应用不错，欢迎赞赏',
        showNeverAskAgain: false,
      ),
    );
  }

  /// 显示30天间隔提示
  static Future<dynamic> showIntervalPrompt(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '💝 继续支持开发',
        message: 'HMusic 一直在为您提供更好的体验\n如果您觉得应用有帮助\n欢迎赞赏支持开发者',
        showNeverAskAgain: true,
      ),
    );
  }
}
