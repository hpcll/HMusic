import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playlist_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../../data/models/music.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final String playlistName;
  const PlaylistDetailPage({super.key, required this.playlistName});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(playlistProvider.notifier)
          .loadPlaylistMusics(widget.playlistName);
    });
  }

  Future<void> _playWholePlaylist() async {
    final did = ref.read(deviceProvider).selectedDeviceId;
    if (did == null) {
      if (mounted) {
        AppSnackBar.showText(context, '请先在设置中配置 NAS 服务器');
      }
      return;
    }
    await ref
        .read(playlistProvider.notifier)
        .playPlaylist(deviceId: did, playlistName: widget.playlistName);
  }

  Future<void> _playSingle(String musicName) async {
    final did = ref.read(deviceProvider).selectedDeviceId;
    if (did == null) {
      if (mounted) {
        AppSnackBar.showText(context, '请先在控制页选择播放设备');
      }
      return;
    }

    // 🎵 获取当前播放列表的歌曲，并转换为 Music 对象列表
    final state = ref.read(playlistProvider);
    final musicNames = state.currentPlaylist == widget.playlistName
        ? state.currentPlaylistMusics
        : <String>[];

    final playlist = musicNames.map((name) => Music(name: name)).toList();

    await ref.read(playbackProvider.notifier).playMusic(
          deviceId: did,
          musicName: musicName,
          playlist: playlist, // 🎵 传递播放列表
        );
  }

  /// 显示歌曲操作菜单
  Future<void> _showMusicOptionsMenu(String musicName) async {
    if (!mounted) return;

    // 检查是否为虚拟播放列表(无法从中移除歌曲引用)
    final isVirtualPlaylist = _isVirtualPlaylist(widget.playlistName);

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  musicName,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const Divider(height: 1),
              // 对于虚拟播放列表,显示"添加到...";对于普通列表,显示"移动到..."和"复制到..."
              if (isVirtualPlaylist)
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('添加到...'),
                  onTap: () => Navigator.pop(context, 'add'),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.drive_file_move_rounded),
                  title: const Text('移动到...'),
                  onTap: () => Navigator.pop(context, 'move'),
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded),
                  title: const Text('复制到...'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
              ],
              // 从播放列表删除
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('从播放列表删除'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    // 处理用户选择
    switch (result) {
      case 'add':
        // 虚拟播放列表的"添加到..."操作,等同于"复制到..."
        await _showPlaylistSelector(musicName, isMove: false);
        break;
      case 'move':
        await _showPlaylistSelector(musicName, isMove: true);
        break;
      case 'copy':
        await _showPlaylistSelector(musicName, isMove: false);
        break;
      case 'delete':
        await _deleteMusicFromPlaylist(musicName);
        break;
    }
  }

  /// 检查是否为虚拟播放列表
  /// 虚拟播放列表无法通过 playlistdelmusic 接口删除歌曲
  bool _isVirtualPlaylist(String playlistName) {
    // 常见的虚拟播放列表名称
    const virtualPlaylists = [
      '下载',
      '所有歌曲',
      '全部',
      '临时搜索列表',
      '在线播放',
      '最近新增',
    ];
    return virtualPlaylists.contains(playlistName);
  }

  /// 显示播放列表选择器
  Future<void> _showPlaylistSelector(String musicName, {required bool isMove}) async {
    if (!mounted) return;

    final state = ref.read(playlistProvider);
    final allPlaylists = state.playlists;

    // 过滤掉当前播放列表和虚拟播放列表(虚拟列表不能作为目标)
    final availablePlaylists = allPlaylists
        .where((p) => p.name != widget.playlistName && !_isVirtualPlaylist(p.name))
        .toList();

    if (availablePlaylists.isEmpty) {
      if (mounted) {
        AppSnackBar.showText(context, '没有可用的播放列表');
      }
      return;
    }

    final selectedPlaylist = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  isMove ? '移动到播放列表' : '添加到播放列表',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availablePlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = availablePlaylists[index];
                    return ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: Text(playlist.name),
                      subtitle: playlist.count != null
                          ? Text('${playlist.count} 首歌曲')
                          : null,
                      onTap: () => Navigator.pop(context, playlist.name),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selectedPlaylist == null || !mounted) return;

    // 执行移动或复制操作
    try {
      if (isMove) {
        await ref.read(playlistProvider.notifier).moveMusicToPlaylist(
              musicNames: [musicName],
              sourcePlaylistName: widget.playlistName,
              targetPlaylistName: selectedPlaylist,
            );
        if (mounted) {
          AppSnackBar.showText(
            context,
            '已移动到 $selectedPlaylist',
            backgroundColor: Colors.green,
          );
        }
      } else {
        await ref.read(playlistProvider.notifier).addMusicToPlaylist(
              musicNames: [musicName],
              playlistName: selectedPlaylist,
            );
        if (mounted) {
          AppSnackBar.showText(
            context,
            '已复制到 $selectedPlaylist',
            backgroundColor: Colors.green,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showText(context, '操作失败: $e');
      }
    }
  }

  /// 从播放列表删除歌曲
  Future<void> _deleteMusicFromPlaylist(String musicName) async {
    if (!mounted) return;

    // 确认删除
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要从播放列表"${widget.playlistName}"中删除"$musicName"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await ref.read(playlistProvider.notifier).removeMusicFromPlaylist(
            musicNames: [musicName],
            playlistName: widget.playlistName,
          );
      if (mounted) {
        AppSnackBar.showText(context, '已删除');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showText(context, '删除失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final musics =
        state.currentPlaylist == widget.playlistName
            ? state.currentPlaylistMusics
            : <String>[];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.playlistName),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded),
            onPressed: _playWholePlaylist,
          ),
        ],
      ),
      body:
          state.isLoading && musics.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : musics.isEmpty
              ? Center(
                child: Text(
                  '此列表暂无歌曲',
                  style: TextStyle(color: onSurface.withOpacity(0.6)),
                ),
              )
              : ListView.builder(
                padding: EdgeInsets.only(
                  bottom: AppLayout.contentBottomPadding(context),
                  top: 6,
                ),
                itemCount: musics.length,
                itemBuilder: (context, index) {
                  final musicName = musics[index];
                  final isLight = Theme.of(context).brightness == Brightness.light;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 0),
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      dense: true,
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                      minLeadingWidth: 0,
                      leading: Icon(
                        Icons.music_note_rounded,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      title: Text(
                        musicName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow_rounded),
                        iconSize: 22,
                        color: Theme.of(context).colorScheme.primary,
                        onPressed: () => _playSingle(musicName),
                      ),
                      onTap: () => _playSingle(musicName),
                      onLongPress: () => _showMusicOptionsMenu(musicName),
                    ),
                  );
                },
              ),
    );
  }
}
