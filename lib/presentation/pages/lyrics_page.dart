import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/playback_provider.dart';
import '../providers/lyric_provider.dart';
import '../providers/device_provider.dart';
import '../../data/models/device.dart';

/// 歌词页面
class LyricsPage extends ConsumerStatefulWidget {
  const LyricsPage({super.key});

  @override
  ConsumerState<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends ConsumerState<LyricsPage> {
  final ScrollController _scrollController = ScrollController();
  int _lastCurrentLine = -1;
  String? _lastSongName; // 🔧 记录上一次的歌曲名，用于检测歌曲切换
  double? _draggingProgress; // 🔧 拖动进度条时的临时进度值（0.0-1.0）

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final lyricState = ref.watch(lyricProvider);
    final current = playback.currentMusic;
    final coverUrl = playback.albumCoverUrl;

    // 🔧 检测歌曲切换，自动重新加载歌词
    final currentSongName = current?.curMusic ?? '';
    if (currentSongName.isNotEmpty && currentSongName != _lastSongName) {
      debugPrint('🎤 [LyricsPage] 检测到歌曲切换: $_lastSongName -> $currentSongName');
      _lastSongName = currentSongName;
      _lastCurrentLine = -1; // 重置当前行索引
      _draggingProgress = null; // 重置拖动状态

      // 延迟加载歌词，避免在 build 中调用
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('🎤 [LyricsPage] 自动重新加载歌词');
          ref.read(lyricProvider.notifier).loadLyrics(currentSongName);
        }
      });
    }

    // 🔧 计算当前应该显示的时间（拖动中显示预览时间，否则使用服务器的进度）
    final displayTime = _draggingProgress != null
        ? (_draggingProgress! * (current?.duration ?? 0)).round()
        : (current?.offset ?? 0);

    // 获取当前歌词行（基于显示时间）
    final currentLineIndex = current != null
        ? ref.read(lyricProvider.notifier).getCurrentLineIndex(displayTime)
        : -1;

    // 🔧 改进的滚动逻辑：拖动时立即滚动，播放时平滑滚动
    if (currentLineIndex >= 0 && currentLineIndex != _lastCurrentLine) {
      _lastCurrentLine = currentLineIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // 拖动时使用 jumpTo 立即定位，播放时使用 animateTo 平滑滚动
          if (_draggingProgress != null) {
            _scrollToLineInstant(currentLineIndex);
          } else {
            _scrollToLine(currentLineIndex);
          }
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 背景层:封面模糊图
          if (coverUrl != null && coverUrl.isNotEmpty)
            Positioned.fill(
              child: _buildBlurredBackground(coverUrl),
            ),

          // 主内容
          SafeArea(
            child: Column(
              children: [
                // 顶部信息栏
                _buildTopBar(current),

                // 歌词区域
                Expanded(
                  child: lyricState.isLoading
                      ? _buildLoading()
                      : (lyricState.lyric == null ||
                              !lyricState.lyric!.hasLyrics)
                          ? _buildNoLyrics()
                          : _buildLyricsContent(lyricState, currentLineIndex, displayTime),
                ),

                // 底部控制栏
                _buildBottomControls(current),
              ],
            ),
          ),

          // 🔧 调试用：屏幕中央参考线（可选，调试完成后可以注释掉）
          if (false) // 设置为 true 可以显示参考线
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 1,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                color: Colors.red.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建模糊背景
  Widget _buildBlurredBackground(String coverUrl) {
    return Stack(
      children: [
        // 封面图放大并模糊
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: coverUrl,
            fit: BoxFit.cover,
            imageBuilder: (context, imageProvider) {
              return Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                  ),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),
              );
            },
            errorWidget: (context, url, error) => Container(
              color: Colors.black,
            ),
          ),
        ),

        // 渐变遮罩
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.black.withOpacity(0.5),
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建顶部信息栏
  Widget _buildTopBar(dynamic currentMusic) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentMusic?.curMusic ?? '暂无播放',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  currentMusic?.curPlaylist ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 关闭按钮
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建加载状态
  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(
        color: Colors.white,
      ),
    );
  }

  /// 构建无歌词状态
  Widget _buildNoLyrics() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.music_note_rounded,
                size: 60,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无歌词',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '纯享音乐模式',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建歌词内容
  Widget _buildLyricsContent(dynamic lyricState, int currentLineIndex, int displayTime) {
    final lyric = lyricState.lyric!;
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;

    // 🔧 计算实际可用的歌词显示区域高度
    // 顶部栏高度：padding(16*2) + 内容高度约 60 = ~92
    // 底部控制栏高度：约 130（包括 margin）
    const topBarHeight = 92.0;
    const bottomControlHeight = 130.0;

    // 实际歌词区域高度
    final lyricsAreaHeight = screenHeight - safeAreaTop - topBarHeight - bottomControlHeight;

    // 🔧 当前行显示位置：区域高度的 40%（向上移动）
    const itemHeight = 90.0; // 与歌词行固定高度保持一致
    final topPadding = lyricsAreaHeight * 0.4 - (itemHeight / 2); // 40% 位置，居中歌词行
    final bottomPadding = lyricsAreaHeight * 0.6 - (itemHeight / 2);

    debugPrint('🎯 [Layout] 屏幕高度=$screenHeight, SafeArea顶部=$safeAreaTop');
    debugPrint('🎯 [Layout] 歌词区域高度=$lyricsAreaHeight, topPadding=$topPadding, bottomPadding=$bottomPadding');

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: bottomPadding,
      ),
      itemCount: lyric.lines.length,
      itemBuilder: (context, index) {
        final line = lyric.lines[index];
        final isCurrent = index == currentLineIndex;

        return GestureDetector(
          onTap: () {
            // 🎵 点击歌词行跳转播放（仅本地播放模式支持）
            final playbackState = ref.read(playbackProvider);
            if (playbackState.isLocalMode) {
              ref.read(playbackProvider.notifier).seekTo(line.timestamp);
            }
          },
          child: _buildLyricLine(line.text, isCurrent),
        );
      },
    );
  }

  /// 构建单行歌词（固定样式，通过位置判断大小）
  Widget _buildLyricLine(String text, bool isCurrent) {
    final displayText = text.isEmpty ? '♪' : text;
    final themeColor = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 90.0,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  displayText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isCurrent ? themeColor : Colors.white, // 🎨 当前行=青色，其他行=白色
                    fontSize: isCurrent ? 26 : 16, // 🎨 当前行字体更大
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDot(false),
                      const SizedBox(width: 8),
                      _buildDot(true),
                      const SizedBox(width: 8),
                      _buildDot(false),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建小圆点指示器
  Widget _buildDot(bool active) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(active ? 0.9 : 0.5),
        shape: BoxShape.circle,
      ),
    );
  }

  /// 构建底部控制栏
  Widget _buildBottomControls(dynamic currentMusic) {
    final isPlaying = currentMusic?.isPlaying ?? false;

    // 🎵 只有本地播放模式才允许拖动进度条
    final playbackState = ref.watch(playbackProvider);
    final canSeek = playbackState.isLocalMode && (currentMusic?.duration ?? 0) > 0;

    // 🔧 计算显示的进度（拖动中显示预览值，否则显示实际值）
    final displayProgress = _draggingProgress ??
        ((currentMusic?.duration ?? 0) > 0
            ? ((currentMusic?.offset ?? 0) / (currentMusic?.duration ?? 1))
                .clamp(0.0, 1.0)
            : 0.0);

    final displayTime = _draggingProgress != null
        ? (_draggingProgress! * (currentMusic?.duration ?? 0)).round()
        : (currentMusic?.offset ?? 0);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          Row(
            children: [
              Text(
                _fmt(displayTime),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    value: displayProgress,
                    onChanged: canSeek
                        ? (v) {
                            // 🔧 拖动时只更新预览，不执行 seek
                            setState(() {
                              _draggingProgress = v;
                            });
                          }
                        : null, // 🎵 远程播放模式禁用拖动
                    onChangeEnd: canSeek
                        ? (v) {
                            // 🔧 拖动结束时才执行 seek
                            final seekSeconds =
                                (v * (currentMusic!.duration)).round();
                            setState(() {
                              _draggingProgress = null; // 清除拖动状态
                            });
                            ref
                                .read(playbackProvider.notifier)
                                .seekTo(seekSeconds);
                          }
                        : null, // 🎵 远程播放模式禁用拖动
                    activeColor: Colors.white.withOpacity(0.85),
                    inactiveColor: Colors.white.withOpacity(0.25),
                  ),
                ),
              ),
              Text(
                _fmt(currentMusic?.duration ?? 0),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 播放控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一曲
              _buildControlButton(
                icon: Icons.skip_previous_rounded,
                onPressed: () => ref.read(playbackProvider.notifier).previous(),
              ),
              const SizedBox(width: 24),
              // 播放/暂停
              _buildControlButton(
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: () {
                  if (isPlaying) {
                    ref.read(playbackProvider.notifier).pauseMusic();
                  } else {
                    ref.read(playbackProvider.notifier).resumeMusic();
                  }
                },
                isPrimary: true,
              ),
              const SizedBox(width: 24),
              // 下一曲
              _buildControlButton(
                icon: Icons.skip_next_rounded,
                onPressed: () => ref.read(playbackProvider.notifier).next(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isPrimary
            ? Colors.white.withOpacity(0.95)
            : Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: isPrimary ? Theme.of(context).colorScheme.primary : Colors.white,
          size: isPrimary ? 32 : 28,
        ),
      ),
    );
  }

  /// 格式化时间
  String _fmt(int seconds) {
    if (seconds <= 0) return '0:00';
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 滚动到指定行（平滑动画）
  void _scrollToLine(int lineIndex) {
    if (!_scrollController.hasClients) return;

    // 🔧 计算目标位置：让指定行精确地显示在屏幕中央
    const itemHeight = 90.0; // 固定的每行高度

    // 目标偏移 = 行索引 * 行高
    // 因为 top padding = screenHeight / 2，所以第 0 行滚动到 offset=0 时就在屏幕中央
    final targetOffset = lineIndex * itemHeight;

    debugPrint('🎯 [Scroll] 平滑滚动到第 $lineIndex 行, offset=$targetOffset');

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 滚动到指定行（立即跳转，用于拖动进度条）
  void _scrollToLineInstant(int lineIndex) {
    if (!_scrollController.hasClients) return;

    // 🔧 计算目标位置：让指定行精确地显示在屏幕中央
    const itemHeight = 90.0; // 固定的每行高度

    // 目标偏移 = 行索引 * 行高
    final targetOffset = lineIndex * itemHeight;

    debugPrint('🎯 [Scroll] 立即跳转到第 $lineIndex 行, offset=$targetOffset');

    _scrollController.jumpTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }
}
