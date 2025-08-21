import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playback_provider.dart';
import '../../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import '../../data/models/device.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../providers/dio_provider.dart'; // Added for TTS

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

    // 延迟初始化以避免阻塞UI，只在用户已登录时自动加载设备
    Future.delayed(const Duration(milliseconds: 500), () {
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
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverList.list(
                children: [
                  if (widget.showAppBar) const SizedBox(height: 0),
                  _buildIntegratedPlayerCard(
                    playbackState,
                    deviceState,
                    authState,
                  ),
                  const SizedBox(height: 12),
                  if (playbackState.error != null)
                    _buildErrorMessage(playbackState),
                ],
              ),
            ),
            // Fill remaining space so initial view does not leave a large blank
            SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox(height: AppLayout.bottomOverlayHeight(context)),
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
          _buildDeviceSelector(deviceState),
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
          const SizedBox(height: 8),
          _buildVolumeControl(playbackState),
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
                          Icons.speaker_group_rounded,
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
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                  blurRadius: 50,
                  spreadRadius: 10,
                ),
            ],
          ),
          child: ClipOval(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    onSurface.withOpacity(0.02),
                    onSurface.withOpacity(0.1),
                  ],
                ),
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: artworkSize * 0.32,
                color: onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ),
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
                currentMusic != null
                    ? currentMusic.curMusic
                    : (hasLoaded ? '暂无播放' : '加载中...'),
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
                      : (!hasLoaded)
                      ? Text(
                        '正在连接服务器...',
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
          child: Stack(
            children: [
              Slider(
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
              if (!AppConstants.enableSeek)
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        AppSnackBar.showText(context, '服务器未支持进度拖动');
                      },
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                    ),
                  ),
                ),
            ],
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
        if (!AppConstants.enableSeek) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 6),
              Text(
                '服务器未支持进度拖动',
                style: TextStyle(
                  color: onSurface.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
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
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0:00', style: TextStyle(color: onSurface.withOpacity(0.7))),
              Text('0:00', style: TextStyle(color: onSurface.withOpacity(0.7))),
            ],
          ),
        ),
        if (!AppConstants.enableSeek) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 6),
              Text(
                '服务器未支持进度拖动',
                style: TextStyle(
                  color: onSurface.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
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
              // 先本地更新，避免频繁打到后端引起音箱多次响
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
}
