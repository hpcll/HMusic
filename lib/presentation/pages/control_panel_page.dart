import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/playback_provider.dart';
import '../../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import '../../data/models/device.dart';
import '../widgets/app_layout.dart';

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
            ref.read(deviceProvider.notifier).loadDevices();
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
    final deviceState = ref.watch(deviceProvider);

    // 🎨 检测封面 URL 变化并清除旧颜色 (颜色提取由 CachedNetworkImage.imageBuilder 处理)
    final coverUrl = playbackState.albumCoverUrl;
    if (coverUrl != _lastCoverUrl) {
      _lastCoverUrl = coverUrl;
      _dominantColor = null; // 清除旧颜色,等待新图片加载后提取
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
                  ),
                  const SizedBox(height: 12),
                  // 🎵 显示当前播放列表
                  if (playbackState.currentPlaylistSongs.isNotEmpty)
                    _buildCurrentPlaylist(playbackState),
                  if (playbackState.currentPlaylistSongs.isNotEmpty)
                    const SizedBox(height: 12),
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
              await ref.read(deviceProvider.notifier).loadDevices();
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
          _buildDeviceArea(deviceState),
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
  Widget _buildDeviceArea(DeviceState deviceState) {
    if (deviceState.isLoading && deviceState.devices.isEmpty) {
      // 加载中且没有设备：显示加载占位符
      return _buildDeviceLoadingPlaceholder();
    } else if (deviceState.devices.isNotEmpty) {
      // 有设备：显示设备选择器
      return _buildDeviceSelector(deviceState);
    } else {
      // 加载完成但没有设备：显示提示
      return _buildNoDeviceHint();
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

  Widget _buildDeviceSelector(DeviceState state) {
    final selectedDevice = state.devices.firstWhere(
      (d) => d.id == state.selectedDeviceId,
      orElse: () => Device(id: '', name: '选择一个设备', isOnline: false),
    );
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () => _showDeviceSelectionSheet(context, state),
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
                color:
                    (selectedDevice.isOnline ?? false)
                        ? Colors.greenAccent
                        : Colors.redAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: ((selectedDevice.isOnline ?? false)
                            ? Colors.greenAccent
                            : Colors.redAccent)
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
  Widget _buildNoDeviceHint() {
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
                await ref.read(deviceProvider.notifier).loadDevices();
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

  void _showDeviceSelectionSheet(BuildContext context, DeviceState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final surfaceColor = Theme.of(context).colorScheme.surface;
        final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: onSurfaceColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '选择设备',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: onSurfaceColor,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        try {
                          await ref.read(deviceProvider.notifier).loadDevices();
                        } catch (e) {
                          // ignore
                        }
                      },
                      icon: Icon(Icons.refresh_rounded, color: onSurfaceColor),
                    ),
                  ],
                ),
              ),
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
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: state.devices.length,
                    itemBuilder: (context, index) {
                      final device = state.devices[index];
                      final isSelected = state.selectedDeviceId == device.id;
                      return ListTile(
                        leading: Icon(
                          // 🎯 根据设备类型显示不同图标
                          device.isLocalDevice
                              ? Icons
                                  .phone_android_rounded // 本机设备
                              : Icons.speaker_group_rounded, // 播放设备
                          color:
                              (device.isOnline ?? false)
                                  ? Colors.greenAccent
                                  : onSurfaceColor.withOpacity(0.4),
                        ),
                        title: Text(
                          device.name,
                          style: TextStyle(color: onSurfaceColor),
                        ),
                        trailing:
                            isSelected
                                ? Icon(
                                  Icons.check_circle_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                                : null,
                        onTap: () {
                          ref
                              .read(deviceProvider.notifier)
                              .selectDevice(device.id);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
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
                        // 延迟提取颜色,避免与首次加载冲突
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (mounted && coverUrl == playbackState.albumCoverUrl) {
                            _extractDominantColorFromProvider(imageProvider);
                          }
                        });
                        return Image(image: imageProvider, fit: BoxFit.cover);
                      },
                      placeholder: (context, url) => _buildDefaultArtwork(artworkSize, onSurface),
                      errorWidget: (context, url, error) => _buildDefaultArtwork(artworkSize, onSurface),
                    )
                    : _buildDefaultArtwork(artworkSize, onSurface),
          ),
        ),
      ),
    );
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
              child:
                  (currentMusic != null && currentMusic.curPlaylist != null)
                      ? Text(
                        currentMusic.curPlaylist,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          fontWeight: FontWeight.w500,
                          color: onSurface.withOpacity(0.7),
                          height: subtitleLineHeight,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                      : const SizedBox.shrink(),
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
    final progress =
        (totalTime > 0) ? (currentTime / totalTime).clamp(0.0, 1.0) : 0.0;

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
            onChanged: AppConstants.enableSeek ? (value) {} : null,
            onChangeEnd:
                AppConstants.enableSeek
                    ? (value) {
                      final newPos = (value * totalTime).round();
                      ref.read(playbackProvider.notifier).seekTo(newPos);
                    }
                    : null,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(currentTime),
              style: TextStyle(color: onSurface.withOpacity(0.7)),
            ),
            Text(
              _formatDuration(totalTime),
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
    final enabled =
        ref.read(deviceProvider).selectedDeviceId != null && !state.isLoading;
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
    final enabled = ref.read(deviceProvider).selectedDeviceId != null;
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
        // 定时关机按钮（长按快速取消定时）
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
                        ? () => ref.read(playbackProvider.notifier).setTimer()
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

  /// 🎵 显示当前播放列表
  Widget _buildCurrentPlaylist(PlaybackState state) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final currentSong = state.currentMusic?.curMusic ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.queue_music_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '当前播放列表',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${state.currentPlaylistSongs.length} 首',
                style: TextStyle(
                  color: onSurface.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 限制最大高度，超出可滚动
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: state.currentPlaylistSongs.length,
              itemBuilder: (context, index) {
                final song = state.currentPlaylistSongs[index];
                final isCurrentSong = song == currentSong;

                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color:
                        isCurrentSong
                            ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.1)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color:
                            isCurrentSong
                                ? Theme.of(context).colorScheme.primary
                                : onSurface.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child:
                            isCurrentSong
                                ? Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 18,
                                )
                                : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                      ),
                    ),
                    title: Text(
                      song,
                      style: TextStyle(
                        color:
                            isCurrentSong
                                ? Theme.of(context).colorScheme.primary
                                : onSurface,
                        fontSize: 14,
                        fontWeight:
                            isCurrentSong ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing:
                        isCurrentSong
                            ? Icon(
                              Icons.graphic_eq_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            )
                            : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
}
