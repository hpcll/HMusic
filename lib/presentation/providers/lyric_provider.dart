import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/lyric.dart';
import '../../data/models/online_music_result.dart'; // 🆕 用于歌词匹配
import '../../data/services/lyric_service.dart';
import '../../data/services/lyric_parser_service.dart'; // 🆕 用于解析 LRC
import '../../data/services/music_api_service.dart';
import '../../data/services/native_music_search_service.dart';
import 'dio_provider.dart';

/// 歌词状态
class LyricState {
  final Lyric? lyric;
  final bool isLoading;
  final String? error;
  final String? currentSongName; // 当前加载歌词的歌曲名

  const LyricState({
    this.lyric,
    this.isLoading = false,
    this.error,
    this.currentSongName,
  });

  LyricState copyWith({
    Lyric? Function()? lyric, // 🔧 使用函数类型以支持显式设置 null
    bool? isLoading,
    String? error,
    String? currentSongName,
  }) {
    return LyricState(
      lyric: lyric != null ? lyric() : this.lyric,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentSongName: currentSongName ?? this.currentSongName,
    );
  }
}

/// 歌词Provider
class LyricNotifier extends StateNotifier<LyricState> {
  final Ref ref;
  LyricService? _lyricService;

  LyricNotifier(this.ref) : super(const LyricState());

  /// 初始化歌词服务（可选，无服务器模式不需要）
  void _ensureServiceInitialized() {
    if (_lyricService != null) return;

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️ [LyricProvider] 无服务器模式，跳过歌词服务初始化');
      return;
    }

    final nativeSearch = ref.read(nativeMusicSearchServiceProvider);
    _lyricService = LyricService(
      musicApi: apiService,
      nativeSearch: nativeSearch,
    );

    debugPrint('✅ [LyricProvider] 歌词服务已初始化');
  }

  /// 加载歌词
  Future<void> loadLyrics(String musicName, {bool autoScrape = true, bool forceReload = false}) async {
    // 🔧 防止重复加载相同歌曲的歌词（除非强制重新加载）
    if (!forceReload && state.currentSongName == musicName && state.lyric != null && !state.isLoading) {
      debugPrint('🎤 [LyricProvider] 歌词已加载，跳过: $musicName');
      return;
    }

    _ensureServiceInitialized();

    try {
      debugPrint('🎤 [LyricProvider] 开始加载歌词: $musicName');

      // 🔧 先清除旧歌词，避免显示上一首歌的内容
      state = state.copyWith(
        isLoading: true,
        error: null,
        currentSongName: musicName,
        lyric: () => null, // 立即清空旧歌词
      );

      Lyric? lyric;

      // 🎯 判断是否为无服务器模式（直连模式）
      if (_lyricService == null) {
        // 🚀 无服务器模式：直接刮削歌词
        debugPrint('🎤 [LyricProvider] 无服务器模式，直接刮削歌词');
        if (autoScrape) {
          lyric = await _scrapeLyricsDirectly(musicName);
        } else {
          debugPrint('⚠️ [LyricProvider] 跳过刮削');
          lyric = Lyric.empty();
        }
      } else {
        // 🎯 有服务器模式：使用 LyricService
        lyric = await _lyricService!.getLyrics(
          musicName: musicName,
          autoScrape: autoScrape,
        );
      }

      // 🔧 检查歌曲是否已经切换（避免异步加载完成后覆盖新歌曲的歌词）
      if (state.currentSongName != musicName) {
        debugPrint('⚠️ [LyricProvider] 歌曲已切换，放弃加载: $musicName');
        return;
      }

      state = state.copyWith(
        lyric: () => lyric,
        isLoading: false,
        error: null,
      );

      if (lyric != null && lyric.hasLyrics) {
        debugPrint('✅ [LyricProvider] 歌词加载成功: ${lyric.lines.length} 行');
      } else {
        debugPrint('⚠️ [LyricProvider] 无歌词');
      }
    } catch (e) {
      debugPrint('❌ [LyricProvider] 加载歌词失败: $e');
      state = state.copyWith(
        isLoading: false,
        error: '加载歌词失败: ${e.toString()}',
        lyric: () => Lyric.empty(),
      );
    }
  }

  /// 🎤 直接刮削歌词（无服务器模式专用）
  /// 从 "歌名 - 歌手" 格式解析，调用 QQ 音乐搜索歌词
  Future<Lyric?> _scrapeLyricsDirectly(String musicName) async {
    try {
      debugPrint('🔍 [LyricProvider] 直接刮削模式启动: $musicName');

      final nativeSearch = ref.read(nativeMusicSearchServiceProvider);
      final parser = LyricParserService();

      // 解析歌曲名,支持两种格式:
      // 1. "歌名 - 歌手" (标准格式)
      // 2. "歌手 - 歌名" (部分本地文件格式)
      final parts = musicName.split(' - ');
      String songName;
      String? artistName;

      if (parts.length >= 2) {
        // 尝试两种格式进行搜索
        songName = parts[0].trim();
        artistName = parts[1].trim();
        debugPrint('🔍 [LyricProvider] 解析: 部分1="$songName", 部分2="$artistName"');
      } else {
        songName = musicName;
        artistName = null;
        debugPrint('🔍 [LyricProvider] 解析: 单一名称="$songName"');
      }

      debugPrint('🔍 [LyricProvider] 开始搜索歌词...');

      // 优先使用QQ音乐获取歌词(QQ音乐歌词质量最好)
      try {
        // 先尝试用第一部分作为歌名搜索
        var results = await nativeSearch.searchQQ(query: songName, page: 1);

        // 如果没有结果且有第二部分,尝试用第二部分作为歌名搜索
        if (results.isEmpty && artistName != null) {
          debugPrint('⚠️ [LyricProvider] 第一次搜索无结果,尝试反转格式搜索');
          results = await nativeSearch.searchQQ(query: artistName, page: 1);
          // 交换歌名和艺术家名
          final temp = songName;
          songName = artistName;
          artistName = temp;
          debugPrint('🔄 [LyricProvider] 使用反转格式: 歌名="$songName", 艺术家="$artistName"');
        }

        if (results.isEmpty) {
          debugPrint('⚠️ [LyricProvider] QQ音乐搜索无结果');
          return Lyric.empty();
        }

        // 🎯 智能匹配:同时考虑歌名和艺术家
        OnlineMusicResult? bestMatch;
        OnlineMusicResult? fallbackMatch;

        debugPrint('🔍 [LyricProvider] 搜索结果数量: ${results.length}');

        for (final result in results) {
          debugPrint('  - ${result.title} - ${result.author} (songId: ${result.songId})');

          if (result.songId == null || result.songId!.isEmpty) continue;

          // 如果有艺术家名称,优先匹配艺术家
          if (artistName != null && artistName.isNotEmpty) {
            final resultArtist = result.author.toLowerCase().trim();
            final resultTitle = result.title.toLowerCase().trim();
            final targetArtist = artistName.toLowerCase().trim();
            final targetSong = songName.toLowerCase().trim();

            // 策略1: 艺术家名称匹配
            final artistMatch = resultArtist == targetArtist ||
                resultArtist.contains(targetArtist) ||
                targetArtist.contains(resultArtist);

            // 策略2: 歌名匹配
            final songMatch = resultTitle == targetSong ||
                resultTitle.contains(targetSong) ||
                targetSong.contains(resultTitle);

            // 最佳匹配: 艺术家和歌名都匹配
            if (artistMatch && songMatch) {
              bestMatch = result;
              debugPrint('✅ [LyricProvider] 找到完美匹配(艺术家+歌名): ${result.title} - ${result.author}');
              break;
            }

            // 次优匹配: 艺术家匹配
            if (artistMatch && bestMatch == null) {
              bestMatch = result;
              debugPrint('✅ [LyricProvider] 找到艺术家匹配: ${result.title} - ${result.author}');
            }
          }

          // 记录第一个有效结果作为备选
          fallbackMatch ??= result;
        }

        // 使用最佳匹配,如果没有则使用备选
        final selectedResult = bestMatch ?? fallbackMatch;

        if (bestMatch != null) {
          debugPrint('🎯 [LyricProvider] 使用匹配结果');
        } else if (fallbackMatch != null) {
          debugPrint('⚠️ [LyricProvider] 未找到精确匹配,使用第一个结果作为备选');
        }

        if (selectedResult != null) {
          debugPrint('🎤 [LyricProvider] 获取歌词: ${selectedResult.title} - ${selectedResult.author}');

          final lyricsText = await nativeSearch.getLyricsQQ(selectedResult.songId!);
          if (lyricsText != null && lyricsText.isNotEmpty) {
            debugPrint('✅ [LyricProvider] 获取到歌词,长度: ${lyricsText.length}');
            return parser.parseLrc(lyricsText);
          }
        }

        debugPrint('⚠️ [LyricProvider] 未找到可用歌词');
        return Lyric.empty();
      } catch (e) {
        debugPrint('❌ [LyricProvider] QQ音乐获取歌词失败: $e');
        return Lyric.empty();
      }
    } catch (e) {
      debugPrint('❌ [LyricProvider] 直接刮削歌词失败: $e');
      return Lyric.empty();
    }
  }

  /// 清除歌词
  void clearLyrics() {
    state = const LyricState();
  }

  /// 根据当前时间获取当前歌词行索引
  int getCurrentLineIndex(int currentTime) {
    if (state.lyric == null) return -1;
    return state.lyric!.getCurrentLineIndex(currentTime);
  }
}

/// 歌词Provider
final lyricProvider = StateNotifierProvider<LyricNotifier, LyricState>((ref) {
  return LyricNotifier(ref);
});
