import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'control_panel_page.dart';
import 'playlist_page.dart';
import 'music_search_page.dart';
import '../providers/music_search_provider.dart';
import 'music_library_page.dart';
import '../providers/auth_provider.dart';
import '../providers/music_library_provider.dart';
import '../widgets/app_snackbar.dart';
import '../providers/ssh_settings_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/usage_stats_provider.dart';
import '../widgets/sponsor_prompt_dialog.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  late AnimationController _heartbeatController;
  late Animation<double> _heartbeatAnimation;
  bool _hasPlayedHeartbeat = false;

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
    final wasIndex = _selectedIndex;
    setState(() {
      _selectedIndex = index;
    });
    // 当切到“列表”标签（index 2）时触发一次加载
    if (index == 2 && wasIndex != 2) {
      final auth = ref.read(authProvider);
      if (auth is AuthAuthenticated) {
        ref.read(playlistProvider.notifier).refreshPlaylists();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchTextChanged);

    // 初始化心跳动画
    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartbeatAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _heartbeatController, curve: Curves.easeInOut),
    );

    // 延迟检查里程碑，避免在初始化时打扰用户
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _checkMilestones();
      }
    });

    // 延迟播放心跳动画（只播放3次）
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_hasPlayedHeartbeat) {
        _playHeartbeatAnimation();
      }
    });
  }

  /// 播放心跳动画(3次)
  void _playHeartbeatAnimation() async {
    _hasPlayedHeartbeat = true;
    for (int i = 0; i < 3; i++) {
      await _heartbeatController.forward();
      await _heartbeatController.reverse();
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// 检查并显示里程碑
  void _checkMilestones() async {
    final usageStats = ref.read(usageStatsProvider.notifier);

    // 检查使用天数里程碑
    if (usageStats.checkDaysMilestone()) {
      final result = await SponsorPromptDialog.showDaysMilestone(context);
      if (result == true || result == 'never') {
        await usageStats.markDaysMilestoneShown();
        await usageStats.updateLastPromptDate();
        if (result == 'never') {
          await usageStats.setNeverShowPrompt(true);
        }
      }
      return; // 一次只显示一个提示
    }

    // 检查播放里程碑
    if (usageStats.checkPlaysMilestone()) {
      final result = await SponsorPromptDialog.showPlaysMilestone(context);
      if (result == true) {
        await usageStats.markPlaysMilestoneShown();
        await usageStats.updateLastPromptDate();
      }
      return;
    }

    // 检查歌词里程碑
    if (usageStats.checkLyricsMilestone()) {
      final result = await SponsorPromptDialog.showLyricsMilestone(context);
      if (result == true) {
        await usageStats.markLyricsMilestoneShown();
        await usageStats.updateLastPromptDate();
      }
      return;
    }

    // 检查30天间隔提示
    final stats = ref.read(usageStatsProvider);
    if (stats.shouldShowIntervalPrompt) {
      final result = await SponsorPromptDialog.showIntervalPrompt(context);
      if (result == true || result == 'never') {
        await usageStats.updateLastPromptDate();
        if (result == 'never') {
          await usageStats.setNeverShowPrompt(true);
        }
      }
    }
  }

  void _handleSearchTextChanged() {
    // Keep UI (clear button visibility) in sync
    if (mounted) setState(() {});

    // Ignore input while IME is composing (e.g., Pinyin on macOS)
    if (_searchController.value.composing.isValid) {
      return;
    }

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_searchController.value.composing.isValid) return;
      final text = _searchController.text;
      ref.read(musicSearchProvider.notifier).searchOnline(text);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_handleSearchTextChanged);
    _searchController.dispose();
    _heartbeatController.dispose();
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
            Transform.translate(
              offset: const Offset(-8, 8),
              child: SvgPicture.asset(
                'assets/hmusic-logo.svg',
                width: 180,
                fit: BoxFit.fitWidth,
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
            // Sponsor button
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: ScaleTransition(
                scale: _heartbeatAnimation,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: onSurface.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      color: Colors.pink.shade400,
                      size: 20,
                    ),
                  ),
                  onPressed: () => context.push('/settings/sponsor'),
                  tooltip: '赞赏支持',
                ),
              ),
            ),
            IconButton(
              onPressed: () => context.push('/settings'),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: onSurface.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.settings_rounded, color: onSurface, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondarySection() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    if (_selectedIndex != 1) {
      return Container(
        key: ValueKey<String>('secondary_section_$_selectedIndex'),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        child: const SizedBox.shrink(),
      );
    }
    return Container(
      key: ValueKey<String>('secondary_section_$_selectedIndex'),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: TextField(
        key: const ValueKey('online_search_field'),
        controller: _searchController,
        style: TextStyle(color: onSurface),
        decoration: InputDecoration(
          hintText: '在线搜索歌曲...',
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
                      ref.read(musicSearchProvider.notifier).clearSearch();
                      setState(() {});
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
            vertical: 8,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildModernBottomNav() {
    // 获取底部安全区域高度（包括小白条）
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final gestureInset = MediaQuery.of(context).systemGestureInsets.bottom;
    final hasGesture = gestureInset > 0 || bottomPadding > 0;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: hasGesture ? ((bottomPadding + 8 - 15).clamp(0, double.infinity)) : 20,
        top: 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 1), // 更淡的边框
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), // 更淡的阴影
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), // 增强模糊
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20), // 更透明
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTabItem(
                  icon: Icons.play_circle_outline_rounded,
                  activeIcon: Icons.play_circle_filled_rounded,
                  label: '播放',
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
    ).colorScheme.onSurface.withValues(alpha: 0.7);

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
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: index == 0
                    ? _buildPlayTabIcon(isSelected, activeColor, inactiveColor)
                    : Icon(
                        isSelected ? activeIcon : icon,
                        key: ValueKey<String>('nav_icon_${index}_$isSelected'),
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

  Widget _buildPlayTabIcon(bool isSelected, Color activeColor, Color inactiveColor) {
    final playback = ref.watch(playbackProvider);
    final cover = playback.albumCoverUrl;
    final isPlaying = playback.currentMusic?.isPlaying ?? false;
    final borderColor = (isSelected ? activeColor : inactiveColor).withValues(alpha: 0.6);

    // 计算播放进度 (0.0 - 1.0)
    final offset = playback.currentMusic?.offset ?? 0;
    final duration = playback.currentMusic?.duration ?? 0;
    final progress = duration > 0 ? (offset / duration).clamp(0.0, 1.0) : 0.0;

    Widget image = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: inactiveColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_circle_filled_rounded,
        size: 16,
        color: isSelected ? activeColor : inactiveColor,
      ),
    );

    if (cover != null && cover.isNotEmpty) {
      final thumb = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: cover,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          errorWidget: (_, __, ___) => Icon(
            Icons.music_note_rounded,
            size: 16,
            color: inactiveColor,
          ),
        ),
      );
      image = thumb;
    }

    return Stack(
      key: ValueKey<String>('play_tab_icon_${cover ?? 'none'}_${isPlaying}_$isSelected'),
      clipBehavior: Clip.none,
      children: [
        // 外围进度圈
        SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.0,
            backgroundColor: borderColor.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              isSelected ? activeColor : inactiveColor,
            ),
          ),
        ),
        // 封面图 (居中)
        Positioned(
          left: 2,
          top: 2,
          child: image,
        ),
        // 播放状态指示器
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded,
              size: 10,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),
        ),
      ],
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
        AppSnackBar.showError(
          context,
          '选择文件失败：$e',
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

      final ssh = ref.read(sshSettingsProvider);
      final useHttp = ssh.useHttpUpload;
      bool ok = false;
      String mode = useHttp ? 'HTTP' : 'SCP';

      if (useHttp) {
        try {
          await ref.read(musicLibraryProvider.notifier).uploadMusics(files);
          ok = true;
        } catch (e) {
          // HTTP 失败则回退到 SCP
          try {
            await ref
                .read(musicLibraryProvider.notifier)
                .uploadViaScp(
                  host: ssh.host,
                  port: ssh.port,
                  username: ssh.username,
                  password: ssh.password,
                  remoteDir: '/opt/xiaomusic/music',
                  files: files,
                  subDir: ssh.subDir,
                );
            ok = true;
            mode = 'SCP(回退)';
          } catch (_) {
            rethrow;
          }
        }
      } else {
        await ref
            .read(musicLibraryProvider.notifier)
            .uploadViaScp(
              host: ssh.host,
              port: ssh.port,
              username: ssh.username,
              password: ssh.password,
              remoteDir: '/opt/xiaomusic/music',
              files: files,
              subDir: ssh.subDir,
            );
        ok = true;
        mode = 'SCP';
      }

      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        if (ok) {
          AppSnackBar.showSuccess(
            context,
            '$mode 上传成功：${files.length} 个文件',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        AppSnackBar.showError(
          context,
          '上传失败：$e',
        );
      }
    }
  }
}
