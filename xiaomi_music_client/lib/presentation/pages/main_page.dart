import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../providers/music_search_provider.dart';
import 'control_panel_page.dart';
import 'music_search_page.dart';
import 'playlist_page.dart';
import 'music_library_page.dart';
import '../providers/auth_provider.dart';
import '../providers/music_library_provider.dart';
import '../widgets/app_snackbar.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  int _selectedIndex = 0;
  final _searchController = TextEditingController();

  List<Widget> get _pages => [
    const ControlPanelPage(
      key: ValueKey('control_panel_page'),
      showAppBar: false,
    ),
    const MusicSearchPage(key: ValueKey('music_search_page')),
    const PlaylistPage(key: ValueKey('playlist_page')),
    const MusicLibraryPage(key: ValueKey('music_library_page')),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      ref.read(musicSearchProvider.notifier).clearSearch();
    } else {
      // Debounce the search to avoid excessive API calls
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_searchController.text == query) {
          ref.read(musicSearchProvider.notifier).searchMusic(query);
        }
      });
    }
    // Rebuild to show/hide clear button
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    // 是否为亮色模式在此处不再需要单独判断

    // 背景渐变已移除，统一使用 surface 颜色，避免滚动影响顶部底色

    // 状态栏样式已在全局 theme 设置，此处不再单独指定

    return Scaffold(
      key: const ValueKey('main_scaffold'),
      // Keep bottom navigation fixed when keyboard shows
      resizeToAvoidBottomInset: false,
      // 统一背景色为 surface，移除页面级渐变，避免顶部随滚动色彩变化
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBody: false,
      extendBodyBehindAppBar: false,
      body: Stack(
        children: [
          // Content column
          SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                // Part 1: Header (Title, Refresh, User Info)
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: _buildHeader(context, authState),
                ),

                // Part 2: Device Selector or Search Bar
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: _buildSecondarySection(),
                ),

                // Part 3: Main Content (Player, Lists)
                Expanded(
                  child: IndexedStack(
                    key: const ValueKey('main_indexed_stack'),
                    index: _selectedIndex,
                    children: _pages,
                  ),
                ),
              ],
            ),
          ),

          // Floating blurred bottom navigation overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: _buildModernBottomNav()),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AuthState authState) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SizedBox(
        height: 56.0, // Standard AppBar height
        child: Row(
          children: [
            Text(
              '小爱音乐',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: onSurface,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            // Upload button - only show on music library tab (index 3)
            if (_selectedIndex == 3)
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: onSurface.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.upload_rounded,
                      color: onSurface,
                      size: 20,
                    ),
                  ),
                  onPressed: _showUploadDialog,
                  tooltip: '上传音乐文件',
                ),
              ),
            PopupMenuButton<String>(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: onSurface.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.settings_rounded, color: onSurface, size: 20),
              ),
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'download_settings':
                    context.push('/settings/download');
                    break;
                  case 'download_tasks':
                    context.push('/downloads');
                    break;
                  case 'ssh_settings':
                    context.push('/settings/ssh');
                    break;
                  case 'server_settings':
                    context.push('/settings/server');
                    break;
                  case 'logout':
                    ref.read(authProvider.notifier).logout();
                    break;
                }
              },
              itemBuilder:
                  (context) => [
                    PopupMenuItem(
                      value: 'download_tasks',
                      child: Row(
                        children: [
                          Icon(
                            Icons.download_rounded,
                            color: onSurface.withOpacity(0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '下载任务',
                            style: TextStyle(color: onSurface.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'download_settings',
                      child: Row(
                        children: [
                          Icon(
                            Icons.settings_rounded,
                            color: onSurface.withOpacity(0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '下载设置',
                            style: TextStyle(color: onSurface.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'server_settings',
                      child: Row(
                        children: [
                          Icon(
                            Icons.http_rounded,
                            color: onSurface.withOpacity(0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '服务器账号设置',
                            style: TextStyle(color: onSurface.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'ssh_settings',
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_upload_rounded,
                            color: onSurface.withOpacity(0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'SCP 上传设置',
                            style: TextStyle(color: onSurface.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            color: onSurface.withOpacity(0.8),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '退出登录',
                            style: TextStyle(color: onSurface.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                  ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondarySection() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    Widget content;

    // Only show the search bar on the search page (_selectedIndex == 1)
    // and device selection on the control page (_selectedIndex == 0)
    switch (_selectedIndex) {
      case 0:
        // Use a placeholder for device selection as it's part of ControlPanelPage
        content =
            const SizedBox.shrink(); // This will be handled inside ControlPanelPage
        break;
      case 1:
        content = TextField(
          key: const ValueKey(
            'main_search_field',
          ), // Unique key for main page search
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: TextStyle(color: onSurface),
          decoration: InputDecoration(
            hintText: '搜索歌曲、专辑或艺术家...',
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
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                    : null,
            filled: true,
            fillColor: onSurface.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: 16,
            ),
          ),
          onSubmitted: (value) {
            ref.read(musicSearchProvider.notifier).searchMusic(value);
          },
        );
        break;
      default:
        // For all other tabs, show nothing in this section.
        content = const SizedBox.shrink();
        break;
    }

    return Container(
      // 固定样式，避免动画带来的断言问题和抖动
      key: ValueKey<String>('secondary_section_$_selectedIndex'),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: content,
    );
  }

  Widget _buildModernBottomNav() {
    // 获取底部安全区域高度（包括小白条）
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final hasBottomInset = bottomPadding > 0;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: hasBottomInset ? bottomPadding + 8 : 20,
        top: 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: onSurface.withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Glass blur background
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
                ),
              ),
            ),
            SizedBox(
              height: 68,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTabItem(
                    icon: Icons.play_circle_outline_rounded,
                    activeIcon: Icons.play_circle_filled_rounded,
                    label: '控制',
                    index: 0,
                  ),
                  _buildTabItem(
                    icon: Icons.search_rounded,
                    activeIcon: Icons.search_rounded,
                    label: '搜索',
                    index: 1,
                  ),
                  _buildTabItem(
                    icon: Icons.playlist_play_outlined,
                    activeIcon: Icons.playlist_play_rounded,
                    label: '列表',
                    index: 2,
                  ),
                  _buildTabItem(
                    icon: Icons.library_music_outlined,
                    activeIcon: Icons.library_music_rounded,
                    label: '曲库',
                    index: 3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.7);

    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder:
                    (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  key: ValueKey<String>(
                    'nav_icon_${index}_$isSelected',
                  ), // Unique key for each navigation icon
                  size: 26,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUploadDialog() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
        withData: false, // We only need paths for uploads
      );

      if (result != null && result.files.isNotEmpty) {
        // Show upload confirmation dialog
        final shouldUpload = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('上传音乐文件'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('已选择 ${result.files.length} 个文件：'),
                    const SizedBox(height: 8),
                    ...result.files
                        .take(5)
                        .map(
                          (file) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• ${file.name}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                    if (result.files.length > 5)
                      Text(
                        '... 还有 ${result.files.length - 5} 个文件',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('上传'),
                  ),
                ],
              ),
        );

        if (shouldUpload == true) {
          await _uploadFiles(result.files);
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('选择文件失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadFiles(List<PlatformFile> files) async {
    try {
      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: const Text('上传中...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('正在上传 ${files.length} 个文件'),
                ],
              ),
            ),
      );

      await ref.read(musicLibraryProvider.notifier).uploadMusics(files);

      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('成功上传 ${files.length} 个文件'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        AppSnackBar.show(
          context,
          SnackBar(content: Text('上传失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
