import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
import '../providers/direct_mode_provider.dart'; // 🎯 直连模式Provider
import '../providers/lyric_provider.dart';
import '../widgets/app_snackbar.dart';
import 'lyrics_page.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  Color? _dominantColor;
  String? _lastCoverUrl;
  String? _colorExtractedUrl; // 🔧 已提取颜色的封面 URL（防止重复提取）

  @override
  void initState() {
    super.initState();
    // 🎨 颜色提取现在由 CachedNetworkImage.imageBuilder 自动处理，不需要在这里手动触发
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final current = playback.currentMusic;
    final coverUrl = playback.albumCoverUrl;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    debugPrint('🎨 build: coverUrl=$coverUrl, _lastCoverUrl=$_lastCoverUrl');

    // 🎨 当封面 URL 变化时，清除旧颜色 (颜色提取由 CachedNetworkImage.imageBuilder 处理)
    if (coverUrl != _lastCoverUrl) {
      debugPrint('🎨 检测到封面 URL 变化: $_lastCoverUrl -> $coverUrl');
      _lastCoverUrl = coverUrl;
      _dominantColor = null; // 立即清除旧颜色,等待新图片加载后提取
      _colorExtractedUrl = null; // 🔧 重置提取标记，允许新封面提取颜色
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
                current?.curPlaylist?.isNotEmpty == true
                    ? current!.curPlaylist!
                    : '未知歌单',  // ✅ 提供默认文本
                style: TextStyle(
                  color: onSurface.withOpacity(
                    current?.curPlaylist?.isNotEmpty == true ? 0.7 : 0.4  // ✅ 未知歌单显示更淡
                  ),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              if (current != null)
                _ProgressBar(
                  currentTime: current.offset,
                  totalTime: current.duration,
                  // 🔧 只有当歌曲名为空时或设备不支持 seek 时才禁用进度条
                  disabled: current.curMusic.isEmpty || !playback.seekEnabled,
                  isLocalMode: playback.isLocalMode, // 🎵 传递播放模式信息
                )
              else
                const _ProgressBar(
                  currentTime: 0,
                  totalTime: 0,
                  disabled: true,
                  isLocalMode: false, // 🎵 默认远程模式
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

    return GestureDetector(
      onTap: () {
        debugPrint('🎤 [点击封面] 触发点击事件');
        _openLyricsPage();
      },
      behavior: HitTestBehavior.opaque, // 🔧 确保整个区域都可点击
      child: Container(
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
                  // 🎨 图片加载完成后,延迟提取颜色(确保图片已缓存)
                  imageBuilder: (context, imageProvider) {
                    // 🔧 只有当这个 URL 还没有提取过颜色时，才提取
                    if (_colorExtractedUrl != coverUrl) {
                      _colorExtractedUrl = coverUrl; // 立即标记，防止重复
                      // 延迟提取颜色,避免与首次加载冲突
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted && coverUrl == ref.read(playbackProvider).albumCoverUrl) {
                          _extractDominantColorFromProvider(imageProvider);
                        }
                      });
                    }
                    return Image(image: imageProvider, fit: BoxFit.cover);
                  },
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

  /// 🎨 从已加载的 ImageProvider 提取主色调 (避免重复加载图片)
  Future<void> _extractDominantColorFromProvider(ImageProvider imageProvider) async {
    try {
      debugPrint('🎨 [NowPlaying] 从已加载的图片提取主色调');
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      final extractedColor = paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      debugPrint('🎨 [NowPlaying] 提取到的颜色: $extractedColor');
      debugPrint('🎨 [NowPlaying] 主色调: ${paletteGenerator.dominantColor?.color}');
      debugPrint('🎨 [NowPlaying] 鲜艳色: ${paletteGenerator.vibrantColor?.color}');

      if (mounted) {
        setState(() {
          _dominantColor = extractedColor;
        });
        debugPrint('🎨 [NowPlaying] 颜色已应用到 UI');
      }
    } catch (e) {
      // 提取颜色失败，使用默认颜色
      debugPrint('❌ [NowPlaying] 提取封面主色调失败: $e');
    }
  }
}

class _ProgressBar extends ConsumerStatefulWidget {
  final int currentTime;
  final int totalTime;
  final bool disabled;
  final bool isLocalMode; // 🎵 是否为本地播放模式

  const _ProgressBar({
    required this.currentTime,
    required this.totalTime,
    this.disabled = false,
    this.isLocalMode = false, // 🎵 默认为远程模式（不可拖动）
  });

  @override
  ConsumerState<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends ConsumerState<_ProgressBar> {
  double? _draggingValue; // 🔧 拖动时的临时进度值

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // 🔧 使用拖动值或实际进度值
    final displayTime = _draggingValue != null
        ? (_draggingValue! * widget.totalTime).round()
        : widget.currentTime;

    final progress = widget.totalTime > 0
        ? (displayTime / widget.totalTime).clamp(0.0, 1.0)
        : 0.0;

    debugPrint('🎯 [ProgressBar] disabled=${widget.disabled}, isLocalMode=${widget.isLocalMode}, progress=$progress, currentTime=${widget.currentTime}, totalTime=${widget.totalTime}');

    // 🎵 本地播放模式和直连模式都允许拖动进度条
    // 直连模式通过 player_set_positon ubus API 实现 seek
    final bool canSeek = !widget.disabled;

    return Column(
      children: [
        Slider(
          value: progress,
          onChanged: canSeek
              ? (v) {
                  // 🔧 拖动时更新临时值,实时显示进度
                  debugPrint('🎯 [ProgressBar] onChanged: $v');
                  setState(() {
                    _draggingValue = v;
                  });
                }
              : null, // 🎵 远程播放模式禁用拖动
          onChangeEnd: canSeek
              ? (v) {
                  // 🔧 拖动结束,清除临时值并执行 seek
                  final seekSeconds = (v * widget.totalTime).round();
                  debugPrint('🎯 [ProgressBar] onChangeEnd: $v, seekTo: $seekSeconds seconds');
                  setState(() {
                    _draggingValue = null;
                  });
                  ref
                      .read(playbackProvider.notifier)
                      .seekTo(seekSeconds);
                }
              : null, // 🎵 远程播放模式禁用拖动
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(displayTime),
              style: TextStyle(color: onSurface.withOpacity(0.7)),
            ),
            Text(
              _fmt(widget.totalTime),
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
    final playbackMode = ref.watch(playbackModeProvider);

    // 🎯 根据播放模式检查设备是否可用
    bool hasDevice = false;
    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 直连模式：检查是否已登录且选择了播放设备
      final directState = ref.watch(directModeProvider);
      hasDevice = directState is DirectModeAuthenticated &&
          directState.playbackDeviceType.isNotEmpty; // 🔧 修复：检查 playbackDeviceType
    } else {
      // xiaomusic 模式：检查是否选择了设备
      hasDevice = ref.read(deviceProvider).selectedDeviceId != null;
    }

    final enabled = hasDevice && !state.isLoading;
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
