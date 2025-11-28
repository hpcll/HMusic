import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/direct_mode_provider.dart';

/// 播放模式选择页面
/// 让用户选择使用xiaomusic服务端模式还是直连模式
class PlaybackModeSelectionPage extends ConsumerWidget {
  const PlaybackModeSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择播放模式'),
        automaticallyImplyLeading: false, // 不显示返回按钮
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text(
              '选择您的使用场景',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // xiaomusic模式卡片
            _ModeCard(
              title: 'xiaomusic 模式',
              subtitle: '适合有NAS或服务器的用户',
              icon: Icons.dns,
              color: const Color(0xFF21B0A5),
              features: const [
                '✅ 功能完整（本地音乐库、语音控制）',
                '✅ 支持歌单管理',
                '✅ 支持音乐下载',
                '⚠️ 需要部署xiaomusic服务端',
              ],
              onTap: () {
                // 🎯 切换到xiaomusic模式
                ref
                    .read(playbackModeProvider.notifier)
                    .setMode(PlaybackMode.xiaomusic);
                // 让 AuthWrapper 自动决定跳转到登录页还是主页
                context.go('/');
              },
            ),

            const SizedBox(height: 24),

            // 直连模式卡片
            _ModeCard(
              title: '直连模式',
              subtitle: '适合普通手机用户',
              icon: Icons.phone_android,
              color: const Color(0xFF007AFF),
              features: const [
                '✅ 无需服务器，开箱即用',
                '✅ 配置简单，只需小米账号',
                '✅ 轻量级，资源占用少',
                '⚠️ 功能相对简单',
              ],
              onTap: () {
                // 🎯 切换到直连模式
                ref
                    .read(playbackModeProvider.notifier)
                    .setMode(PlaybackMode.miIoTDirect);
                // 让 AuthWrapper 自动决定跳转到登录页还是主页
                context.go('/');
              },
            ),

            const Spacer(),

            const Text(
              '提示：可在设置中随时切换模式',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> features;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              ...features.map((feature) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      feature,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
