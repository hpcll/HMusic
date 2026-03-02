import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/playback_provider.dart';
import '../../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import '../providers/lyric_provider.dart';
import '../../data/models/device.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_bottom_sheet.dart';
import 'lyrics_page.dart';
import '../providers/direct_mode_provider.dart';

class ControlPanelPage extends ConsumerStatefulWidget {
  final bool showAppBar;

  const ControlPanelPage({super.key, this.showAppBar = true});

  @override
  ConsumerState<ControlPanelPage> createState() => _ControlPanelPageState();
}

class _ControlPanelPageState extends ConsumerState<ControlPanelPage>
    with TickerProviderStateMixin {
  AnimationController? _albumAnimationController;
  AnimationController? _buttonAnimationController;
  Color? _dominantColor; // 封面主色调
  String? _lastCoverUrl; // 上一次的封面 URL
  String? _colorExtractedUrl; // 🔧 已提取颜色的封面 URL（防止重复提取）
  double? _draggingValue; // 🔧 拖动进度条时的临时值

  @override
  void initState() {
    super.initState();

    _albumAnimationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );

    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // 🎯 优化：立即开始加载，避免延迟造成的割裂感
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final authState = ref.read(authProvider);

          if (authState is AuthAuthenticated) {
            // 🔧 优化：移除重复的 loadDevices 调用，ensureInitialized 内部会自动调用
            // 直连模式的设备由 DirectModeProvider 自动加载
            ref.read(playbackProvider.notifier).ensureInitialized();
          } else {
            debugPrint('ControlPanel: 用户未登录，跳过自动加载设备');
          }
        } catch (e) {
          debugPrint('初始化错误: $e');
        }
      }
    });
  }

  /// 根据当前播放模式获取设备列表状态
  DeviceState _getDeviceStateByMode(
    PlaybackMode mode,
    DeviceState xiaoMusicState,
    DirectModeState directState,
  ) {
    if (mode == PlaybackMode.miIoTDirect) {
      // 直连模式：从 DirectModeProvider 获取设备列表
      if (directState is DirectModeAuthenticated) {
        // 将 MiDevice 转换为 Device 格式
        final miDevices = directState.devices.map((miDevice) {
          return Device(
            id: miDevice.deviceId,
            name: miDevice.name,
            isOnline: true, // 假设直连设备都是在线的
            type: miDevice.hardware, // 将 hardware 映射到 type 字段
          );
        }).toList();

        return DeviceState(
          devices: miDevices,
          selectedDeviceId: directState.playbackDeviceType, // 🔧 修复：使用 playbackDeviceType
          isLoading: false,
        );
      } else {
        // 未登录或未找到设备
        return const DeviceState(
          devices: [],
          selectedDeviceId: null,
          isLoading: false,
        );
      }
    } else {
      // xiaomusic 模式：使用原有的设备列表
      return xiaoMusicState;
    }
  }

  @override
  void dispose() {
    _albumAnimationController?.dispose();
    _buttonAnimationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackProvider);
    final authState = ref.watch(authProvider);
    final xiaoMusicDeviceState = ref.watch(deviceProvider); // xiaomusic模式的设备列表
    final directModeState = ref.watch(directModeProvider); // 直连模式的状态
    final playbackMode = ref.watch(playbackModeProvider); // 当前播放模式

    // 🎯 根据当前模式选择正确的设备列表
    final deviceState = _getDeviceStateByMode(
      playbackMode,
      xiaoMusicDeviceState,
      directModeState,
    );

    // 🎨 检测封面 URL 变化并清除旧颜色 (颜色提取由 CachedNetworkImage.imageBuilder 处理)
    final coverUrl = playbackState.albumCoverUrl;
    if (coverUrl != _lastCoverUrl) {
      _lastCoverUrl = coverUrl;
      _dominantColor = null; // 清除旧颜色,等待新图片加载后提取
      _colorExtractedUrl = null; // 🔧 重置提取标记，允许新封面提取颜色
    }

    // 延迟动画控制以避免在build中修改状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _albumAnimationController != null) {
        if (playbackState.currentMusic?.isPlaying ?? false) {
          if (!_albumAnimationController!.isAnimating) {
            _albumAnimationController!.repeat();
          }
        } else {
          if (_albumAnimationController!.isAnimating) {
            _albumAnimationController!.stop();
          }
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showAppBar ? _buildAppBar(context) : null,
      body: SafeArea(
        bottom: true,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              sliver: SliverList.list(
                children: [
                  if (widget.showAppBar) const SizedBox(height: 0),
                  _buildIntegratedPlayerCard(
                    playbackState,
                    deviceState,
                    authState,
                    playbackMode,
                  ),
                  if (playbackState.error != null)
                    _buildErrorMessage(playbackState),
                ],
              ),
            ),
            // Fill remaining space so initial view does not leave a large blank
            SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox(height: AppLayout.bottomOverlayHeight(context) + 8),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        '小米音乐',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface.withOpacity(0.9),
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed('/now-playing'),
          icon: Icon(
            Icons.queue_music_rounded,
            color: onSurface.withOpacity(0.8),
          ),
          tooltip: '正在播放',
        ),
        IconButton(
          onPressed: () async {
            try {
              // 🎯 根据播放模式刷新对应的设备列表
              final playbackMode = ref.read(playbackModeProvider);
              if (playbackMode == PlaybackMode.miIoTDirect) {
                await ref.read(directModeProvider.notifier).refreshDevices();
              } else {
                await ref.read(deviceProvider.notifier).loadDevices();
              }
              await ref.read(playbackProvider.notifier).refreshStatus();
            } catch (e) {
              // Ignore refresh errors
            }
          },
          icon: Icon(Icons.refresh_rounded, color: onSurface.withOpacity(0.8)),
        ),
      ],
    );
  }

  Widget _buildIntegratedPlayerCard(
    PlaybackState playbackState,
    DeviceState deviceState,
    AuthState authState,
    PlaybackMode playbackMode,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final currentMusic = playbackState.currentMusic;
    final double fixedCardHeight = _stableCardFixedHeight(context);

    return Container(
      padding: const EdgeInsets.all(12),
      constraints: BoxConstraints(minHeight: fixedCardHeight),
      decoration: BoxDecoration(
        color:
            isLight
                ? Colors.white.withOpacity(0.6)
                : Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 🎯 始终显示设备区域，避免布局跳动
          _buildDeviceArea(deviceState, playbackMode),
          const SizedBox(height: 12),
          _buildAlbumArtwork(currentMusic, currentMusic?.isPlaying ?? false),
          const SizedBox(height: 12),
          _buildSongInfo(currentMusic, playbackState.hasLoaded),
          const SizedBox(height: 8),
          if (currentMusic != null)
            _buildProgressBar(currentMusic)
          else
            _buildInitialProgressBar(),
          const SizedBox(height: 8),
          _buildPlaybackControls(playbackState),
          const SizedBox(height: 12),
          _buildQuickActions(playbackState),
          const SizedBox(height: 8),
          _buildVolumeControl(playbackState),
        ],
      ),
    );
  }

  /// 🎯 设备区域：始终显示固定高度，避免布局跳动
  Widget _buildDeviceArea(DeviceState deviceState, PlaybackMode playbackMode) {
    if (deviceState.isLoading && deviceState.devices.isEmpty) {
      // 加载中且没有设备：显示加载占位符
      return _buildDeviceLoadingPlaceholder();
    } else if (deviceState.devices.isNotEmpty) {
      // 有设备：显示设备选择器
      return _buildDeviceSelector(deviceState, playbackMode);
    } else {
      // 加载完成但没有设备：显示提示
      return _buildNoDeviceHint(playbackMode);
    }
  }

  /// 🎯 加载中的占位符（保持与设备选择器相同的高度）
  Widget _buildDeviceLoadingPlaceholder() {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(onSurface.withOpacity(0.6)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '正在加载设备...',
            style: TextStyle(
              color: onSurface.withOpacity(0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  double _stableCardFixedHeight(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final artworkSize = screenWidth * 0.46; // matches _buildAlbumArtwork

    const double deviceSelectorHeight = 36; // approx row height with padding
    const double titleFontSize = 24;
    const double titleLineHeight = 1.3;
    const int titleLines = 2;
    const double subtitleFontSize = 16;
    const double subtitleLineHeight = 1.25;
    final double titleBlock =
        titleFontSize * titleLineHeight * titleLines; // ~62
    final double subtitleBlock = subtitleFontSize * subtitleLineHeight; // ~20

    const double sliderBlock = 56; // slider + time row + paddings
    const double controlsBlock = 56; // main play button area height
    const double volumeBlock = 44; // volume row with slider thickness

    // Vertical spacings present in the card
    const double vSpace = 12 + 12 + 8 + 8 + 8; // between sections

    // Card internal padding top+bottom = 24 (see Container padding: 12 all)
    const double cardVerticalPadding = 24;
    // Additional hint line under slider (~18px)
    const double seekHintHeight = 18;

    final double base =
        deviceSelectorHeight +
        artworkSize +
        titleBlock +
        subtitleBlock +
        sliderBlock +
        seekHintHeight +
        controlsBlock +
        volumeBlock +
        vSpace +
        cardVerticalPadding;

    // Small buffer to prevent fractional rounding causing wrap
    return base + 6;
  }

  Widget _buildDeviceSelector(DeviceState state, PlaybackMode playbackMode) {
    // 🎯 根据播放模式获取选中的设备信息
    final Device selectedDevice;
    final bool isOnline;

    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 直连模式：根据 playbackDeviceType 判断
      final directState = ref.watch(directModeProvider);

      if (directState is DirectModeAuthenticated) {
        final playbackDeviceType = directState.playbackDeviceType;

        if (playbackDeviceType == 'local') {
          // 本地播放
          selectedDevice = Device(
            id: 'local',
            name: '本地播放',
            isOnline: true,
          );
          isOnline = true;
        } else {
          // 小爱音箱
          selectedDevice = state.devices.firstWhere(
            (d) => d.id == playbackDeviceType,
            orElse: () => Device(id: '', name: '选择播放设备', isOnline: false),
          );
          isOnline = selectedDevice.isOnline ?? false;
        }
      } else {
        selectedDevice = Device(id: '', name: '选择播放设备', isOnline: false);
        isOnline = false;
      }
    } else {
      // xiaomusic 模式：使用原有逻辑
      selectedDevice = state.devices.firstWhere(
        (d) => d.id == state.selectedDeviceId,
        orElse: () => Device(id: '', name: '选择一个设备', isOnline: false),
      );
      isOnline = selectedDevice.isOnline ?? false;
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () => _showDeviceSelectionSheet(context, state, playbackMode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isOnline ? Colors.greenAccent : Colors.redAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isOnline ? Colors.greenAccent : Colors.redAccent)
                        .withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedDevice.name,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: onSurface.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }

  /// 🎯 没有找到设备时的提示
  Widget _buildNoDeviceHint(PlaybackMode playbackMode) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orangeAccent.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.orangeAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未找到播放设备，请检查设置',
              style: TextStyle(
                color: onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: Colors.orangeAccent,
              size: 18,
            ),
            onPressed: () async {
              try {
                // 🎯 根据播放模式刷新对应的设备列表
                if (playbackMode == PlaybackMode.miIoTDirect) {
                  await ref.read(directModeProvider.notifier).refreshDevices();
                } else {
                  await ref.read(deviceProvider.notifier).loadDevices();
                }
              } catch (e) {
                // ignore
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _showDeviceSelectionSheet(
    BuildContext context,
    DeviceState state,
    PlaybackMode playbackMode,
  ) {
    showAppBottomSheet(
      context: context,
      builder: (context) {
        final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

        return AppBottomSheet(
          title: '选择设备',
          trailing: IconButton(
            onPressed: () async {
              try {
                // 🎯 根据播放模式刷新对应的设备列表
                if (playbackMode == PlaybackMode.miIoTDirect) {
                  await ref.read(directModeProvider.notifier).refreshDevices();
                } else {
                  await ref.read(deviceProvider.notifier).loadDevices();
                }
              } catch (e) {
                // ignore
              }
            },
            icon: Icon(Icons.refresh_rounded, color: onSurfaceColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isLoading && state.devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      '未找到设备',
                      style: TextStyle(color: onSurfaceColor.withOpacity(0.7)),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // 🎵 直连模式：在设备列表顶部添加本地播放���项
                      if (playbackMode == PlaybackMode.miIoTDirect)
                        _buildLocalPlaybackOption(context, onSurfaceColor),

                      // 🎯 设备列表
                      ...state.devices.map((device) {
                        final isSelected = playbackMode == PlaybackMode.miIoTDirect
                            ? _isDeviceSelectedInDirectMode(device.id)
                            : state.selectedDeviceId == device.id;

                        return ListTile(
                          leading: Icon(
                            // 🎯 根据设备类型显示不同图标
                            device.isLocalDevice
                                ? Icons.phone_android_rounded // 本机设备
                                : Icons.speaker_group_rounded, // 播放设备
                            color: (device.isOnline ?? false)
                                ? Colors.greenAccent
                                : onSurfaceColor.withOpacity(0.4),
                          ),
                          title: Text(
                            device.name,
                            style: TextStyle(color: onSurfaceColor),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () {
                            // 🎯 根据播放模式选择对应的Provider
                            if (playbackMode == PlaybackMode.miIoTDirect) {
                              // 直连模式：设置播放设备为小爱音箱
                              ref
                                  .read(directModeProvider.notifier)
                                  .selectPlaybackDevice(device.id);
                            } else {
                              // xiaomusic模式：使用 DeviceProvider
                              ref
                                  .read(deviceProvider.notifier)
                                  .selectDevice(device.id);
                            }
                            Navigator.pop(context);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 🎵 构建本地播放选项（仅直连模式）
  Widget _buildLocalPlaybackOption(BuildContext context, Color onSurfaceColor) {
    final directState = ref.watch(directModeProvider);

    // 检查本地播放是否被选中
    final isSelected = directState is DirectModeAuthenticated &&
                       directState.playbackDeviceType == 'local';

    return ListTile(
      leading: Icon(
        Icons.smartphone_rounded,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : onSurfaceColor.withOpacity(0.8),
      ),
      title: Text(
        '本地播放',
        style: TextStyle(
          color: onSurfaceColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '在手机上播放音乐',
        style: TextStyle(
          color: onSurfaceColor.withOpacity(0.6),
          fontSize: 12,
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: () {
        // 设置播放设备为本地播放
        ref.read(directModeProvider.notifier).selectPlaybackDevice('local');
        Navigator.pop(context);
      },
    );
  }

  /// 🎯 检查设备是否在直连模式下被选中
  bool _isDeviceSelectedInDirectMode(String deviceId) {
    final directState = ref.read(directModeProvider);

    if (directState is DirectModeAuthenticated) {
      // 播放设备类型如果等于设备ID，说明这个设备被选中
      return directState.playbackDeviceType == deviceId;
    }

    return false;
  }

  Widget _buildAlbumArtwork(dynamic currentMusic, bool isPlaying) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final screenWidth = MediaQuery.of(context).size.width;
    final artworkSize = screenWidth * 0.46;

    // ✨ 获取封面图 URL
    final playbackState = ref.watch(playbackProvider);
    final coverUrl = playbackState.albumCoverUrl;

    // 🎨 使用提取的主色调或默认主题色
    final glowColor = _dominantColor ?? Theme.of(context).colorScheme.primary;

    return Center(
      child: GestureDetector(
        onTap: () {
          debugPrint('🎤 [点击封面] 触发点击事件');
          _openLyricsPage();
        },
        behavior: HitTestBehavior.opaque, // 🔧 确保整个区域都可点击
        child: RotationTransition(
          turns: _albumAnimationController ?? kAlwaysCompleteAnimation,
          child: Container(
            width: artworkSize,
            height: artworkSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onSurface.withOpacity(0.05),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isPlaying ? 0.35 : 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
                if (isPlaying)
                  BoxShadow(
                    color: glowColor.withOpacity(0.4),
                    blurRadius: 50,
                    spreadRadius: 10,
                  ),
              ],
            ),
            child: ClipOval(
              child:
                  coverUrl != null && coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        width: artworkSize,
                        height: artworkSize,
                        // 🎨 图片加载完成后,延迟提取颜色(确保图片已缓存)
                        imageBuilder: (context, imageProvider) {
                          // 🔧 只有当这个 URL 还没有提取过颜色时，才提取
                          if (_colorExtractedUrl != coverUrl) {
                            _colorExtractedUrl = coverUrl; // 立即标记，防止重复
                            // 延迟提取颜色,避免与首次加载冲突
                            Future.delayed(const Duration(milliseconds: 300), () {
                              if (mounted && coverUrl == playbackState.albumCoverUrl) {
                                _extractDominantColorFromProvider(imageProvider);
                              }
                            });
                          }
                          return Image(image: imageProvider, fit: BoxFit.cover);
                        },
                        placeholder: (context, url) => _buildDefaultArtwork(artworkSize, onSurface),
                        errorWidget: (context, url, error) => _buildDefaultArtwork(artworkSize, onSurface),
                      )
                      : _buildDefaultArtwork(artworkSize, onSurface),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开歌词页面
  void _openLyricsPage() {
    final current = ref.read(playbackProvider).currentMusic;

    debugPrint('🎤 [打开歌词] 开始执行');
    debugPrint('🎤 [打开歌词] 当前播放状态: ${current != null}');
    debugPrint('🎤 [打开歌词] 歌曲名: ${current?.curMusic}');

    if (current == null || current.curMusic.isEmpty) {
      debugPrint('⚠️ [打开歌词] 当前没有播放歌曲,不打开歌词页面');
      // 显示提示
      AppSnackBar.showWarning(
        context,
        '当前没有播放歌曲',
      );
      return;
    }

    debugPrint('🎤 [打开歌词] 准备打开歌词页面: ${current.curMusic}');

    // 加载歌词
    ref.read(lyricProvider.notifier).loadLyrics(current.curMusic);

    // 导航到歌词页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const LyricsPage(),
      ),
    );

    debugPrint('✅ [打开歌词] 页面跳转完成');
  }

  /// 默认的专辑封面（音乐图标）
  Widget _buildDefaultArtwork(double artworkSize, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [onSurface.withOpacity(0.02), onSurface.withOpacity(0.1)],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: artworkSize * 0.32,
        color: onSurface.withOpacity(0.8),
      ),
    );
  }

  Widget _buildSongInfo(dynamic currentMusic, bool hasLoaded) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // Fix the vertical space so the card height won't change when
    // title goes from one line (加载中...) to two-line actual song name.
    const double titleFontSize = 24;
    const double titleLineHeight = 1.3;
    const int titleMaxLines = 2;
    final double fixedTitleHeight =
        titleFontSize * titleLineHeight * titleMaxLines;

    const double subtitleFontSize = 16;
    const double subtitleLineHeight = 1.25; // close to Material default
    final double fixedSubtitleHeight =
        subtitleFontSize * subtitleLineHeight; // single line
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SizedBox(
            height: fixedTitleHeight,
            child: Center(
              child: Text(
                currentMusic != null ? currentMusic.curMusic : '暂无播放',
                style: const TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  height: titleLineHeight,
                ).copyWith(color: onSurface),
                textAlign: TextAlign.center,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Subtitle: make loading text style identical to playlist subtitle,
          // so spacing/visual weight stays consistent.
          SizedBox(
            height: fixedSubtitleHeight,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentMusic != null && currentMusic.curPlaylist != null)
                    Flexible(
                      child: Text(
                        currentMusic.curPlaylist,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          fontWeight: FontWeight.w500,
                          color: onSurface.withValues(alpha: 0.7),
                          height: subtitleLineHeight,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (currentMusic != null && currentMusic.curPlaylist != null)
                    const SizedBox(width: 6),
                  const _PlaybackModeBadge(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(dynamic currentMusic) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final currentTime = currentMusic.offset ?? 0;
    final totalTime = currentMusic.duration ?? 0;

    // 🔧 使用拖动值或实际进度值
    final displayTime = _draggingValue != null
        ? (_draggingValue! * totalTime).round()
        : currentTime;

    final progress =
        (totalTime > 0) ? (displayTime / totalTime).clamp(0.0, 1.0) : 0.0;

    // 🎯 Bug3 fix: 根据设备能力决定是否允许 seek（OH2P 不支持）
    final seekEnabled = ref.watch(playbackProvider).seekEnabled;
    final canSeek = totalTime > 0 && seekEnabled;

    debugPrint('🎯 [ControlPanel-ProgressBar] canSeek=$canSeek, progress=$progress, currentTime=$currentTime, totalTime=$totalTime, dragging=${_draggingValue != null}');

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4.0,
            trackShape: const RoundedRectSliderTrackShape(),
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: onSurface.withOpacity(0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.2),
          ),
          child: Slider(
            value: progress,
            onChanged: canSeek ? (value) {
              // 🔧 拖动时更新临时值,实时显示进度
              debugPrint('🎯 [ControlPanel-ProgressBar] onChanged: $value');
              setState(() {
                _draggingValue = value;
              });
            } : null, // 🎵 远程播放模式禁用拖动
            onChangeEnd:
                canSeek
                    ? (value) {
                      // 🔧 拖动结束,清除临时值并执行 seek
                      final newPos = (value * totalTime).round();
                      debugPrint('🎯 [ControlPanel-ProgressBar] onChangeEnd: $value, seekTo: $newPos seconds');
                      setState(() {
                        _draggingValue = null;
                      });
                      ref.read(playbackProvider.notifier).seekTo(newPos);
                    }
                    : null, // 🎵 远程播放模式禁用拖动
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              totalTime > 0 ? _formatDuration(displayTime) : '--:--',
              style: TextStyle(color: onSurface.withOpacity(0.7)),
            ),
            Text(
              totalTime > 0 ? _formatDuration(totalTime) : '--:--',
              style: TextStyle(color: onSurface.withOpacity(0.7)),
            ),
          ],
        ),
      ],
    );
  }

  /// Initial progress area before first server data: fixed UI values
  /// to keep layout identical with real state.
  Widget _buildInitialProgressBar() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        // Seek bar placeholder (disabled look)
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4.0,
            inactiveTrackColor: onSurface.withOpacity(0.1),
            activeTrackColor: onSurface.withOpacity(0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            thumbColor: onSurface.withOpacity(0.3),
            overlayColor: Colors.transparent,
          ),
          child: Slider(value: 0, min: 0, max: 1, onChanged: null),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0:00', style: TextStyle(color: onSurface.withOpacity(0.7))),
            Text('0:00', style: TextStyle(color: onSurface.withOpacity(0.7))),
          ],
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildPlaybackControls(PlaybackState state) {
    // 🎯 根据播放模式检查对应的设备选择状态
    final playbackMode = ref.read(playbackModeProvider);
    final bool hasSelectedDevice;
    if (playbackMode == PlaybackMode.miIoTDirect) {
      final directState = ref.read(directModeProvider);
      hasSelectedDevice = directState is DirectModeAuthenticated &&
          directState.playbackDeviceType.isNotEmpty; // 🔧 修复：检查 playbackDeviceType
    } else {
      hasSelectedDevice = ref.read(deviceProvider).selectedDeviceId != null;
    }
    final enabled = hasSelectedDevice && !state.isLoading;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildControlButton(
          icon: Icons.skip_previous_rounded,
          size: 32,
          enabled: enabled,
          onPressed: () => ref.read(playbackProvider.notifier).previous(),
        ),
        _buildMainPlayButton(
          state,
          enabled,
          state.currentMusic?.isPlaying ?? false,
        ),
        _buildControlButton(
          icon: Icons.skip_next_rounded,
          size: 32,
          enabled: enabled,
          onPressed: () => ref.read(playbackProvider.notifier).next(),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return IconButton(
      icon: Icon(icon),
      iconSize: size,
      color: enabled ? onSurface : onSurface.withOpacity(0.4),
      onPressed: enabled ? onPressed : null,
    );
  }

  Widget _buildMainPlayButton(
    PlaybackState state,
    bool enabled,
    bool isPlaying,
  ) {
    // 延迟动画控制以避免在build中修改状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _buttonAnimationController != null) {
        if (isPlaying) {
          _buttonAnimationController!.forward();
        } else {
          _buttonAnimationController!.reverse();
        }
      }
    });

    return GestureDetector(
      onTap:
          enabled
              ? () {
                if (isPlaying) {
                  ref.read(playbackProvider.notifier).pauseMusic();
                } else {
                  ref.read(playbackProvider.notifier).resumeMusic();
                }
              }
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient:
              enabled
                  ? LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                  : null,
          color:
              !enabled
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.1)
                  : null,
          shape: BoxShape.circle,
          boxShadow:
              enabled
                  ? [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ]
                  : [],
        ),
        child: Center(
          child:
              state.isLoading
                  ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                      strokeWidth: 2.0,
                    ),
                  )
                  : AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress:
                        _buttonAnimationController ?? kAlwaysCompleteAnimation,
                    size: 28,
                    color: Colors.white,
                  ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl(PlaybackState state) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(
          Icons.volume_mute_rounded,
          color: onSurface.withOpacity(0.6),
          size: 16,
        ),
        Expanded(
          child: Slider(
            value: state.volume.toDouble(),
            min: 0,
            max: 100,
            onChanged: (value) {
              // 先本地更新，避免频繁打到后端引起设备多次响
              ref.read(playbackProvider.notifier).setVolumeLocal(value.round());
            },
            onChangeEnd: (value) {
              // 松手时再提交后端
              ref.read(playbackProvider.notifier).setVolume(value.round());
            },
          ),
        ),
        Icon(
          Icons.volume_up_rounded,
          color: onSurface.withOpacity(0.6),
          size: 16,
        ),
      ],
    );
  }

  Widget _buildErrorMessage(PlaybackState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
            onPressed: () => ref.read(playbackProvider.notifier).clearError(),
          ),
        ],
      ),
    );
  }

  /// 🎵 快捷操作按钮（播放模式切换 + 定时关机 + 加入收藏）
  Widget _buildQuickActions(PlaybackState state) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // 🎯 根据播放模式检查对应的设备选择状态
    final playbackMode = ref.read(playbackModeProvider);
    final bool hasSelectedDevice;
    if (playbackMode == PlaybackMode.miIoTDirect) {
      final directState = ref.read(directModeProvider);
      hasSelectedDevice = directState is DirectModeAuthenticated &&
          directState.playbackDeviceType.isNotEmpty; // 🔧 修复：检查 playbackDeviceType
    } else {
      hasSelectedDevice = ref.read(deviceProvider).selectedDeviceId != null;
    }
    final enabled = hasSelectedDevice;
    final favoriteEnabled = enabled && state.currentMusic != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 播放模式切换按钮
        IconButton(
          icon: Icon(state.playMode.icon),
          iconSize: 28,
          color:
              enabled
                  ? Theme.of(context).colorScheme.primary
                  : onSurface.withOpacity(0.4),
          onPressed:
              enabled
                  ? () {
                    // 循环切换到下一个播放模式
                    final currentMode = state.playMode;
                    final nextMode =
                        PlayMode.values[(currentMode.index + 1) %
                            PlayMode.values.length];
                    ref
                        .read(playbackProvider.notifier)
                        .switchPlayMode(nextMode);
                  }
                  : null,
          tooltip: state.playMode.displayName,
        ),
        const SizedBox(width: 32),
        // 定时关机按钮（点击弹出选择器，长按快速取消定时）
        GestureDetector(
          onLongPress:
              enabled && state.timerMinutes > 0
                  ? () {
                    // 长按快速关闭定时
                    ref.read(playbackProvider.notifier).cancelTimer();
                  }
                  : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.timer_outlined),
                iconSize: 28,
                color:
                    enabled
                        ? (state.timerMinutes > 0
                            ? Colors.orangeAccent
                            : onSurface)
                        : onSurface.withOpacity(0.4),
                onPressed:
                    enabled
                        ? () => _showTimerBottomSheet(context, state) // 🎯 修改：弹出选择器
                        : null,
                tooltip:
                    state.timerMinutes > 0
                        ? '${state.timerMinutes}分钟后关机\n长按取消定时'
                        : '定时关机',
              ),
              if (state.timerMinutes > 0)
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${state.timerMinutes}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        // 收藏/取消收藏按钮
        IconButton(
          icon: Icon(
            state.isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
          iconSize: 28,
          color:
              favoriteEnabled
                  ? (state.isFavorite ? Colors.redAccent : Colors.pinkAccent)
                  : onSurface.withOpacity(0.4),
          onPressed:
              favoriteEnabled
                  ? () => ref.read(playbackProvider.notifier).toggleFavorites()
                  : null,
          tooltip: state.isFavorite ? '取消收藏' : '加入收藏',
        ),
      ],
    );
  }

  /// 🎨 从封面图提取主色调 (已废弃,改用 _extractDominantColorFromProvider)
  Future<void> _extractDominantColor(String imageUrl) async {
    try {
      debugPrint('🎨 [ControlPanel] 开始提取封面主色调: $imageUrl');
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      final extractedColor = paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      debugPrint('🎨 [ControlPanel] 提取到的颜色: $extractedColor');

      if (mounted) {
        setState(() {
          _dominantColor = extractedColor;
        });
        debugPrint('🎨 [ControlPanel] 颜色已应用到 UI');
      }
    } catch (e) {
      debugPrint('❌ [ControlPanel] 提取封面主色调失败: $e');
    }
  }

  /// 🎨 从已加载的 ImageProvider 提取主色调 (避免重复加载图片)
  Future<void> _extractDominantColorFromProvider(ImageProvider imageProvider) async {
    try {
      debugPrint('🎨 [ControlPanel] 从已加载的图片提取主色调');
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      final extractedColor = paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      debugPrint('🎨 [ControlPanel] 提取到的颜色: $extractedColor');

      if (mounted) {
        setState(() {
          _dominantColor = extractedColor;
        });
        debugPrint('🎨 [ControlPanel] 颜色已应用到 UI');
      }
    } catch (e) {
      debugPrint('❌ [ControlPanel] 提取封面主色调失败: $e');
    }
  }

  /// ⏰ 显示定时器底部弹窗选择器
  void _showTimerBottomSheet(BuildContext context, PlaybackState state) {
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final primaryColor = Theme.of(context).colorScheme.primary;

    showAppBottomSheet(
      context: context,
      isScrollControlled: true, // 允许自定义高度
      builder: (context) => AppBottomSheet(
        title: '定时关机',
        trailing: state.timerMinutes > 0
            ? TextButton.icon(
                onPressed: () {
                  ref.read(playbackProvider.notifier).cancelTimer();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('取消定时'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orangeAccent,
                ),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 当前定时状态提示
            if (state.timerMinutes > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orangeAccent.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      color: Colors.orangeAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '已设置 ${state.timerMinutes} 分钟后关机',
                        style: TextStyle(
                          color: onSurfaceColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 快捷时间选项（横向滚动）
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildTimerOption(context, state, 15, '15分钟'),
                    _buildTimerOption(context, state, 30, '30分钟'),
                    _buildTimerOption(context, state, 45, '45分钟'),
                    _buildTimerOption(context, state, 60, '1小时'),
                    _buildTimerOption(context, state, 90, '1.5小时'),
                    _buildTimerOption(context, state, 120, '2小时'),
                  ],
                ),
              ),
            ),

            // 自定义输入
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: TextField(
                decoration: InputDecoration(
                  labelText: '自定义时间（分钟）',
                  labelStyle: TextStyle(color: onSurfaceColor.withOpacity(0.7)),
                  hintText: '输入1-999分钟',
                  hintStyle: TextStyle(color: onSurfaceColor.withOpacity(0.4)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                  prefixIcon: Icon(Icons.edit_rounded, color: primaryColor),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.check_circle_rounded, color: primaryColor),
                    onPressed: () {
                      // 这个按钮只是装饰，实际提交由 onSubmitted 处理
                    },
                  ),
                ),
                keyboardType: TextInputType.number,
                style: TextStyle(color: onSurfaceColor, fontSize: 16),
                onSubmitted: (value) {
                  final minutes = int.tryParse(value);
                  if (minutes != null && minutes > 0 && minutes <= 999) {
                    ref.read(playbackProvider.notifier).setTimerMinutes(minutes);
                    Navigator.pop(context);
                  } else {
                    // 显示错误提示
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('请输入有效的分钟数（1-999）'),
                        backgroundColor: Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ),

            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// ⏰ 构建单个定时器选项卡片
  Widget _buildTimerOption(
    BuildContext context,
    PlaybackState state,
    int minutes,
    String label,
  ) {
    final isSelected = state.timerMinutes == minutes;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () {
        ref.read(playbackProvider.notifier).setTimerMinutes(minutes);
        Navigator.pop(context);
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withOpacity(0.15)
              : onSurfaceColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryColor : onSurfaceColor.withOpacity(0.2),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 36,
              color: isSelected ? primaryColor : onSurfaceColor.withOpacity(0.6),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? primaryColor : onSurfaceColor.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放模式小角标 — 独立 ConsumerWidget 隔离 playbackModeProvider 的 watch 范围
class _PlaybackModeBadge extends ConsumerWidget {
  const _PlaybackModeBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playbackModeProvider);
    final isXiaomusic = mode == PlaybackMode.xiaomusic;

    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    if (isXiaomusic) {
      bgColor = Colors.blue.withValues(alpha: 0.15);
      fgColor = Colors.blue;
      icon = Icons.dns_rounded;
      label = 'xiaomusic';
    } else {
      bgColor = Colors.orange.withValues(alpha: 0.15);
      fgColor = Colors.orange;
      icon = Icons.wifi_tethering_rounded;
      label = '直连';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fgColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fgColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}