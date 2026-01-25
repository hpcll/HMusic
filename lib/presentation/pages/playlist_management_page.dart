import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async'; // 🔄 用于 StreamSubscription
import '../../data/services/direct_mode_playlist_service.dart';
import '../../data/models/local_playlist_model.dart';
import '../widgets/app_snackbar.dart';
import '../providers/playback_provider.dart';
import '../providers/direct_mode_provider.dart';
import '../providers/music_search_provider.dart';
import '../../core/utils/playlist_refresh_controller.dart'; // 🔄 歌单刷新控制器

/// 🎵 歌单管理页面
///
/// 用于直连模式的本地歌单管理（创建、编辑、删除歌单）
class PlaylistManagementPage extends ConsumerStatefulWidget {
  const PlaylistManagementPage({super.key});

  @override
  ConsumerState<PlaylistManagementPage> createState() =>
      _PlaylistManagementPageState();
}

class _PlaylistManagementPageState
    extends ConsumerState<PlaylistManagementPage> {
  final _playlistService = DirectModePlaylistService();
  List<LocalPlaylistModel> _playlists = [];
  bool _isLoading = true;
  StreamSubscription? _refreshSubscription; // 🔄 刷新事件订阅

  @override
  void initState() {
    super.initState();
    _loadPlaylists();

    // 🔄 监听歌单刷新事件
    _refreshSubscription = PlaylistRefreshController.stream.listen((_) {
      debugPrint('🔄 [歌单管理] 收到刷新事件，重新加载歌单列表');
      _loadPlaylists();
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel(); // 🔄 取消订阅
    super.dispose();
  }

  /// 📋 加载歌单列表
  Future<void> _loadPlaylists() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final playlists = await _playlistService.getAllPlaylists();
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [歌单管理] 加载歌单失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppSnackBar.showError(context, '加载歌单失败: $e');
      }
    }
  }

  /// ✨ 创建新歌单
  Future<void> _createPlaylist() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _CreatePlaylistDialog(),
    );

    if (result != null) {
      final name = result['name']!;
      final description = result['description'];

      final success = await _playlistService.createPlaylist(
        name: name,
        description: description,
      );

      if (mounted) {
        if (success) {
          AppSnackBar.showSuccess(context, '歌单 "$name" 创建成功');
          _loadPlaylists(); // 刷新列表
        } else {
          AppSnackBar.showError(context, '歌单名称已存在');
        }
      }
    }
  }

  /// ✏️ 编辑歌单
  Future<void> _editPlaylist(LocalPlaylistModel playlist) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _CreatePlaylistDialog(
        initialName: playlist.name,
        initialDescription: playlist.description,
        isEdit: true,
      ),
    );

    if (result != null) {
      final name = result['name']!;
      final description = result['description'];

      final updatedPlaylist = playlist.copyWith(
        name: name,
        description: description,
      );

      final success = await _playlistService.updatePlaylist(updatedPlaylist);

      if (mounted) {
        if (success) {
          AppSnackBar.showSuccess(context, '歌单已更新');
          _loadPlaylists(); // 刷新列表
        } else {
          AppSnackBar.showError(context, '更新失败');
        }
      }
    }
  }

  /// 🗑️ 删除歌单
  Future<void> _deletePlaylist(LocalPlaylistModel playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除歌单 "${playlist.name}" 吗？\n该操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _playlistService.deletePlaylist(playlist.id);

      if (mounted) {
        if (success) {
          AppSnackBar.showSuccess(context, '歌单已删除');
          _loadPlaylists(); // 刷新列表
        } else {
          AppSnackBar.showError(context, '删除失败');
        }
      }
    }
  }

  /// 📝 查看歌单详情（歌曲列表）
  void _viewPlaylistDetails(LocalPlaylistModel playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PlaylistDetailPage(playlist: playlist),
      ),
    ).then((_) => _loadPlaylists()); // 返回时刷新列表
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单管理'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.library_music_outlined,
                        size: 80,
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '还没有歌单',
                        style: TextStyle(
                          fontSize: 18,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击右下角按钮创建第一个歌单',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    return _PlaylistCard(
                      playlist: playlist,
                      onTap: () => _viewPlaylistDetails(playlist),
                      onEdit: () => _editPlaylist(playlist),
                      onDelete: () => _deletePlaylist(playlist),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPlaylist,
        icon: const Icon(Icons.add),
        label: const Text('创建歌单'),
      ),
    );
  }
}

/// 🎵 歌单卡片组件
class _PlaylistCard extends StatelessWidget {
  final LocalPlaylistModel playlist;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 📀 歌单图标
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.queue_music_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 歌单信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${playlist.songs.length} 首歌曲',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 操作按钮
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 12),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20),
                            SizedBox(width: 12),
                            Text('删除'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 歌单描述
              if (playlist.description != null &&
                  playlist.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  playlist.description!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ✨ 创建/编辑歌单对话框
class _CreatePlaylistDialog extends StatefulWidget {
  final String? initialName;
  final String? initialDescription;
  final bool isEdit;

  const _CreatePlaylistDialog({
    this.initialName,
    this.initialDescription,
    this.isEdit = false,
  });

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? '编辑歌单' : '创建歌单'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '歌单名称',
              hintText: '请输入歌单名称',
              border: OutlineInputBorder(),
            ),
            maxLength: 50,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '描述（可选）',
              hintText: '请输入歌单描述',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 200,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              return;
            }

            Navigator.pop(context, {
              'name': name,
              'description': _descriptionController.text.trim(),
            });
          },
          child: Text(widget.isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// 📝 歌单详情页面（歌曲列表）
class _PlaylistDetailPage extends ConsumerStatefulWidget {
  final LocalPlaylistModel playlist;

  const _PlaylistDetailPage({required this.playlist});

  @override
  ConsumerState<_PlaylistDetailPage> createState() =>
      _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<_PlaylistDetailPage> {
  final _playlistService = DirectModePlaylistService();
  late LocalPlaylistModel _playlist;
  bool _isPlaying = false; // 播放状态标记
  StreamSubscription? _refreshSubscription; // 🔄 刷新事件订阅

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;

    // 🔄 监听歌单刷新事件
    _refreshSubscription = PlaylistRefreshController.stream.listen((_) {
      debugPrint('🔄 [歌单详情] 收到刷新事件，重新加载歌单数据');
      _reloadPlaylist();
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel(); // 🔄 取消订阅
    super.dispose();
  }

  /// 🔄 重新加载歌单数据
  Future<void> _reloadPlaylist() async {
    try {
      final updatedPlaylist = await _playlistService.getPlaylistById(_playlist.id);
      if (updatedPlaylist != null && mounted) {
        setState(() {
          _playlist = updatedPlaylist;
        });
        debugPrint('✅ [歌单详情] 歌单数据已刷新: ${_playlist.songs.length} 首歌曲');
      }
    } catch (e) {
      debugPrint('❌ [歌单详情] 刷新歌单失败: $e');
    }
  }

  /// 🎵 播放单首歌曲
  ///
  /// 搜索歌曲并播放，这是歌单播放的核心逻辑
  Future<void> _playSong(String songName, int index) async {
    // 检查直连模式是否已登录
    final directState = ref.read(directModeProvider);
    if (directState is! DirectModeAuthenticated) {
      AppSnackBar.showError(context, '直连模式未登录，请先登录');
      return;
    }

    if (directState.devices.isEmpty) {
      AppSnackBar.showWarning(context, '没有可用的小米设备');
      return;
    }

    setState(() {
      _isPlaying = true;
    });

    try {
      debugPrint('🎵 [歌单播放] 开始搜索并播放: $songName');

      // 解析歌曲名和歌手
      String searchQuery = songName;

      // 显示搜索提示
      if (mounted) {
        AppSnackBar.showInfo(
          context,
          '🔍 正在搜索: $searchQuery',
          duration: const Duration(seconds: 1),
        );
      }

      // 使用 MusicSearchProvider 搜索歌曲
      await ref.read(musicSearchProvider.notifier).searchMusic(searchQuery);

      // 等待搜索完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 获取搜索结果
      final searchState = ref.read(musicSearchProvider);
      if (searchState.error != null) {
        throw Exception('搜索失败: ${searchState.error}');
      }

      if (searchState.onlineResults.isEmpty) {
        throw Exception('未找到匹配的歌曲');
      }

      // 获取第一个搜索结果
      final result = searchState.onlineResults.first;
      debugPrint('🎵 [歌单播放] 找到歌曲: ${result.title} - ${result.author}');

      // 获取设备
      final device = directState.devices.first;

      // 显示播放提示
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          '🎵 正在播放: ${result.title}',
          duration: const Duration(seconds: 2),
        );
      }

      // 直接跳转到搜索页面并触发播放（这样可以利用搜索页面已有的完整播放逻辑）
      // 或者，使用 PlaybackProvider 来播放
      // 由于搜索结果已经有 platform 和 songId，可以直接使用 PlaybackProvider

      // 构造播放名称
      final musicName = '${result.title} - ${result.author}';

      // 解析播放URL（使用 playMusic 方法，它会自动处理URL解析）
      await ref.read(playbackProvider.notifier).playMusic(
        deviceId: device.deviceId,
        musicName: musicName,
        url: '', // URL 为空时，playMusic 会尝试搜索解析
        albumCoverUrl: result.picture,
      );

      debugPrint('✅ [歌单播放] 播放请求已发送');
    } catch (e) {
      debugPrint('❌ [歌单播放] 播放失败: $e');
      if (mounted) {
        AppSnackBar.showError(context, '播放失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    }
  }

  /// 🎵 播放歌单中的所有歌曲（从第一首开始）
  Future<void> _playAll() async {
    if (_playlist.songs.isEmpty) {
      AppSnackBar.showWarning(context, '歌单是空的，没有歌曲可以播放');
      return;
    }

    // 播放第一首歌曲
    await _playSong(_playlist.songs.first, 0);

    // TODO: 未来可以实现播放队列功能，自动播放下一首
  }

  /// ➕ 跳转到搜索页面添加歌曲
  void _goToSearchPage() {
    // 跳转到搜索页面，用户可以在那里搜索并添加歌曲到歌单
    context.push('/search');

    // 显示提示
    AppSnackBar.showInfo(
      context,
      '在搜索页面找到歌曲后，点击菜单选择"加入歌单"即可添加到 "${_playlist.name}"',
      duration: const Duration(seconds: 4),
    );
  }

  /// 🗑️ 从歌单移除歌曲
  Future<void> _removeSong(String songName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认移除'),
        content: Text('确定要从歌单中移除 "$songName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _playlistService.removeSongFromPlaylist(
        _playlist.id,
        songName,
      );

      if (mounted) {
        if (success) {
          AppSnackBar.showSuccess(context, '已移除');
          // 刷新歌单
          final updatedPlaylist =
              await _playlistService.getPlaylistById(_playlist.id);
          if (updatedPlaylist != null && mounted) {
            setState(() {
              _playlist = updatedPlaylist;
            });
          }
        } else {
          AppSnackBar.showError(context, '移除失败');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_playlist.name),
        centerTitle: true,
        actions: [
          // ➕ 添加歌曲按钮
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加歌曲',
            onPressed: _goToSearchPage,
          ),
        ],
      ),
      body: Column(
        children: [
          // 🎵 播放控制区域
          if (_playlist.songs.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withOpacity(0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // 歌曲数量
                  Expanded(
                    child: Text(
                      '共 ${_playlist.songs.length} 首歌曲',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                  // 播放全部按钮
                  FilledButton.icon(
                    onPressed: _isPlaying ? null : () => _playAll(),
                    icon: _isPlaying
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(_isPlaying ? '加载中...' : '播放全部'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 歌曲列表
          Expanded(
            child: _playlist.songs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note_outlined,
                          size: 80,
                          color: colorScheme.onSurface.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '歌单是空的',
                          style: TextStyle(
                            fontSize: 18,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击右上角 + 按钮添加歌曲',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _goToSearchPage,
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('去搜索歌曲'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _playlist.songs.length,
                    itemBuilder: (context, index) {
                      final songName = _playlist.songs[index];
                      // 解析歌曲名和歌手
                      String title = songName;
                      String? artist;
                      if (songName.contains(' - ')) {
                        final parts = songName.split(' - ');
                        title = parts[0];
                        artist = parts.length > 1 ? parts[1] : null;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _playSong(songName, index), // 点击播放
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: artist != null
                              ? Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 播放按钮
                              IconButton(
                                icon: Icon(
                                  Icons.play_circle_outline_rounded,
                                  color: colorScheme.primary,
                                ),
                                onPressed: () => _playSong(songName, index),
                                tooltip: '播放',
                              ),
                              // 删除按钮
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => _removeSong(songName),
                                color: Colors.red.shade400,
                                tooltip: '移除',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      // 悬浮添加按钮
      floatingActionButton: _playlist.songs.isNotEmpty
          ? FloatingActionButton(
              onPressed: _goToSearchPage,
              tooltip: '添加歌曲',
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}
