import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playlist_provider.dart';
import '../providers/local_playlist_provider.dart'; // 🆕 本地播放列表 Provider
import '../providers/playback_provider.dart'; // 🆕 播放状态
import '../providers/direct_mode_provider.dart'; // 🆕 用于获取播放模式
import '../providers/device_provider.dart';
import 'playlist_detail_page.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../providers/auth_provider.dart';

class PlaylistPage extends ConsumerStatefulWidget {
  final bool showCreateDialog; // 🎯 新增：是否自动弹出创建对话框

  const PlaylistPage({super.key, this.showCreateDialog = false});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  @override
  void initState() {
    super.initState();
    // 🎯 根据播放模式选择初始化逻辑
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mode = ref.read(playbackModeProvider);

      if (mode == PlaybackMode.miIoTDirect) {
        // 直连模式：加载本地播放列表
        ref.read(localPlaylistProvider.notifier).refreshPlaylists();
      } else {
        // xiaomusic 模式：检查登录状态后加载服务器播放列表
        final auth = ref.read(authProvider);
        if (auth is AuthAuthenticated) {
          ref.read(playlistProvider.notifier).refreshPlaylists();
        }
      }

      // 🎯 如果需要自动弹出创建对话框
      if (widget.showCreateDialog) {
        // 延迟一点确保页面已经渲染完成
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _showCreatePlaylistDialog();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 根据播放模式选择 Provider
    final playbackMode = ref.watch(playbackModeProvider);
    final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;

    // 🎯 根据模式获取状态（分别获取以避免类型推断为 Object）
    final isLoading = isDirectMode
        ? ref.watch(localPlaylistProvider).isLoading
        : ref.watch(playlistProvider).isLoading;

    final error = isDirectMode
        ? ref.watch(localPlaylistProvider).error
        : ref.watch(playlistProvider).error;

    // 获取播放列表数组（兼容两种模型）
    final playlists = isDirectMode
        ? ref.watch(localPlaylistProvider).playlists
        : ref.watch(playlistProvider).playlists;

    return Scaffold(
      key: const ValueKey('playlist_scaffold'),
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false, // 底部由 AppLayout 处理
        child: _buildContent(
          isLoading: isLoading,
          error: error,
          playlists: playlists,
          isDirectMode: isDirectMode,
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: AppLayout.bottomOverlayHeight(context) + 8,
        ),
        child: FloatingActionButton(
          key: const ValueKey('playlist_fab'),
          onPressed: () => _showCreatePlaylistDialog(),
          tooltip: '新建歌单',
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add_rounded),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildContent({
    required bool isLoading,
    required String? error,
    required List<dynamic> playlists,
    required bool isDirectMode,
  }) {
    if (isLoading && playlists.isEmpty) {
      return _buildLoadingIndicator();
    }
    if (error != null) {
      return _buildErrorState(error, isDirectMode);
    }
    if (playlists.isEmpty) {
      return _buildInitialState(isDirectMode);
    }
    return _buildPlaylistsList(playlists, isDirectMode);
  }

  Widget _buildInitialState(bool isDirectMode) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('playlist_initial'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 80,
            color: onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Text(
            '你的歌单',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDirectMode
                ? '点击右下角 + 创建你的第一个歌单'
                : '在这里创建和管理你的音乐收藏',
            style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 16),
          // 直连模式不显示"加载歌单"按钮（本地存储无需加载）
          if (!isDirectMode)
            FilledButton.icon(
              onPressed: () {
                ref.read(playlistProvider.notifier).refreshPlaylists();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('加载歌单'),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      key: const ValueKey('playlist_loading'),
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorState(String error, bool isDirectMode) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('playlist_error'),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              '加载列表失败',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(fontSize: 15, color: onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                if (isDirectMode) {
                  ref.read(localPlaylistProvider.notifier).refreshPlaylists();
                } else {
                  ref.read(playlistProvider.notifier).refreshPlaylists();
                }
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsList(List<dynamic> playlists, bool isDirectMode) {
    // 🎯 获取可删除播放列表列表（仅 xiaomusic 模式需要）
    final deletablePlaylists = isDirectMode
        ? <String>{} // 直连模式所有播放列表都可删除
        : ref.watch(playlistProvider).deletablePlaylists;

    return RefreshIndicator(
      key: const ValueKey('playlist_refresh'),
      onRefresh: () {
        if (isDirectMode) {
          return ref.read(localPlaylistProvider.notifier).refreshPlaylists();
        } else {
          return ref.read(playlistProvider.notifier).refreshPlaylists();
        }
      },
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              AppLayout.contentBottomPadding(context),
            ),
            sliver: SliverList.builder(
              key: const ValueKey('playlist_list'),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                // 🎯 兼容两种模型访问属性
                final String playlistName =
                    isDirectMode ? playlist.name : playlist.name;
                final int playlistCount = isDirectMode
                    ? playlist.count
                    : (playlist.count ?? 0);
                final bool deletable = isDirectMode
                    ? true // 直连模式所有播放列表都可删除
                    : deletablePlaylists.contains(playlistName);

                final isLight = Theme.of(context).brightness == Brightness.light;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 3.0),
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.black.withOpacity(0.03)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isLight
                          ? Colors.black.withOpacity(0.06)
                          : Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -3,
                    ),
                    minLeadingWidth: 0,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.queue_music_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      playlistName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      '$playlistCount首歌曲',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🎯 仅 xiaomusic 模式显示播放按钮（直连模式暂不支持播放列表）
                        if (!isDirectMode)
                          IconButton(
                            icon: const Icon(Icons.play_circle_fill_rounded),
                            color: Theme.of(context).colorScheme.primary,
                            iconSize: 20,
                            tooltip: '播放歌单',
                            onPressed: () async {
                              final did =
                                  ref.read(deviceProvider).selectedDeviceId;
                              if (did == null) {
                                if (mounted) {
                                  AppSnackBar.showWarning(context, '请先在设置中配置 NAS 服务器');
                                }
                                return;
                              }
                              await ref
                                  .read(playlistProvider.notifier)
                                  .playPlaylist(
                                    deviceId: did,
                                    playlistName: playlistName,
                                  );
                            },
                          ),
                        PopupMenuButton<String>(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (value) async {
                            switch (value) {
                              case 'open':
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => PlaylistDetailPage(
                                          playlistName: playlistName,
                                        ),
                                  ),
                                );
                                break;
                              case 'delete':
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder:
                                      (ctx) => AlertDialog(
                                        title: const Text('删除歌单'),
                                        content: Text(
                                          '确定删除 "$playlistName" 吗？此操作不可撤销。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(ctx, false),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed:
                                                () => Navigator.pop(ctx, true),
                                            child: const Text('删除'),
                                          ),
                                        ],
                                      ),
                                );
                                if (ok == true) {
                                  try {
                                    // 🎯 根据模式调用对应的删除方法
                                    if (isDirectMode) {
                                      await ref
                                          .read(localPlaylistProvider.notifier)
                                          .deletePlaylist(playlistName);
                                    } else {
                                      await ref
                                          .read(playlistProvider.notifier)
                                          .deletePlaylist(playlistName);
                                    }
                                    if (mounted) {
                                      AppSnackBar.showSuccess(
                                        context,
                                        '已删除歌单：$playlistName',
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      AppSnackBar.showError(
                                        context,
                                        '删除失败：$e',
                                      );
                                    }
                                  }
                                }
                                break;
                            }
                          },
                          itemBuilder:
                              (context) => [
                                const PopupMenuItem(
                                  value: 'open',
                                  child: Text('打开'),
                                ),
                                if (deletable)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除歌单'),
                                  ),
                              ],
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => PlaylistDetailPage(
                                playlistName: playlistName,
                              ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    bool _requestedFocus = false;

    // 🎯 检查当前播放模式
    final playbackMode = ref.read(playbackModeProvider);
    final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        final focusNode = FocusNode();
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final canCreate = controller.text.trim().isNotEmpty;
            // 延后聚焦，避免与底部面板动画同时触发造成卡顿
            if (!_requestedFocus) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await Future.delayed(const Duration(milliseconds: 180));
                if (focusNode.canRequestFocus) {
                  FocusScope.of(context).requestFocus(focusNode);
                }
              });
              _requestedFocus = true;
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '新建歌单',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: false,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        labelText: '歌单名称',
                        hintText: '例如：我的最爱',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: onSurface.withOpacity(0.1),
                          ),
                        ),
                        filled: true,
                        fillColor: onSurface.withOpacity(0.04),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                !canCreate
                                    ? null
                                    : () async {
                                      final name = controller.text.trim();
                                      try {
                                        // 🎯 根据模式调用对应的创建方法
                                        if (isDirectMode) {
                                          await ref
                                              .read(localPlaylistProvider.notifier)
                                              .createPlaylist(name);
                                        } else {
                                          await ref
                                              .read(playlistProvider.notifier)
                                              .createPlaylist(name);
                                        }
                                        if (mounted) Navigator.pop(context);
                                        if (mounted) {
                                          AppSnackBar.showSuccess(
                                            context,
                                            '"$name" 已创建',
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) Navigator.pop(context);
                                        if (mounted) {
                                          AppSnackBar.showError(
                                            context,
                                            '创建失败: $e',
                                          );
                                        }
                                      }
                                    },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('创建'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
