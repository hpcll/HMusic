import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playback_provider.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackProvider);
    final currentMusic = playbackState.currentMusic;
    if (currentMusic == null) return const SizedBox.shrink();

    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isPlaying = currentMusic.isPlaying;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.music_note_rounded,
              color: onSurface.withOpacity(0.7),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentMusic.curMusic,
                  style: TextStyle(
                    color: onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  currentMusic.curPlaylist ?? '',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              if (isPlaying) {
                ref.read(playbackProvider.notifier).pauseMusic();
              } else {
                ref.read(playbackProvider.notifier).resumeMusic();
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.skip_next_rounded,
              color: onSurface.withOpacity(0.9),
            ),
            onPressed: () => ref.read(playbackProvider.notifier).next(),
          ),
        ],
      ),
    );
  }
}
