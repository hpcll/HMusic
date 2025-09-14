import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/music_library_provider.dart';
import '../providers/playlist_provider.dart';
import '../widgets/app_snackbar.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurface = colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 音源设置分组
          _buildSettingsGroup(
            context,
            title: '音源设置',
            children: [
              _buildSettingsItem(
                context: context,
                icon: Icons.audio_file_rounded,
                title: '音源设置',
                subtitle: '配置音乐源和搜索策略',
                onTap: () => context.push('/settings/source'),
                onSurface: onSurface,
              ),
              _buildSettingsItem(
                context: context,
                icon: Icons.record_voice_over_rounded,
                title: 'TTS文字转语音',
                subtitle: '配置语音合成设置',
                onTap: () => context.push('/settings/tts'),
                onSurface: onSurface,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 服务器设置分组
          _buildSettingsGroup(
            context,
            title: '服务器设置',
            children: [
              _buildSettingsItem(
                context: context,
                icon: Icons.http_rounded,
                title: '服务器账号设置',
                subtitle: '配置服务器连接信息',
                onTap: () => context.push('/settings/server'),
                onSurface: onSurface,
              ),
              _buildSettingsItem(
                context: context,
                icon: Icons.cloud_upload_rounded,
                title: 'SCP 上传设置',
                subtitle: '配置文件上传方式',
                onTap: () => context.push('/settings/ssh'),
                onSurface: onSurface,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 下载和工具分组
          _buildSettingsGroup(
            context,
            title: '下载与工具',
            children: [
              _buildSettingsItem(
                context: context,
                icon: Icons.link_rounded,
                title: '从链接下载',
                subtitle: '通过链接下载音乐',
                onTap: () => _showDownloadFromLinkDialog(context, ref),
                onSurface: onSurface,
              ),
              _buildSettingsItem(
                context: context,
                icon: Icons.download_rounded,
                title: '下载任务',
                subtitle: '查看和管理下载任务',
                onTap: () => context.push('/downloads'),
                onSurface: onSurface,
              ),
              _buildSettingsItem(
                context: context,
                icon: Icons.code_rounded,
                title: 'JS代理测试',
                subtitle: '测试JavaScript代理功能',
                onTap: () => context.push('/js-proxy-test'),
                onSurface: onSurface,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 支持分组
          _buildSettingsGroup(
            context,
            title: '支持',
            children: [
              _buildSettingsItem(
                context: context,
                icon: Icons.favorite_rounded,
                title: '赞赏支持',
                subtitle: '支持开发者继续维护',
                onTap: () => context.push('/settings/sponsor'),
                onSurface: onSurface,
                iconColor: Colors.red.withOpacity(0.8),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 账户操作
          _buildSettingsGroup(
            context,
            title: '账户',
            children: [
              _buildSettingsItem(
                context: context,
                icon: Icons.logout_rounded,
                title: '退出登录',
                subtitle: '注销当前账户',
                onTap: () => _showLogoutDialog(context, ref),
                onSurface: onSurface,
                iconColor: Colors.red.withOpacity(0.8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outline.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color onSurface,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? onSurface).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? onSurface.withOpacity(0.8),
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: onSurface.withOpacity(0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: onSurface.withOpacity(0.4),
        size: 20,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _showDownloadFromLinkDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final singleNameController = TextEditingController();
    final singleUrlController = TextEditingController();
    final listNameController = TextEditingController();
    final listUrlController = TextEditingController();

    Map<String, String>? result;

    result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title: const Text('从链接下载到服务器'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TabBar(tabs: [Tab(text: '单曲'), Tab(text: '合集')]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: TabBarView(
                      children: [
                        // 单曲
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: singleNameController,
                              decoration: const InputDecoration(
                                labelText: '歌曲名',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: singleUrlController,
                              decoration: const InputDecoration(
                                labelText: '歌曲链接 URL',
                                hintText: '例如：https://example.com/music.mp3',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                        // 合集
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: listNameController,
                              decoration: const InputDecoration(
                                labelText: '保存目录名（播放列表名）',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: listUrlController,
                              decoration: const InputDecoration(
                                labelText: '合集/歌单链接 URL',
                                hintText: '例如：https://example.com/playlist',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final controller = DefaultTabController.of(context);
                  final isPlaylist = (controller.index) == 1;
                  if (isPlaylist) {
                    final name = listNameController.text.trim();
                    final url = listUrlController.text.trim();
                    if (name.isEmpty || url.isEmpty) return;
                    Navigator.pop<Map<String, String>>(context, {
                      'type': 'playlist',
                      'name': name,
                      'url': url,
                    });
                  } else {
                    final name = singleNameController.text.trim();
                    final url = singleUrlController.text.trim();
                    if (name.isEmpty || url.isEmpty) return;
                    Navigator.pop<Map<String, String>>(context, {
                      'type': 'single',
                      'name': name,
                      'url': url,
                    });
                  }
                },
                child: const Text('下载'),
              ),
            ],
          ),
        );
      },
    );

    if (!context.mounted || result == null) return;

    try {
      if (result['type'] == 'single') {
        await ref
            .read(musicLibraryProvider.notifier)
            .downloadOneMusic(result['name']!, url: result['url']);
        if (context.mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('已提交单曲下载任务'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result['type'] == 'playlist') {
        await ref
            .read(playlistProvider.notifier)
            .downloadPlaylist(result['name']!, url: result['url']);
        if (context.mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('已提交整表下载任务'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('下载失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('退出登录'),
            content: const Text('确定要退出登录吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(authProvider.notifier).logout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('退出'),
              ),
            ],
          ),
    );
  }
}
