import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/app_snackbar.dart';
import '../providers/music_library_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
import '../providers/playlist_provider.dart';
import '../widgets/music_list_item.dart';
import '../widgets/app_layout.dart';

class MusicLibraryPage extends ConsumerStatefulWidget {
  const MusicLibraryPage({super.key});

  @override
  ConsumerState<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends ConsumerState<MusicLibraryPage>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  late AnimationController _refreshController;
  late AnimationController _listAnimationController;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _listAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // 启动列表动画
    _listAnimationController.forward();
    
    // 手动触发音乐库加载作为临时解决方案
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 检查音乐库是否为空且没有正在加载
      final libraryState = ref.read(musicLibraryProvider);
      if (libraryState.musicList.isEmpty && !libraryState.isLoading) {
        debugPrint('MusicLibraryPage: 手动触发音乐库加载');
        ref.read(musicLibraryProvider.notifier).refreshLibrary();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshController.dispose();
    _listAnimationController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(musicLibraryProvider.notifier).filterMusic(query);
    // 重建搜索按钮状态
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(musicLibraryProvider.notifier).filterMusic('');
    // 刷新音乐库，显示全部歌曲
    ref.read(musicLibraryProvider.notifier).refreshLibrary();
    setState(() {});
  }

  void _playMusic(String musicName) async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      if (mounted) {
        AppSnackBar.showText(context, '请先在设置中配置 NAS 服务器');
      }
      return;
    }

    try {
      // 🎵 获取当前的音乐列表（用于本地播放的上一曲/下一曲功能）
      final libraryState = ref.read(musicLibraryProvider);
      final playlist = libraryState.searchQuery.isEmpty
          ? libraryState.musicList
          : libraryState.filteredMusicList;

      await ref.read(playbackProvider.notifier).playMusic(
            deviceId: selectedDid,
            musicName: musicName,
            playlist: playlist, // 🎵 传递播放列表
          );

      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('正在播放: $musicName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('播放失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // NAS 播放以本地为主，设备选择逻辑移除

  void _deleteMusic(String musicName) {
    final primary = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('删除音乐', style: TextStyle(color: Colors.black87)),
        content: const Text(
          '确定要删除该音乐吗？此操作不可撤销。',
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: primary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(musicLibraryProvider.notifier).deleteMusic(musicName);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(musicLibraryProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      key: const ValueKey('music_library_scaffold'),
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton:
          libraryState.isSelectionMode &&
                  libraryState.selectedMusicNames.isNotEmpty
              ? _buildFloatingDeleteButton(libraryState)
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        key: const ValueKey('music_library_refresh'),
        onRefresh: () async {
          _refreshController.repeat();
          try {
            await ref.read(musicLibraryProvider.notifier).refreshLibrary();
          } finally {
            _refreshController.reset();
          }
        },
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Transform.translate(
                offset: const Offset(0, -4),
                child: _buildHeader(onSurface),
              ),
              const SizedBox(height: 12),
              _buildStatistics(libraryState, onSurface),
              const SizedBox(height: 8),
              Expanded(child: _buildContent(libraryState)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color onSurface) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(color: onSurface),
        decoration: InputDecoration(
          hintText: '搜索本地音乐...',
          hintStyle: TextStyle(color: onSurface.withOpacity(0.5)),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: onSurface.withOpacity(0.6),
          ),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      color: onSurface.withOpacity(0.6),
                    ),
                    onPressed: _clearSearch,
                  )
                  : null,
          filled: true,
          fillColor: onSurface.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.0),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildStatistics(MusicLibraryState libraryState, Color onSurface) {
    if (libraryState.filteredMusicList.isEmpty &&
        libraryState.searchQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    // 选择模式下显示选择状态栏
    if (libraryState.isSelectionMode) {
      return _buildSelectionBar(libraryState, onSurface);
    }

    // 普通模式下显示统计信息
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_note_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${libraryState.filteredMusicList.length} 首',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (libraryState.searchQuery.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              '从 ${libraryState.musicList.length} 首中筛选',
              style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 13),
            ),
          ],

          const Spacer(),

          // 批量选择按钮
          if (libraryState.filteredMusicList.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: onSurface.withOpacity(0.1), width: 1),
              ),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.checklist_rounded,
                  color: onSurface.withOpacity(0.7),
                  size: 18,
                ),
                onPressed: () {
                  ref.read(musicLibraryProvider.notifier).toggleSelectionMode();
                },
                tooltip: '批量选择',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(MusicLibraryState libraryState, Color onSurface) {
    final isAllSelected =
        libraryState.selectedMusicNames.length ==
            libraryState.filteredMusicList.length &&
        libraryState.filteredMusicList.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // 全选按钮
          GestureDetector(
            onTap: () {
              if (isAllSelected) {
                ref.read(musicLibraryProvider.notifier).clearSelection();
              } else {
                ref.read(musicLibraryProvider.notifier).selectAllMusic();
              }
            },
            child: Text(
              '全选',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const Spacer(),

          // 选中数量显示
          Text(
            '已选中 ${libraryState.selectedMusicNames.length} 项',
            style: TextStyle(
              color: onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          // 关闭按钮
          GestureDetector(
            onTap: () {
              ref.read(musicLibraryProvider.notifier).toggleSelectionMode();
            },
            child: Icon(
              Icons.close,
              color: onSurface.withOpacity(0.7),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingDeleteButton(MusicLibraryState libraryState) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 120, // 向上移动更多，避免遮挡最后一个选择框
        right: 56, // 调整位置使按钮中心与选择框中心对齐
      ),
      child: FloatingActionButton(
        onPressed: () => _showBatchDeleteDialog(libraryState),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 6,
        heroTag: "delete_fab",
        child: Badge(
          label: Text(
            '${libraryState.selectedMusicNames.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.red.shade800,
          child: const Icon(Icons.delete, size: 24),
        ),
      ),
    );
  }

  Widget _buildContent(MusicLibraryState libraryState) {
    if (libraryState.isLoading) {
      return _buildLoadingIndicator();
    }
    if (libraryState.error != null) {
      return _buildErrorState(libraryState.error!);
    }
    if (libraryState.musicList.isEmpty) {
      return _buildEmptyState();
    }
    if (libraryState.filteredMusicList.isEmpty &&
        libraryState.searchQuery.isNotEmpty) {
      return _buildNoResultsState();
    }
    return _buildMusicList(libraryState.filteredMusicList, libraryState);
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      key: const ValueKey('music_library_loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在加载音乐库...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('music_library_error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 80,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(musicLibraryProvider.notifier).clearError();
                ref.read(musicLibraryProvider.notifier).refreshLibrary();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('music_library_empty'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 80,
            color: onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Text(
            '音乐库为空',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尚未找到任何音乐文件\n请先添加音乐到您的设备',
            style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('music_library_no_results'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 80,
              color: onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 20),
            Text(
              '没有找到匹配的音乐',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '尝试使用其他关键词搜索',
              style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                ref.read(musicLibraryProvider.notifier).filterMusic('');
                setState(() {});
              },
              icon: const Icon(Icons.clear_all_rounded),
              label: const Text('清除搜索'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicList(
    List<dynamic> musicList,
    MusicLibraryState libraryState,
  ) {
    return FadeTransition(
      key: const ValueKey('music_library_list'),
      opacity: _listAnimationController,
      child: ListView.builder(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: AppLayout.contentBottomPadding(context),
        ),
        itemCount: musicList.length,
        itemBuilder: (context, index) {
          final music = musicList[index];
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.3, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _listAnimationController,
                curve: Interval(
                  (index / musicList.length) * 0.5,
                  ((index + 1) / musicList.length) * 0.5 + 0.5,
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0, end: 1).animate(
                CurvedAnimation(
                  parent: _listAnimationController,
                  curve: Interval(
                    (index / musicList.length) * 0.5,
                    ((index + 1) / musicList.length) * 0.5 + 0.5,
                    curve: Curves.easeOut,
                  ),
                ),
              ),
              child: MusicListItem(
                music: music,
                onTap: () {
                  if (libraryState.isSelectionMode) {
                    ref
                        .read(musicLibraryProvider.notifier)
                        .toggleMusicSelection(music.name);
                  } else {
                    _playMusic(music.name);
                  }
                },
                onPlay: () => _playMusic(music.name),
                trailing:
                    libraryState.isSelectionMode
                        ? _buildSelectionCheckbox(music, libraryState)
                        : _buildMusicItemMenu(music),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMusicItemMenu(dynamic music) {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.more_vert_rounded,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          size: 18,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'play':
            _playMusic(music.name);
            break;
          case 'add':
            _showAddToPlaylistDialog(music.name);
            break;
          case 'delete':
            _deleteMusic(music.name);
            break;
          case 'info':
            _showMusicInfo(music);
            break;
        }
      },
      itemBuilder:
          (context) => [
            PopupMenuItem(
              value: 'play',
              child: Row(
                children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  const Text('播放'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'add',
              child: Row(
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Text('添加到...'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'info',
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Text('详细信息'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Text('删除', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
    );
  }

  Widget _buildSelectionCheckbox(
    dynamic music,
    MusicLibraryState libraryState,
  ) {
    final isSelected = libraryState.selectedMusicNames.contains(music.name);
    return Container(
      padding: const EdgeInsets.all(8),
      child: Checkbox(
        value: isSelected,
        onChanged: (value) {
          ref
              .read(musicLibraryProvider.notifier)
              .toggleMusicSelection(music.name);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  void _showBatchDeleteDialog(MusicLibraryState libraryState) {
    final primary = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('批量删除音乐', style: TextStyle(color: Colors.black87)),
        content: Text(
          '确定要删除选中的 ${libraryState.selectedMusicNames.length} 首音乐吗？\n\n此操作不可撤销。',
          style: const TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: primary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(musicLibraryProvider.notifier).deleteSelectedMusic();
              if (mounted) {
                AppSnackBar.show(
                  context,
                  SnackBar(
                    content: Text('已删除 ${libraryState.selectedMusicNames.length} 首音乐'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 检查是否为虚拟播放列表
  bool _isVirtualPlaylist(String playlistName) {
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

  /// 显示添加到播放列表的对话框
  Future<void> _showAddToPlaylistDialog(String musicName) async {
    if (!mounted) return;

    final playlistState = ref.read(playlistProvider);
    final allPlaylists = playlistState.playlists;

    // 过滤掉虚拟播放列表(虚拟列表不能作为目标)
    final availablePlaylists = allPlaylists
        .where((p) => !_isVirtualPlaylist(p.name))
        .toList();

    if (availablePlaylists.isEmpty) {
      if (mounted) {
        AppSnackBar.showText(context, '没有可用的播放列表,请先创建一个播放列表');
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
                  '添加到播放列表',
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

    // 添加到播放列表
    try {
      await ref.read(playlistProvider.notifier).addMusicToPlaylist(
            musicNames: [musicName],
            playlistName: selectedPlaylist,
          );
      if (mounted) {
        AppSnackBar.showText(
          context,
          '已添加到 $selectedPlaylist',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showText(context, '添加失败: $e');
      }
    }
  }

  /// 获取包含指定歌曲的播放列表(从当前已加载的播放列表数据中查找)
  List<String> _getPlaylistsContainingMusic(String musicName, PlaylistState playlistState) {
    final containingPlaylists = <String>[];

    for (final playlist in playlistState.playlists) {
      // 跳过虚拟播放列表,不显示在结果中
      if (_isVirtualPlaylist(playlist.name)) {
        continue;
      }

      // 检查播放列表的歌曲列表中是否包含此歌曲
      if (playlist.musicList != null && playlist.musicList!.contains(musicName)) {
        containingPlaylists.add(playlist.name);
      }
    }

    return containingPlaylists;
  }

  void _showMusicInfo(music) {
    final primary = Theme.of(context).colorScheme.primary;
    final ext = music.name.contains('.') ? music.name.split('.').last : '未知';

    // 获取包含此歌曲的播放列表
    final playlistState = ref.read(playlistProvider);
    final containingPlaylists = _getPlaylistsContainingMusic(music.name, playlistState);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          music.title ?? music.name,
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (music.artist != null)
                Row(
                  children: [
                    Icon(Icons.person_rounded, color: primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        music.artist!,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              if (music.artist != null) const SizedBox(height: 8),
              if (music.album != null)
                Row(
                  children: [
                    Icon(Icons.album_rounded, color: primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        music.album!,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              if (music.album != null) const SizedBox(height: 8),
              if (music.duration != null)
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, color: primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        music.duration!,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              if (music.duration != null) const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.insert_drive_file_rounded, color: primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      music.name,
                      style: TextStyle(color: Colors.black87),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.tag_rounded, color: primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '后缀: $ext',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ],
              ),
              // 显示包含此歌曲的播放列表
              if (containingPlaylists.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.playlist_play_rounded, color: primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '所属播放列表:',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: containingPlaylists.map((playlistName) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: primary.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  playlistName,
                                  style: TextStyle(
                                    color: primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '关闭',
              style: TextStyle(color: primary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _playMusic(music.name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('播放'),
          ),
        ],
      ),
    );
  }
}
