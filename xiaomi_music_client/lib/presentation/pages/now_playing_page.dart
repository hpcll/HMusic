import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  Color? _dominantColor;
  String? _lastCoverUrl;

  @override
  void initState() {
    super.initState();
    // 页面初始化后立即检查并提取封面颜色
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coverUrl = ref.read(playbackProvider).albumCoverUrl;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        debugPrint('🎨 页面初始化：检测到封面 URL，开始提取颜色');
        _lastCoverUrl = coverUrl;
        _extractDominantColor(coverUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final current = playback.currentMusic;
    final coverUrl = playback.albumCoverUrl;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    debugPrint('🎨 build: coverUrl=$coverUrl, _lastCoverUrl=$_lastCoverUrl');

    // 当封面 URL 变化时，提取颜色
    if (coverUrl != _lastCoverUrl) {
      debugPrint('🎨 检测到封面 URL 变化: $_lastCoverUrl -> $coverUrl');
      _lastCoverUrl = coverUrl;
      _dominantColor = null; // 立即清除旧颜色
      if (coverUrl != null && coverUrl.isNotEmpty) {
        // 异步提取新颜色
        Future.microtask(() => _extractDominantColor(coverUrl));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('正在播放'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 12),
              _buildAlbumCover(coverUrl, onSurface),
              const SizedBox(height: 20),
              Text(
                current?.curMusic ?? '暂无播放',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                current?.curPlaylist ?? '',
                style: TextStyle(
                  color: onSurface.withOpacity(0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              if (current != null)
                _ProgressBar(
                  currentTime: current.offset ?? 0,
                  totalTime: current.duration ?? 0,
                )
              else
                const _ProgressBar(
                  currentTime: 0,
                  totalTime: 0,
                  disabled: true,
                ),
              const SizedBox(height: 16),
              _Controls(),
              const SizedBox(height: 16),
              _Volume(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumCover(String? coverUrl, Color onSurface) {
    final glowColor = _dominantColor ?? Theme.of(context).colorScheme.primary;
    debugPrint('🎨 当前光圈颜色: $glowColor (提取的颜色: $_dominantColor)');

    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onSurface.withOpacity(0.06),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.4),
            blurRadius: 40,
            spreadRadius: 8,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: coverUrl != null && coverUrl.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator(
                    color: glowColor,
                  ),
                ),
                errorWidget: (context, url, error) => Icon(
                  Icons.music_note_rounded,
                  size: 96,
                  color: onSurface.withOpacity(0.8),
                ),
              ),
            )
          : Icon(
              Icons.music_note_rounded,
              size: 96,
              color: onSurface.withOpacity(0.8),
            ),
    );
  }

  Future<void> _extractDominantColor(String imageUrl) async {
    try {
      debugPrint('🎨 开始提取封面主色调: $imageUrl');
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      final extractedColor = paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      debugPrint('🎨 提取到的颜色: $extractedColor');
      debugPrint('🎨 主色调: ${paletteGenerator.dominantColor?.color}');
      debugPrint('🎨 鲜艳色: ${paletteGenerator.vibrantColor?.color}');

      if (mounted) {
        setState(() {
          _dominantColor = extractedColor;
        });
        debugPrint('🎨 颜色已应用到 UI');
      }
    } catch (e) {
      // 提取颜色失败，使用默认颜色
      debugPrint('❌ 提取封面主色调失败: $e');
    }
  }
}

class _ProgressBar extends ConsumerWidget {
  final int currentTime;
  final int totalTime;
  final bool disabled;
  const _ProgressBar({
    required this.currentTime,
    required this.totalTime,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final progress =
        totalTime > 0 ? (currentTime / totalTime).clamp(0.0, 1.0) : 0.0;
    return Column(
      children: [
        Slider(
          value: progress,
          onChanged: disabled ? null : (v) {},
          onChangeEnd:
              disabled
                  ? null
                  : (v) => ref
                      .read(playbackProvider.notifier)
                      .seekTo((v * totalTime).round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(currentTime),
              style: TextStyle(color: onSurface.withOpacity(0.7)),
            ),
            Text(
              _fmt(totalTime),
              style: TextStyle(color: onSurface.withOpacity(0.7)),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(int seconds) {
    if (seconds <= 0) return '0:00';
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Controls extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackProvider);
    final enabled =
        ref.read(deviceProvider).selectedDeviceId != null && !state.isLoading;
    final isPlaying = state.currentMusic?.isPlaying ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        IconButton(
          onPressed:
              enabled
                  ? () => ref.read(playbackProvider.notifier).previous()
                  : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 36,
        ),
        ElevatedButton(
          onPressed:
              enabled
                  ? () {
                    if (isPlaying) {
                      ref.read(playbackProvider.notifier).pauseMusic();
                    } else {
                      ref.read(playbackProvider.notifier).resumeMusic();
                    }
                  }
                  : null,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(18),
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 36,
          ),
        ),
        IconButton(
          onPressed:
              enabled ? () => ref.read(playbackProvider.notifier).next() : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 36,
        ),
      ],
    );
  }
}

class _Volume extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackProvider);
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
            onChanged:
                (v) => ref
                    .read(playbackProvider.notifier)
                    .setVolumeLocal(v.round()),
            onChangeEnd:
                (v) => ref.read(playbackProvider.notifier).setVolume(v.round()),
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
}
