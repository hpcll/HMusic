import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/app_snackbar.dart';
import '../providers/music_library_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
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
        AppSnackBar.showText(context, '请先在控制页选择播放设备');
      }
      return;
    }

    try {
      await ref
          .read(playbackProvider.notifier)
          .playMusic(deviceId: selectedDid, musicName: musicName);

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

  // 设备选择由控制面板统一处理，此处不再弹窗

  void _deleteMusic(String musicName) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('删除音乐', style: TextStyle(color: Colors.white)),
            content: Text(
              '确定要删除"$musicName"吗？此操作不可撤销。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Color(0xFF667EEA)),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  ref
                      .read(musicLibraryProvider.notifier)
                      .deleteMusic(musicName);
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
      floatingActionButton: libraryState.isSelectionMode && 
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
              const SizedBox(height: 20),
              _buildHeader(onSurface),
              const SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: onSurface.withOpacity(0.1), width: 1),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: TextStyle(
            color: onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: '搜索本地音乐...',
            hintStyle: TextStyle(
              color: onSurface.withOpacity(0.5),
              fontSize: 16,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: onSurface.withOpacity(0.6),
              size: 22,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      color: onSurface.withOpacity(0.6),
                      size: 20,
                    ),
                    onPressed: _clearSearch,
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
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
                border: Border.all(
                  color: onSurface.withOpacity(0.1), 
                  width: 1,
                ),
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
    final isAllSelected = libraryState.selectedMusicNames.length == 
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
        right: 32,   // 向左移动，与选择框中心对齐
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 100,
              color: onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              '音乐库为空',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '尚未找到任何音乐文件\n请先添加音乐到您的设备',
              style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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

  Widget _buildMusicList(List<dynamic> musicList, MusicLibraryState libraryState) {
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
                    ref.read(musicLibraryProvider.notifier).toggleMusicSelection(music.name);
                  } else {
                    _playMusic(music.name);
                  }
                },
                onPlay: () => _playMusic(music.name),
                trailing: libraryState.isSelectionMode 
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

  Widget _buildSelectionCheckbox(dynamic music, MusicLibraryState libraryState) {
    final isSelected = libraryState.selectedMusicNames.contains(music.name);
    return Container(
      padding: const EdgeInsets.all(8),
      child: Checkbox(
        value: isSelected,
        onChanged: (value) {
          ref.read(musicLibraryProvider.notifier).toggleMusicSelection(music.name);
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  void _showBatchDeleteDialog(MusicLibraryState libraryState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '批量删除音乐',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '确定要删除选中的 ${libraryState.selectedMusicNames.length} 首音乐吗？\n\n此操作不可撤销。',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '取消',
              style: TextStyle(color: Color(0xFF667EEA)),
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

  void _showMusicInfo(music) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              music.title ?? music.name,
              style: const TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (music.artist != null) ...[
                  const Text(
                    '艺术家:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    music.artist!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (music.album != null) ...[
                  const Text(
                    '专辑:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    music.album!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (music.duration != null) ...[
                  const Text(
                    '时长:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    music.duration!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  '文件名:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  music.name,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '关闭',
                  style: TextStyle(color: Color(0xFF667EEA)),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _playMusic(music.name);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  foregroundColor: Colors.white,
                ),
                child: const Text('播放'),
              ),
            ],
          ),
    );
  }
}
