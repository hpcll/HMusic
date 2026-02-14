import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';

import '../providers/playlist_provider.dart';
import '../providers/local_playlist_provider.dart'; // 🎯 本地播放列表
import '../providers/direct_mode_provider.dart'; // 🎯 播放模式
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
import '../providers/music_library_provider.dart';
import '../providers/js_proxy_provider.dart'; // 🎯 JS代理（QuickJS）
import '../providers/js_source_provider.dart'; // 🎯 JS音源服务
import '../providers/playback_queue_provider.dart'; // 🎯 播放队列管理
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../../data/models/music.dart';
import '../../data/models/local_playlist.dart'; // 🎯 本地播放列表模型
import '../../data/models/playlist_item.dart'; // 🎯 统一播放列表项
import '../../data/models/playlist_queue.dart'; // 🎯 PlaylistSource 枚举
import '../../data/utils/lx_music_info_builder.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final String playlistName;
  final bool isLocalPlaylist;

  const PlaylistDetailPage({
    super.key,
    required this.playlistName,
    this.isLocalPlaylist = false,
  });

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  Map<String, String> _buildLibraryCoverMap(List<Music> musics) {
    final map = <String, String>{};

    for (final music in musics) {
      final picture = music.picture?.trim();
      if (picture == null || picture.isEmpty) continue;

      final name = music.name.trim();
      if (name.isNotEmpty) {
        map[name] = picture;
      }

      final title = music.title?.trim() ?? '';
      final artist = music.artist?.trim() ?? '';
      if (title.isNotEmpty && artist.isNotEmpty) {
        map['$title - $artist'] = picture;
      }
      if (title.isNotEmpty) {
        map.putIfAbsent(title, () => picture);
      }
    }

    return map;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!widget.isLocalPlaylist) {
        ref
            .read(playlistProvider.notifier)
            .loadPlaylistMusics(widget.playlistName);
      }
    });
  }

  Future<void> _playWholePlaylist() async {
    if (widget.isLocalPlaylist) {
      // 🎵 本地元歌单播放
      debugPrint('🎵 [PlaylistDetail] 元歌单播放: ${widget.playlistName}');

      // 获取歌单歌曲列表
      final localState = ref.read(localPlaylistProvider);
      try {
        final playlist = localState.playlists.firstWhere(
          (p) => p.name == widget.playlistName,
        );

        if (playlist.songs.isEmpty) {
          if (mounted) {
            AppSnackBar.showWarning(context, '歌单为空');
          }
          return;
        }

        // 🎯 根据当前播放模式获取设备 ID
        final playbackMode = ref.read(playbackModeProvider);
        final String deviceId;

        if (playbackMode == PlaybackMode.miIoTDirect) {
          // 直连模式
          final directState = ref.read(directModeProvider);
          if (directState is! DirectModeAuthenticated) {
            if (mounted) {
              AppSnackBar.showWarning(context, '请先登录直连模式');
            }
            return;
          }
          if (directState.playbackDeviceType.isEmpty) {
            if (mounted) {
              AppSnackBar.showWarning(context, '请先在控制页选择播放设备');
            }
            return;
          }
          deviceId = directState.playbackDeviceType;
        } else {
          // xiaomusic 模式
          final did = ref.read(deviceProvider).selectedDeviceId;
          if (did == null) {
            if (mounted) {
              AppSnackBar.showWarning(context, '请先在控制页选择播放设备');
            }
            return;
          }
          deviceId = did;
        }

        // 🎯 播放第一首歌曲（带URL缓存和自动重试）
        final firstSong = playlist.songs.first;

        // 🎯 设置播放队列（确保 _getCurrentQueueName() 能返回正确的歌单名）
        final queueItems = _localSongsToPlaylistItems(playlist.songs);
        ref.read(playbackQueueProvider.notifier).setQueue(
              queueName: widget.playlistName,
              source: PlaylistSource.customPlaylist,
              items: queueItems,
              startIndex: 0,
            );
        debugPrint(
          '🎯 [PlaylistDetail] 已设置元歌单队列: ${widget.playlistName}, ${queueItems.length}首',
        );

        // 🎯 解析URL（自动使用缓存或重新解析）
        var resolveResult = await _resolveUrlWithCache(firstSong, 0);
        String? playUrl = resolveResult.url;
        int? songDuration = resolveResult.duration;

        if (playUrl == null || playUrl.isEmpty) {
          if (mounted) {
            AppSnackBar.showError(
              context,
              '无法解析播放链接: ${firstSong.displayName}',
            );
          }
          return;
        }

        // 🎵 使用解析到的URL播放
        try {
          await ref
              .read(playbackProvider.notifier)
              .playMusic(
                deviceId: deviceId,
                musicName: firstSong.displayName,
                url: playUrl,
                albumCoverUrl: firstSong.coverUrl,
                playlistName: widget.playlistName,
                duration: songDuration,
              );

          if (mounted) {
            AppSnackBar.showSuccess(context, '正在播放: ${firstSong.displayName}');
          }
        } catch (e) {
          // 🔄 播放失败，可能是缓存URL失效，尝试强制刷新重试
          debugPrint('❌ [PlaylistDetail] 播放失败，尝试强制刷新缓存: $e');

          resolveResult = await _resolveUrlWithCache(
            firstSong,
            0,
            forceRefresh: true,
          );
          playUrl = resolveResult.url;
          songDuration = resolveResult.duration;

          if (playUrl == null || playUrl.isEmpty) {
            if (mounted) {
              AppSnackBar.showError(
                context,
                '无法解析播放链接: ${firstSong.displayName}',
              );
            }
            return;
          }

          // 🔁 使用新解析的URL重试播放
          try {
            await ref
                .read(playbackProvider.notifier)
                .playMusic(
                  deviceId: deviceId,
                  musicName: firstSong.displayName,
                  url: playUrl,
                  albumCoverUrl: firstSong.coverUrl,
                  playlistName: widget.playlistName,
                  duration: songDuration,
                );

            if (mounted) {
              AppSnackBar.showSuccess(
                context,
                '正在播放: ${firstSong.displayName}',
              );
            }
          } catch (e2) {
            // 第二次也失败，显示错误
            debugPrint('❌ [PlaylistDetail] 重试播放仍失败: $e2');
            if (mounted) {
              AppSnackBar.showError(context, '播放失败: ${e2.toString()}');
            }
          }
        }
      } catch (e) {
        debugPrint('❌ [PlaylistDetail] 播放歌单失败: $e');
        if (mounted) {
          AppSnackBar.showError(context, '播放失败: $e');
        }
      }
    } else {
      // 🎵 xiaomusic 模式：使用原有逻辑
      final did = ref.read(deviceProvider).selectedDeviceId;
      if (did == null) {
        if (mounted) {
          AppSnackBar.showWarning(context, '请先在设置中配置 NAS 服务器');
        }
        return;
      }
      await ref
          .read(playlistProvider.notifier)
          .playPlaylist(deviceId: did, playlistName: widget.playlistName);
    }
  }

  /// 🎯 将元歌单歌曲列表转为统一的 PlaylistItem 列表
  List<PlaylistItem> _localSongsToPlaylistItems(List<LocalPlaylistSong> songs) {
    return songs
        .map(
          (s) => PlaylistItem.fromOnlineMusic(
            title: s.title,
            artist: s.artist,
            duration: s.duration ?? 0,
            platform: s.platform,
            songId: s.songId,
            coverUrl: s.coverUrl,
          ),
        )
        .toList();
  }

  Future<void> _playSingle(String musicName) async {
    if (widget.isLocalPlaylist) {
      // 🎵 元歌单播放歌曲
      debugPrint('🎵 [PlaylistDetail] 元歌单播放歌曲: $musicName');

      // 🎯 根据当前播放模式获取设备 ID
      final playbackMode = ref.read(playbackModeProvider);
      final String deviceId;

      if (playbackMode == PlaybackMode.miIoTDirect) {
        // 直连模式
        final directState = ref.read(directModeProvider);
        if (directState is! DirectModeAuthenticated) {
          if (mounted) {
            AppSnackBar.showWarning(context, '请先登录直连模式');
          }
          return;
        }
        if (directState.playbackDeviceType.isEmpty) {
          if (mounted) {
            AppSnackBar.showWarning(context, '请先在控制页选择播放设备');
          }
          return;
        }
        deviceId = directState.playbackDeviceType;
      } else {
        // xiaomusic 模式
        final did = ref.read(deviceProvider).selectedDeviceId;
        if (did == null) {
          if (mounted) {
            AppSnackBar.showWarning(context, '请先在控制页选择播放设备');
          }
          return;
        }
        deviceId = did;
      }

      // 🎯 获取歌曲信息和索引
      final localState = ref.read(localPlaylistProvider);
      try {
        final playlist = localState.playlists.firstWhere(
          (p) => p.name == widget.playlistName,
        );

        // 找到对应歌曲的索引
        final songIndex = playlist.songs.indexWhere(
          (s) => s.displayName == musicName,
        );

        if (songIndex == -1) {
          throw Exception('歌曲不存在: $musicName');
        }

        final song = playlist.songs[songIndex];

        // 🎯 设置播放队列（确保 _getCurrentQueueName() 能返回正确的歌单名）
        final queueItems = _localSongsToPlaylistItems(playlist.songs);
        ref.read(playbackQueueProvider.notifier).setQueue(
              queueName: widget.playlistName,
              source: PlaylistSource.customPlaylist,
              items: queueItems,
              startIndex: songIndex,
            );
        debugPrint(
          '🎯 [PlaylistDetail] 已设置元歌单队列: ${widget.playlistName}, '
          '${queueItems.length}首, 当前第${songIndex + 1}首',
        );

        // 🎯 解析URL（自动使用缓存或重新解析）
        var resolveResult = await _resolveUrlWithCache(song, songIndex);
        String? playUrl = resolveResult.url;
        int? songDuration = resolveResult.duration;

        if (playUrl == null || playUrl.isEmpty) {
          if (mounted) {
            AppSnackBar.showError(context, '无法解析播放链接: $musicName');
          }
          return;
        }

        // 🎵 使用解析到的URL播放
        try {
          await ref
              .read(playbackProvider.notifier)
              .playMusic(
                deviceId: deviceId,
                musicName: musicName,
                url: playUrl,
                albumCoverUrl: song.coverUrl,
                playlistName: widget.playlistName,
                duration: songDuration,
              );
        } catch (e) {
          // 🔄 播放失败，可能是缓存URL失效，尝试强制刷新重试
          debugPrint('❌ [PlaylistDetail] 播放失败，尝试强制刷新缓存: $e');

          resolveResult = await _resolveUrlWithCache(
            song,
            songIndex,
            forceRefresh: true,
          );
          playUrl = resolveResult.url;
          songDuration = resolveResult.duration;

          if (playUrl == null || playUrl.isEmpty) {
            if (mounted) {
              AppSnackBar.showError(context, '无法解析播放链接: $musicName');
            }
            return;
          }

          // 🔁 使用新解析的URL重试播放
          try {
            await ref
                .read(playbackProvider.notifier)
                .playMusic(
                  deviceId: deviceId,
                  musicName: musicName,
                  url: playUrl,
                  albumCoverUrl: song.coverUrl,
                  playlistName: widget.playlistName,
                  duration: songDuration,
                );
          } catch (e2) {
            // 第二次也失败，显示错误
            debugPrint('❌ [PlaylistDetail] 重试播放仍失败: $e2');
            if (mounted) {
              AppSnackBar.showError(context, '播放失败: ${e2.toString()}');
            }
          }
        }
      } catch (e) {
        debugPrint('❌ [PlaylistDetail] 播放歌曲失败: $e');
        if (mounted) {
          AppSnackBar.showError(context, '播放失败: $e');
        }
      }
    } else {
      // 🎵 xiaomusic 模式：使用原有逻辑
      final did = ref.read(deviceProvider).selectedDeviceId;
      if (did == null) {
        if (mounted) {
          AppSnackBar.showWarning(context, '请先在控制页选择播放设备');
        }
        return;
      }

      // 🎵 获取当前歌单的歌曲，并转换为 Music 对象列表
      final state = ref.read(playlistProvider);
      final musicNames =
          state.currentPlaylist == widget.playlistName
              ? state.currentPlaylistMusics
              : <String>[];

      final playlist = musicNames.map((name) => Music(name: name)).toList();

      await ref
          .read(playbackProvider.notifier)
          .playMusic(
            deviceId: did,
            musicName: musicName,
            playlist: playlist, // 🎵 传递播放列表
            playlistName: widget.playlistName, // 🎵 传递歌单名
          );
    }
  }

  /// 显示歌曲操作菜单
  Future<void> _showMusicOptionsMenu(String musicName, int index) async {
    if (!mounted) return;

    // 本地元歌单不区分虚拟歌单
    final isVirtualPlaylist =
        widget.isLocalPlaylist
            ? false
            : _isVirtualPlaylist(widget.playlistName);

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  musicName,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const Divider(height: 1),
              // 对于虚拟播放列表,显示"添加到...";对于普通列表,显示"移动到..."和"复制到..."
              if (isVirtualPlaylist)
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('添加到...'),
                  onTap: () => Navigator.pop(context, 'add'),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.drive_file_move_rounded),
                  title: const Text('移动到...'),
                  onTap: () => Navigator.pop(context, 'move'),
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded),
                  title: const Text('复制到...'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
              ],
              // 从播放列表删除
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('从播放列表删除'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    // 处理用户选择
    switch (result) {
      case 'add':
        // 虚拟播放列表的"添加到..."操作,等同于"复制到..."
        await _showPlaylistSelector(musicName, isMove: false);
        break;
      case 'move':
        await _showPlaylistSelector(musicName, isMove: true);
        break;
      case 'copy':
        await _showPlaylistSelector(musicName, isMove: false);
        break;
      case 'delete':
        await _deleteMusicFromPlaylist(musicName, index);
        break;
    }
  }

  /// 检查是否为虚拟播放列表
  /// 虚拟播放列表无法通过 playlistdelmusic 接口删除歌曲
  bool _isVirtualPlaylist(String playlistName) {
    // 常见的虚拟播放列表名称
    const virtualPlaylists = ['下载', '所有歌曲', '全部', '临时搜索列表', '在线播放', '最近新增'];
    return virtualPlaylists.contains(playlistName);
  }

  /// 显示播放列表选择器
  Future<void> _showPlaylistSelector(
    String musicName, {
    required bool isMove,
  }) async {
    if (!mounted) return;

    if (widget.isLocalPlaylist) {
      AppSnackBar.showWarning(context, '本地元歌单暂不支持跨歌单移动/复制');
      return;
    }

    final state = ref.read(playlistProvider);
    final allPlaylists = state.playlists;

    // 过滤掉当前播放列表和虚拟播放列表(虚拟列表不能作为目标)
    final availablePlaylists =
        allPlaylists
            .where(
              (p) =>
                  p.name != widget.playlistName && !_isVirtualPlaylist(p.name),
            )
            .toList();

    if (availablePlaylists.isEmpty) {
      if (mounted) {
        AppSnackBar.showWarning(context, '没有可用的播放列表');
      }
      return;
    }

    final selectedPlaylist = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  isMove ? '移动到播放列表' : '添加到播放列表',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availablePlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = availablePlaylists[index];
                    return ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: Text(playlist.name),
                      subtitle:
                          playlist.count != null
                              ? Text('${playlist.count} 首歌曲')
                              : null,
                      onTap: () => Navigator.pop(context, playlist.name),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selectedPlaylist == null || !mounted) return;

    // 执行移动或复制操作
    try {
      if (isMove) {
        await ref
            .read(playlistProvider.notifier)
            .moveMusicToPlaylist(
              musicNames: [musicName],
              sourcePlaylistName: widget.playlistName,
              targetPlaylistName: selectedPlaylist,
            );
        if (mounted) {
          AppSnackBar.showSuccess(context, '已移动到 $selectedPlaylist');
        }
      } else {
        await ref
            .read(playlistProvider.notifier)
            .addMusicToPlaylist(
              musicNames: [musicName],
              playlistName: selectedPlaylist,
            );
        if (mounted) {
          AppSnackBar.showSuccess(context, '已复制到 $selectedPlaylist');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, '操作失败: $e');
      }
    }
  }

  /// 从播放列表删除歌曲
  Future<void> _deleteMusicFromPlaylist(String musicName, int index) async {
    if (!mounted) return;

    // 确认删除
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定要从歌单"${widget.playlistName}"中删除"$musicName"吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirm != true || !mounted) return;

    try {
      if (widget.isLocalPlaylist) {
        // 本地元歌单：使用索引删除
        await ref
            .read(localPlaylistProvider.notifier)
            .removeMusicFromPlaylist(
              playlistName: widget.playlistName,
              songIndices: [index],
            );
      } else {
        // 服务端歌单：使用歌曲名删除
        await ref
            .read(playlistProvider.notifier)
            .removeMusicFromPlaylist(
              musicNames: [musicName],
              playlistName: widget.playlistName,
            );
      }

      if (mounted) {
        AppSnackBar.showSuccess(context, '已删除');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, '删除失败: $e');
      }
    }
  }

  /// 🎯 解析播放URL（带缓存逻辑），同时返回 duration
  /// [song] 要播放的歌曲
  /// [songIndex] 歌曲在歌单中的索引（用于更新缓存）
  /// [forceRefresh] 强制刷新缓存（播放失败时使用）
  Future<({String? url, int? duration})> _resolveUrlWithCache(
    LocalPlaylistSong song,
    int songIndex, {
    bool forceRefresh = false,
  }) async {
    // 1. 检查缓存是否有效（除非强制刷新）
    if (!forceRefresh && song.isCacheValid) {
      debugPrint('✅ [PlaylistDetail] 使用缓存URL: ${song.displayName}');
      debugPrint('   缓存过期时间: ${song.urlExpireTime}');

      // 🎯 如果已有 duration，直接返回
      if (song.duration != null && song.duration! > 0) {
        return (url: song.cachedUrl, duration: song.duration);
      }

      // 🎯 旧歌曲没有 duration，用 just_audio 从缓存 URL 探测
      final probedDuration = await _probeDurationFromUrl(song.cachedUrl!);
      if (probedDuration != null && probedDuration > 0) {
        // 保存 duration 到 LocalPlaylistSong
        await ref.read(localPlaylistProvider.notifier).updateSongDuration(
              playlistName: widget.playlistName,
              songIndex: songIndex,
              duration: probedDuration,
            );
      }
      return (url: song.cachedUrl, duration: probedDuration ?? song.duration);
    }

    // 强制刷新时记录日志
    if (forceRefresh) {
      debugPrint('🔄 [PlaylistDetail] 强制刷新缓存: ${song.displayName}');
    }

    // 2. 缓存无效或不存在，解析新URL
    debugPrint('🔍 [PlaylistDetail] 缓存无效，开始解析URL: ${song.displayName}');
    final platform = song.platform ?? 'qq';
    final songId = song.songId ?? '';

    if (songId.isEmpty) {
      debugPrint('❌ [PlaylistDetail] 歌曲ID为空，无法解析');
      return (url: null, duration: null);
    }

    try {
      // 歌单播放解析使用固定高品质，不跟随“服务器下载音质”设置
      const quality = '320k';

      debugPrint('🔧 [PlaylistDetail] 开始URL解析');
      debugPrint('   平台: $platform, 歌曲ID: $songId, 解析音质: $quality');
      final musicInfo = buildLxMusicInfoFromLocalPlaylistSong(song);

      String? resolvedUrl;

      // 3. 尝试使用 QuickJS 解析
      try {
        debugPrint('🔍 [PlaylistDetail] 方法1: 尝试QuickJS解析');
        final jsProxy = ref.read(jsProxyProvider.notifier);
        final jsProxyState = ref.read(jsProxyProvider);

        debugPrint('   QuickJS状态:');
        debugPrint('     - isInitialized: ${jsProxyState.isInitialized}');
        debugPrint('     - currentScript: ${jsProxyState.currentScript}');
        debugPrint(
          '     - hasRequestHandler: ${jsProxyState.hasRequestHandler}',
        );

        if (jsProxyState.isInitialized && jsProxyState.currentScript != null) {
          debugPrint('   ✅ QuickJS已就绪，开始调用 getMusicUrl()');

          final mapped =
              (platform == 'qq')
                  ? 'tx'
                  : (platform == 'netease' || platform == '163')
                  ? 'wy'
                  : platform;

          debugPrint(
            '   调用参数: source=$mapped, songId=$songId, quality=$quality',
          );

          resolvedUrl = await jsProxy.getMusicUrl(
            source: mapped,
            songId: songId,
            quality: quality,
            musicInfo: musicInfo,
          );

          if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
            debugPrint(
              '✅ [PlaylistDetail] QuickJS解析成功: ${resolvedUrl.substring(0, resolvedUrl.length > 100 ? 100 : resolvedUrl.length)}...',
            );
          } else {
            debugPrint('❌ [PlaylistDetail] QuickJS解析失败：返回空结果');
          }
        } else {
          debugPrint('⚠️ [PlaylistDetail] QuickJS未就绪，跳过此方法');
          if (!jsProxyState.isInitialized) {
            debugPrint('     原因: 未初始化');
          }
          if (jsProxyState.currentScript == null) {
            debugPrint('     原因: 未加载脚本');
          }
        }
      } catch (e, stackTrace) {
        debugPrint('❌ [PlaylistDetail] QuickJS解析异常: $e');
        debugPrint(
          '   堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
        );
      }

      // 4. 回退到 WebView JS解析
      if (resolvedUrl == null || resolvedUrl.isEmpty) {
        try {
          debugPrint('🔍 [PlaylistDetail] 方法2: 尝试WebView JS解析');
          final webSvc = await ref.read(webviewJsSourceServiceProvider.future);

          if (webSvc != null) {
            debugPrint('   ✅ WebView服务可用，开始解析');
            resolvedUrl = await webSvc.resolveMusicUrl(
              platform: platform,
              songId: songId,
              quality: quality,
            );

            if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
              debugPrint(
                '✅ [PlaylistDetail] WebView JS解析成功: ${resolvedUrl.substring(0, resolvedUrl.length > 100 ? 100 : resolvedUrl.length)}...',
              );
            } else {
              debugPrint('❌ [PlaylistDetail] WebView JS解析失败：返回空结果');
            }
          } else {
            debugPrint('⚠️ [PlaylistDetail] WebView服务不可用');
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [PlaylistDetail] WebView JS解析异常: $e');
          debugPrint(
            '   堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
          );
        }
      }

      // 5. 回退到内置 JS解析
      if (resolvedUrl == null || resolvedUrl.isEmpty) {
        try {
          debugPrint('🔍 [PlaylistDetail] 方法3: 尝试内置JS解析');
          final jsSvc = await ref.read(jsSourceServiceProvider.future);

          if (jsSvc != null && jsSvc.isReady) {
            debugPrint('   ✅ 内置JS服务可用，开始解析');
            final js = """
              (function(){
                try{
                  console.log('[PlaylistDetail] 内置JS: 开始解析');
                  if (!lx || !lx.EVENT_NAMES) {
                    console.log('[PlaylistDetail] 内置JS: lx 环境不存在');
                    return '';
                  }
                  function mapPlat(p){ p=(p||'').toLowerCase(); if(p==='qq'||p==='tencent') return 'tx'; if(p==='netease'||p==='163') return 'wy'; if(p==='kuwo') return 'kw'; if(p==='kugou') return 'kg'; if(p==='migu') return 'mg'; return p; }
                  var musicInfo = ${jsonEncode(musicInfo)};
                  var payload = { action: 'musicUrl', source: mapPlat('$platform'), info: { type: '$quality', musicInfo: musicInfo } };
                  console.log('[PlaylistDetail] 内置JS: 调用 lx.emit，参数:', payload);
                  var res = lx.emit(lx.EVENT_NAMES.request, payload);
                  console.log('[PlaylistDetail] 内置JS: lx.emit 返回:', typeof res, res);
                  if (res && typeof res.then === 'function') {
                    console.log('[PlaylistDetail] 内置JS: 返回了Promise，不支持');
                    return '';
                  }
                  if (typeof res === 'string') {
                    console.log('[PlaylistDetail] 内置JS: 返回字符串:', res);
                    return res;
                  }
                  if (res && res.url) {
                    console.log('[PlaylistDetail] 内置JS: 返回对象url字段:', res.url);
                    return res.url;
                  }
                  console.log('[PlaylistDetail] 内置JS: 未返回有效结果');
                  return '';
                }catch(e){
                  console.log('[PlaylistDetail] 内置JS: 异常:', e);
                  return '';
                }
              })()
            """;
            resolvedUrl = jsSvc.evaluateToString(js);

            if (resolvedUrl.isNotEmpty) {
              debugPrint(
                '✅ [PlaylistDetail] 内置JS解析成功: ${resolvedUrl.substring(0, resolvedUrl.length > 100 ? 100 : resolvedUrl.length)}...',
              );
            } else {
              debugPrint('❌ [PlaylistDetail] 内置JS解析失败：返回空结果');
            }
          } else {
            debugPrint('⚠️ [PlaylistDetail] 内置JS服务不可用');
            if (jsSvc == null) {
              debugPrint('     原因: 服务为null');
            } else if (!jsSvc.isReady) {
              debugPrint('     原因: 服务未就绪');
            }
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [PlaylistDetail] 内置JS解析异常: $e');
          debugPrint(
            '   堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
          );
        }
      }

      // 6. 解析成功，更新缓存
      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        await ref
            .read(localPlaylistProvider.notifier)
            .updateSongCache(
              playlistName: widget.playlistName,
              songIndex: songIndex,
              cachedUrl: resolvedUrl,
            );

        // 🎯 如果没有 duration，用 just_audio 从新 URL 探测
        int? duration = song.duration;
        if (duration == null || duration <= 0) {
          duration = await _probeDurationFromUrl(resolvedUrl);
          if (duration != null && duration > 0) {
            await ref.read(localPlaylistProvider.notifier).updateSongDuration(
                  playlistName: widget.playlistName,
                  songIndex: songIndex,
                  duration: duration,
                );
          }
        }
        return (url: resolvedUrl, duration: duration);
      }

      debugPrint('❌ [PlaylistDetail] 所有解析方法均失败');
      return (url: null, duration: null);
    } catch (e) {
      debugPrint('❌ [PlaylistDetail] URL解析失败: $e');
      return (url: null, duration: null);
    }
  }

  /// 🎯 使用 just_audio 从 URL 探测音频时长
  Future<int?> _probeDurationFromUrl(String url) async {
    try {
      debugPrint('🎯 [PlaylistDetail] 探测音频时长: ${url.substring(0, url.length > 60 ? 60 : url.length)}...');
      final tempPlayer = AudioPlayer();
      try {
        final duration = await tempPlayer.setUrl(url).timeout(
          const Duration(seconds: 8),
        );
        if (duration != null && duration.inSeconds > 0) {
          debugPrint('✅ [PlaylistDetail] 探测到时长: ${duration.inSeconds}秒');
          return duration.inSeconds;
        }
        debugPrint('⚠️ [PlaylistDetail] 探测返回空时长');
        return null;
      } finally {
        await tempPlayer.dispose();
      }
    } catch (e) {
      debugPrint('⚠️ [PlaylistDetail] 探测时长失败: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final playbackState = ref.watch(playbackProvider);
    final libraryState = ref.watch(musicLibraryProvider);
    final libraryCoverMap = _buildLibraryCoverMap(libraryState.musicList);

    // 🎯 根据模式获取歌曲列表
    List<String> musics;
    List<LocalPlaylistSong>? songs; // 🎯 直连模式的完整歌曲对象（包含封面图）
    bool isLoading;

    if (widget.isLocalPlaylist) {
      // 本地元歌单：从本地播放列表获取歌曲（保存完整对象）
      final localState = ref.watch(localPlaylistProvider);
      isLoading = localState.isLoading;

      try {
        final playlist = localState.playlists.firstWhere(
          (p) => p.name == widget.playlistName,
        );
        songs = playlist.songs; // 🎯 保存完整的歌曲对象
        musics = songs.map((s) => s.displayName).toList(); // 同时保存歌曲名（用于显示）
      } catch (e) {
        // 播放列表不存在
        songs = [];
        musics = [];
      }
    } else {
      // xiaomusic 模式：从服务器播放列表获取歌曲（只有歌曲名）
      songs = null; // xiaomusic 模式不需要完整对象
      final state = ref.watch(playlistProvider);
      isLoading = state.isLoading;
      musics =
          state.currentPlaylist == widget.playlistName
              ? state.currentPlaylistMusics
              : <String>[];
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.playlistName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.isLocalPlaylist ? '本地元歌单' : '服务端歌单',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded),
            onPressed: _playWholePlaylist,
          ),
        ],
      ),
      body:
          isLoading && musics.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : musics.isEmpty
              ? Center(
                child: Text(
                  '此歌单暂无歌曲',
                  style: TextStyle(color: onSurface.withOpacity(0.6)),
                ),
              )
              : ListView.builder(
                padding: EdgeInsets.only(
                  bottom: AppLayout.contentBottomPadding(context),
                  top: 8,
                  left: 12,
                  right: 12,
                ),
                itemCount: musics.length,
                itemBuilder: (context, index) {
                  final musicName = musics[index];
                  final isLight =
                      Theme.of(context).brightness == Brightness.light;

                  // 🖼️ 获取封面图URL（优先级：歌单自带 > 曲库映射 > 当前播放状态）
                  final isCurrentlyPlaying =
                      playbackState.currentMusic?.curMusic == musicName;

                  String? coverUrl;
                  if (songs != null && index < songs.length) {
                    // 直连模式：优先使用歌曲对象的封面图
                    coverUrl = songs[index].coverUrl;
                  }

                  if (coverUrl == null || coverUrl.isEmpty) {
                    coverUrl = libraryCoverMap[musicName.trim()];
                  }

                  if ((coverUrl == null || coverUrl.isEmpty) &&
                      isCurrentlyPlaying) {
                    coverUrl = playbackState.albumCoverUrl;
                  }

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 3,
                      horizontal: 0,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isLight
                              ? Colors.black.withOpacity(0.03)
                              : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            isLight
                                ? Colors.black.withOpacity(0.06)
                                : Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minLeadingWidth: 32,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            coverUrl != null
                                ? CachedNetworkImage(
                                  imageUrl: coverUrl,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  placeholder:
                                      (context, url) => Container(
                                        width: 36,
                                        height: 36,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.1),
                                        child: Icon(
                                          Icons.music_note_rounded,
                                          size: 18,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ),
                                  errorWidget:
                                      (context, url, error) => Container(
                                        width: 36,
                                        height: 36,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.1),
                                        child: Icon(
                                          Icons.music_note_rounded,
                                          size: 18,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ),
                                )
                                : Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                      ),
                      title: Text(
                        musicName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isCurrentlyPlaying
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                          color:
                              isCurrentlyPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      trailing: SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            isCurrentlyPlaying
                                ? Icons.graphic_eq_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          iconSize: 20,
                          color:
                              isCurrentlyPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                          onPressed: () => _playSingle(musicName),
                        ),
                      ),
                      onTap: () => _playSingle(musicName),
                      onLongPress:
                          () => _showMusicOptionsMenu(musicName, index),
                    ),
                  );
                },
              ),
    );
  }
}
