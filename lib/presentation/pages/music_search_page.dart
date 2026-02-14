import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart'; // 🎯 用于缓存JS插件检测结果
import '../providers/js_proxy_provider.dart';
import '../providers/music_search_provider.dart';
import '../providers/source_settings_provider.dart';
import '../providers/js_script_manager_provider.dart';
import '../../data/models/online_music_result.dart';
import 'package:dio/dio.dart' as dio;
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/js_source_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../providers/device_provider.dart';
import '../providers/dio_provider.dart';
import '../../data/models/device.dart';
import '../providers/playback_provider.dart';
import '../providers/direct_mode_provider.dart';
import '../providers/playback_queue_provider.dart'; // 🎯 播放队列Provider
import '../../data/models/playlist_item.dart'; // 🎯 播放列表项模型
import '../../data/models/playlist_queue.dart'; // 🎯 播放队列模型
import '../providers/playlist_provider.dart'; // 🎯 播放列表Provider
import '../providers/local_playlist_provider.dart'; // 🎯 本地播放列表Provider
import '../../data/models/local_playlist.dart'; // 🎯 本地播放列表模型
import '../../data/utils/lx_music_info_builder.dart';

class MusicSearchPage extends ConsumerStatefulWidget {
  const MusicSearchPage({super.key});

  @override
  ConsumerState<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends ConsumerState<MusicSearchPage> {
  // legacy dialog removed

  // legacy play removed
  late final WebViewController _wvController;

  // 🎯 xiaomusic JS插件检测缓存
  static const String _jsPluginCacheKey = 'xiaomusic_has_js_plugins';
  static const String _jsPluginCacheTimeKey = 'xiaomusic_js_plugins_check_time';
  static const int _cacheExpireHours = 1; // 缓存过期时间：1小时
  @override
  void initState() {
    super.initState();
    _wvController = WebViewController();
    // 提供给 Provider 使用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webviewJsSourceControllerProvider.notifier).state =
          _wvController;
    });
  }

  /// 🎯 检测 xiaomusic 是否配置了 JS 插件（带缓存）
  ///
  /// 返回 true 表示有插件，使用插件模式
  /// 返回 false 表示无插件，使用懒加载模式
  Future<bool> _checkXiaomusicHasJsPlugins() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查缓存是否存在且未过期
      final cachedTime = prefs.getInt(_jsPluginCacheTimeKey);
      final cachedResult = prefs.getBool(_jsPluginCacheKey);

      if (cachedTime != null && cachedResult != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
        final expireMs = _cacheExpireHours * 60 * 60 * 1000;

        if (cacheAge < expireMs) {
          debugPrint(
            '[XiaomusicPluginCheck] 📦 使用缓存结果: $cachedResult (缓存年龄: ${cacheAge ~/ 1000}秒)',
          );
          return cachedResult;
        } else {
          debugPrint('[XiaomusicPluginCheck] ⏰ 缓存已过期，重新检测...');
        }
      } else {
        debugPrint('[XiaomusicPluginCheck] 🔍 首次检测JS插件配置...');
      }

      // 调用API检测
      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) {
        debugPrint('[XiaomusicPluginCheck] ⚠️ API服务未初始化，默认使用懒加载模式');
        return false;
      }

      final hasPlugins = await apiService.hasJsPlugins();
      debugPrint(
        '[XiaomusicPluginCheck] ✅ 检测结果: ${hasPlugins ? "有插件" : "无插件"}',
      );

      // 缓存结果
      await prefs.setBool(_jsPluginCacheKey, hasPlugins);
      await prefs.setInt(
        _jsPluginCacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('[XiaomusicPluginCheck] 💾 结果已缓存');

      return hasPlugins;
    } catch (e) {
      debugPrint('[XiaomusicPluginCheck] ❌ 检测失败: $e，默认使用懒加载模式');
      return false; // 检测失败时默认使用懒加载模式
    }
  }

  /// 显示音质相关提示信息

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(musicSearchProvider);

    return Scaffold(
      key: const ValueKey('music_search_scaffold'),
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            _buildContent(searchState),
            // 隐藏的 WebView 用于本地 JS 音源网络请求
            Offstage(
              offstage: true,
              child: SizedBox(
                height: 1,
                width: 1,
                child: WebViewWidget(controller: _wvController),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(MusicSearchState searchState) {
    if (searchState.isLoading) {
      return _buildLoadingIndicator();
    }
    if (searchState.error != null) {
      return _buildErrorState(searchState.error!);
    }
    if (searchState.onlineResults.isNotEmpty) {
      return _buildOnlineResultsList(searchState.onlineResults);
    }
    return _buildInitialState();
  }

  Widget _buildInitialState() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        // 模拟曲库页面的顶部布局间距，保持垂直位置一致
        const SizedBox(height: 20), // 对应曲库页面的顶部间距
        const SizedBox(height: 40), // 模拟搜索框高度 (TextField实际高度)
        const SizedBox(height: 16), // 对应曲库页面搜索框后的间距
        const SizedBox(height: 32), // 模拟统计信息区域的高度
        const SizedBox(height: 8), // 对应曲库页面统计信息后的间距
        Expanded(
          child: Center(
            key: const ValueKey('search_initial'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 80,
                  color: onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 20),
                Text(
                  '开始搜索音乐',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: onSurface.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '输入歌曲、艺术家或专辑名称',
                  style: TextStyle(
                    fontSize: 16,
                    color: onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      key: const ValueKey('search_loading'),
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorState(String error) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isSourceError = isSourceFailureError(error);
    final settingsNotifier = ref.read(sourceSettingsProvider.notifier);
    final currentStrategy = settingsNotifier.getCurrentStrategyName();
    final nextStrategy = settingsNotifier.getNextStrategyName();

    return Center(
      key: const ValueKey('search_error'),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSourceError
                  ? Icons.wifi_off_rounded
                  : Icons.error_outline_rounded,
              size: 60,
              color: isSourceError ? Colors.orange : Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              isSourceError ? '音源暂时不可用' : '哦豁，出错了',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(fontSize: 15, color: onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (isSourceError) ...[
              const SizedBox(height: 8),
              Text(
                '当前策略: $currentStrategy',
                style: TextStyle(
                  fontSize: 13,
                  color: onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 切换音源按钮
                  ElevatedButton.icon(
                    onPressed: () async {
                      await settingsNotifier.cycleSearchStrategy();
                      // 自动重试搜索
                      final query = ref.read(musicSearchProvider).searchQuery;
                      if (query.isNotEmpty) {
                        ref
                            .read(musicSearchProvider.notifier)
                            .searchOnline(query);
                      }
                    },
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: Text('切换到 $nextStrategy'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 手动重试按钮
              TextButton.icon(
                onPressed: () {
                  final query = ref.read(musicSearchProvider).searchQuery;
                  if (query.isNotEmpty) {
                    ref.read(musicSearchProvider.notifier).searchOnline(query);
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试当前策略'),
                style: TextButton.styleFrom(
                  foregroundColor: onSurface.withOpacity(0.7),
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              // 普通错误只显示重试按钮
              TextButton.icon(
                onPressed: () {
                  final query = ref.read(musicSearchProvider).searchQuery;
                  if (query.isNotEmpty) {
                    ref.read(musicSearchProvider.notifier).searchOnline(query);
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineResultsList(List<OnlineMusicResult> results) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final searchState = ref.watch(musicSearchProvider);
    final isLoadingMore = searchState.isLoadingMore;
    final hasMore = searchState.hasMore;

    final totalCount = results.length + (isLoadingMore ? 1 : 0);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (hasMore &&
              !isLoadingMore &&
              metrics.pixels >= metrics.maxScrollExtent - 200) {
            ref.read(musicSearchProvider.notifier).loadMore();
          }
        }
        return false;
      },
      child: ListView.separated(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        key: const ValueKey('online_search_results'),
        padding: EdgeInsets.only(
          bottom: AppLayout.contentBottomPadding(context),
          top: 12,
        ),
        itemCount: totalCount,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (isLoadingMore && index == totalCount - 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final item = results[index];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: onSurface.withOpacity(0.08),
              child: const Icon(Icons.audiotrack_rounded, size: 18),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              item.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12),
            ),
            trailing: PopupMenuButton<String>(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onSelected: (value) async {
                FocusManager.instance.primaryFocus?.unfocus();
                switch (value) {
                  case 'add_to_queue':
                    await _addToQueue(item);
                    break;
                  case 'add_to_playlist':
                    await _addToPlaylist(item);
                    break;
                  case 'server':
                    await _downloadToServer(item);
                    break;
                  case 'local':
                    await _downloadToLocal(item);
                    break;
                  case 'play':
                    await _playViaResolver(item);
                    break;
                }
              },
              itemBuilder: (context) {
                // 🎯 根据播放模式显示不同的菜单项
                final playbackMode = ref.watch(playbackModeProvider);
                final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;

                return [
                  const PopupMenuItem(value: 'play', child: Text('解析直链并播放')),
                  // 🎯 两种模式都显示"加入本地歌单（元音乐）"
                  const PopupMenuItem(
                    value: 'add_to_playlist',
                    child: Text('📋 加入本地歌单'),
                  ),
                  // 🎯 直连模式额外显示"加入播放队列"（用于当前播放队列）
                  if (isDirectMode)
                    const PopupMenuItem(
                      value: 'add_to_queue',
                      child: Text('➕ 加入播放队列'),
                    ),
                  // 🎯 只有 xiaomusic 模式才显示"下载到服务器"（直连模式无服务器）
                  if (!isDirectMode)
                    const PopupMenuItem(
                      value: 'server',
                      child: Text('下载到服务端歌单'),
                    ),
                  const PopupMenuItem(value: 'local', child: Text('下载到本地')),
                ];
              },
              icon: Icon(
                Icons.more_vert_rounded,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                size: 18,
              ),
            ),
            onTap: () => _playViaResolver(item),
          );
        },
      ),
    );
  }

  Future<void> _downloadToServer(OnlineMusicResult item) async {
    final settings = ref.read(sourceSettingsProvider);
    final quality = settings.defaultDownloadQuality;

    try {
      final selectedPlaylist = await _selectServerPlaylistForDownload();
      if (selectedPlaylist == null || selectedPlaylist.isEmpty) {
        return;
      }

      var url = item.url;
      if (url.isEmpty) {
        url = await _resolveWithQualityFallback(item, quality) ?? '';
      }

      if (url.isEmpty) {
        if (mounted) {
          AppSnackBar.showError(context, '❌ 无法解析直链，下载失败');
        }
        return;
      }

      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) {
        throw Exception('API 服务未初始化');
      }

      final serverName = _buildServerMusicName(item);
      final currentSettings = await apiService.getSettings();
      final originalDownloadPath =
          (currentSettings['download_path'] ?? 'music/download').toString();
      final targetDownloadPath = _buildDownloadPathForPlaylist(
        originalDownloadPath,
        selectedPlaylist,
      );
      final targetPlaylistName = selectedPlaylist;
      final targetDirname = _buildServerDirnameForPlaylist(selectedPlaylist);

      bool _isDownloadOneMusicParamUnsupported(
        String errorText,
        String paramName,
      ) {
        return errorText.contains('422') ||
            errorText.contains('validation') ||
            errorText.contains('extra_forbidden') ||
            errorText.contains('extra inputs are not permitted') ||
            (errorText.contains(paramName) && errorText.contains('field'));
      }

      // 优先尝试新后端：downloadonemusic(playlist_name)
      // playlist_name 传原始歌单名，不做安全化处理
      if (apiService.canAttemptDownloadOneMusicPlaylistName()) {
        final playlistNameSupported =
            await apiService.supportsDownloadOneMusicPlaylistName();
        if (playlistNameSupported) {
          try {
            final resp = await apiService.downloadOneMusic(
              musicName: serverName,
              url: url,
              playlistName: targetPlaylistName,
            );
            if (!(resp['ret'] == 'OK' || resp['success'] == true)) {
              throw Exception(resp.toString());
            }

            apiService.markDownloadOneMusicPlaylistNameSupported();

            if (mounted) {
              AppSnackBar.showSuccess(
                context,
                '已提交到歌单 "$selectedPlaylist"：${item.title}',
              );
            }
            return;
          } catch (e) {
            final errorText = e.toString().toLowerCase();
            final playlistNameUnsupported = _isDownloadOneMusicParamUnsupported(
              errorText,
              'playlist_name',
            );

            if (!playlistNameUnsupported) {
              rethrow;
            }

            apiService.markDownloadOneMusicPlaylistNameUnsupported();
            debugPrint(
              'ℹ️ [MusicSearch] 后端暂不支持 downloadonemusic.playlist_name，继续尝试 dirname',
            );
          }
        }
      }

      // 兼容旧后端：downloadonemusic(dirname)
      // 旧版本兼容策略（不读取 OpenAPI）：
      // - 本次运行第一次先尝试 dirname；
      // - 若确认不支持则标记，本次运行后续不再尝试，直接走回退逻辑。
      if (apiService.canAttemptDownloadOneMusicDirname()) {
        try {
          final resp = await apiService.downloadOneMusic(
            musicName: serverName,
            url: url,
            dirname: targetDirname,
          );
          if (!(resp['ret'] == 'OK' || resp['success'] == true)) {
            throw Exception(resp.toString());
          }

          apiService.markDownloadOneMusicDirnameSupported();

          if (mounted) {
            AppSnackBar.showSuccess(
              context,
              '已提交到歌单 "$selectedPlaylist"：${item.title}',
            );
          }
          return;
        } catch (e) {
          final errorText = e.toString().toLowerCase();
          final dirnameUnsupported =
              _isDownloadOneMusicParamUnsupported(errorText, 'dirname');

          if (!dirnameUnsupported) {
            rethrow;
          }

          apiService.markDownloadOneMusicDirnameUnsupported();
          debugPrint('ℹ️ [MusicSearch] 后端暂不支持 downloadonemusic.dirname，回退旧逻辑');
        }
      }

      bool changedPath = false;
      bool restoreFailed = false;
      try {
        if (targetDownloadPath != originalDownloadPath) {
          await apiService.modifySetting({'download_path': targetDownloadPath});
          changedPath = true;
        }

        final resp = await apiService.downloadOneMusic(
          musicName: serverName,
          url: url,
        );
        if (!(resp['ret'] == 'OK' || resp['success'] == true)) {
          throw Exception(resp.toString());
        }
      } finally {
        if (changedPath) {
          try {
            await apiService.modifySetting({
              'download_path': originalDownloadPath,
            });
          } catch (e) {
            restoreFailed = true;
            debugPrint('⚠️ [MusicSearch] 恢复 download_path 失败: $e');
          }
        }

        if (restoreFailed && mounted) {
          AppSnackBar.showWarning(context, '⚠️ 下载目录恢复失败，请检查设置页');
        }
      }

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          '已提交到歌单 "$selectedPlaylist"：${item.title}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, '下载失败：$e');
      }
    }
  }

  Future<String?> _selectServerPlaylistForDownload() async {
    final playlistNotifier = ref.read(playlistProvider.notifier);
    await playlistNotifier.refreshPlaylists();
    final playlistState = ref.read(playlistProvider);

    final customPlaylists = playlistState.deletablePlaylists.toList()..sort();
    final fallbackPlaylists =
        playlistState.playlists.map((p) => p.name).toSet().toList()..sort();
    final playlistNames =
        customPlaylists.isNotEmpty ? customPlaylists : fallbackPlaylists;

    if (!mounted) return null;

    if (playlistNames.isEmpty) {
      final newPlaylistName = await _showCreatePlaylistDialog();
      if (newPlaylistName == null || newPlaylistName.isEmpty) {
        return null;
      }
      await playlistNotifier.createPlaylist(newPlaylistName);
      return newPlaylistName;
    }

    final selected = await showDialog<String>(
      context: context,
      builder:
          (context) =>
              _PlaylistSelectionDialog(playlists: [...playlistNames, '➕ 新建歌单']),
    );

    if (selected == null || selected.isEmpty) {
      return null;
    }

    if (selected == '➕ 新建歌单') {
      final newPlaylistName = await _showCreatePlaylistDialog();
      if (newPlaylistName == null || newPlaylistName.isEmpty) {
        return null;
      }
      await playlistNotifier.createPlaylist(newPlaylistName);
      return newPlaylistName;
    }

    return selected;
  }

  String _buildDownloadPathForPlaylist(String basePath, String playlistName) {
    final safePlaylistName = playlistName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    final normalizedBase = basePath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');

    if (safePlaylistName.isEmpty) {
      return normalizedBase;
    }

    return '$normalizedBase/$safePlaylistName';
  }

  /// 生成 downloadonemusic.dirname（相对 music 根目录）
  ///
  /// 这里直接使用歌单名，确保落在 music/<歌单名>，便于被服务端识别为同名目录分类。
  String _buildServerDirnameForPlaylist(String playlistName) {
    return playlistName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _downloadToLocal(OnlineMusicResult item) async {
    // 本地下载与服务器下载统一：都跟随默认下载音质设置
    final settings = ref.read(sourceSettingsProvider);
    final quality = settings.defaultDownloadQuality;

    try {
      // 确定下载目录
      Directory dir;
      if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        // Android 11+ 需要 MANAGE_EXTERNAL_STORAGE 权限写入公共目录
        bool hasPermission = false;

        // 优先检查 MANAGE_EXTERNAL_STORAGE 权限（Android 11+）
        if (await Permission.manageExternalStorage.isGranted) {
          hasPermission = true;
        } else if (await Permission.storage.isGranted) {
          // 回退到普通存储权限（Android 10-）
          hasPermission = true;
        } else {
          // 请求权限
          final manageStatus = await Permission.manageExternalStorage.request();
          if (manageStatus.isGranted) {
            hasPermission = true;
          } else {
            // 回退请求普通存储权限
            final storageStatus = await Permission.storage.request();
            hasPermission = storageStatus.isGranted;
          }
        }

        if (!hasPermission) {
          if (mounted) {
            AppSnackBar.showError(context, '❌ 需要存储权限才能下载到本地');
          }
          return;
        }

        // 直接使用公共 Download 目录
        dir = Directory('/storage/emulated/0/Download/HMusic');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      // ⚠️ 放在权限确认之后再解析URL，避免授权弹窗期间链接过期导致404
      var url = item.url;
      if (url.isEmpty) {
        // 使用音质降级逻辑解析
        url = await _resolveWithQualityFallback(item, quality) ?? '';
      }

      if (url.isEmpty) {
        if (mounted) {
          AppSnackBar.showError(context, '❌ 无法解析直链，无法下载');
        }
        return;
      }

      final titlePart = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final authorPart = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName =
          authorPart.isNotEmpty ? '$titlePart - $authorPart' : titlePart;

      String buildFilePath(String targetUrl) {
        final ext = p.extension(Uri.parse(targetUrl).path);
        return p.join(dir.path, '$safeName${ext.isEmpty ? '.m4a' : ext}');
      }

      var downloadUrl = url;
      var savedFilePath = buildFilePath(downloadUrl);
      final client = dio.Dio();
      try {
        await client.download(
          downloadUrl,
          savedFilePath,
          options: dio.Options(
            responseType: dio.ResponseType.bytes,
            followRedirects: true,
          ),
        );
      } on dio.DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final canRetry = statusCode == 403 || statusCode == 404;

        if (!canRetry) rethrow;

        debugPrint('[XMC] ⚠️ 本地下载首次失败($statusCode)，尝试按音质链降级重试下载');

        var recovered = false;
        final qualities = _getQualityFallbackList(quality);
        for (final fallbackQuality in qualities) {
          final refreshedUrl = await _resolvePlayUrlForItem(
            item,
            quality: fallbackQuality,
          );

          if (refreshedUrl == null ||
              refreshedUrl.isEmpty ||
              refreshedUrl == downloadUrl) {
            continue;
          }

          final candidatePath = buildFilePath(refreshedUrl);

          try {
            debugPrint('[XMC] 🔄 本地下载重试音质: $fallbackQuality');
            await client.download(
              refreshedUrl,
              candidatePath,
              options: dio.Options(
                responseType: dio.ResponseType.bytes,
                followRedirects: true,
              ),
            );

            downloadUrl = refreshedUrl;
            savedFilePath = candidatePath;
            recovered = true;
            debugPrint('[XMC] ✅ 本地下载重试成功，音质: $fallbackQuality');
            break;
          } on dio.DioException catch (retryError) {
            final retryStatus = retryError.response?.statusCode;
            debugPrint('[XMC] ❌ 重试音质 $fallbackQuality 失败: $retryStatus');

            if (retryStatus != 403 && retryStatus != 404) {
              rethrow;
            }
          }
        }

        if (!recovered) rethrow;
      }

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          '已保存到本地: ${p.basename(savedFilePath)}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, '本地下载失败：$e');
      }
    }
  }

  /// 音质降级逻辑：按优先级尝试不同音质
  /// quality: 'lossless' | 'high' | 'standard'
  Future<String?> _resolveWithQualityFallback(
    OnlineMusicResult item,
    String targetQuality,
  ) async {
    // 根据目标音质确定尝试顺序
    final qualities = _getQualityFallbackList(targetQuality);

    debugPrint('[XMC] 🎵 开始音质降级解析: $targetQuality -> ${qualities.join(' → ')}');

    for (final quality in qualities) {
      debugPrint('[XMC] 🔍 尝试音质: $quality');
      final url = await _resolvePlayUrlForItem(item, quality: quality);
      if (url != null && url.isNotEmpty) {
        debugPrint('[XMC] ✅ 成功解析音质 $quality');
        return url;
      }
      debugPrint('[XMC] ❌ 音质 $quality 解析失败，尝试下一个');
    }

    debugPrint('[XMC] ❌ 所有音质均解析失败');
    return null;
  }

  /// 获取音质降级列表
  List<String> _getQualityFallbackList(String target) {
    switch (target) {
      case 'hires24':
      case '24bitflac':
      case 'flac24bit':
      case 'flac24':
        return ['flac24bit', 'hires', 'flac', '320k', '128k'];
      case 'lossless':
      case 'flac':
        return ['flac', '320k', '128k'];
      case 'high':
        return ['320k', '128k'];
      case 'standard':
      default:
        return ['128k'];
    }
  }

  Future<String?> _resolvePlayUrlForItem(
    OnlineMusicResult item, {
    String quality = '320k',
  }) async {
    try {
      final platform = (item.platform ?? 'qq');
      final id = item.songId ?? '';
      if (id.isEmpty) return null;
      final musicInfo = buildLxMusicInfoFromOnlineResult(item);

      // 0) 优先使用新的 QuickJS 代理解析（若已加载脚本）
      try {
        final jsProxy = ref.read(jsProxyProvider.notifier);
        final jsProxyState = ref.read(jsProxyProvider);
        if (jsProxyState.isInitialized && jsProxyState.currentScript != null) {
          final mapped =
              (platform == 'qq')
                  ? 'tx'
                  : (platform == 'netease' || platform == '163')
                  ? 'wy'
                  : platform;
          final url = await jsProxy.getMusicUrl(
            source: mapped,
            songId: id,
            quality: quality,
            musicInfo: musicInfo,
          );
          if (url != null && url.isNotEmpty) return url;
        }
      } catch (_) {}

      // 1) 隐藏WebView JS解析
      try {
        final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
        if (webSvc != null) {
          final url = await webSvc.resolveMusicUrl(
            platform: platform,
            songId: id,
            quality: quality,
          );
          if (url != null && url.isNotEmpty) return url;
        }
      } catch (_) {}

      // 2) 回退到内置 LocalJS 解析
      try {
        final jsSvc = await ref.read(jsSourceServiceProvider.future);
        if (jsSvc != null && jsSvc.isReady) {
          final js = """
            (function(){
              try{
                if (!lx || !lx.EVENT_NAMES) return '';
                function mapPlat(p){ p=(p||'').toLowerCase(); if(p==='qq'||p==='tencent') return 'tx'; if(p==='netease'||p==='163') return 'wy'; if(p==='kuwo') return 'kw'; if(p==='kugou') return 'kg'; if(p==='migu') return 'mg'; return p; }
                var musicInfo = ${jsonEncode(musicInfo)};
                var payload = { action: 'musicUrl', source: mapPlat('$platform'), info: { type: '$quality', musicInfo: musicInfo } };
                var res = lx.emit(lx.EVENT_NAMES.request, payload);
                if (res && typeof res.then === 'function') return '';
                if (typeof res === 'string') return res;
                if (res && res.url) return res.url;
                return '';
              }catch(e){ return '' }
            })()
          """;
          final url = jsSvc.evaluateToString(js);
          if (url.isNotEmpty) return url;
        }
      } catch (_) {}

      // 🚫 不再回退到统一API，保持 JS 音源的纯净性
      print('[XMC] ⚠️ [Resolve] 所有JS解析方法均失败，返回null');
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 🎵 添加到播放队列
  Future<void> _addToQueue(OnlineMusicResult item) async {
    try {
      // 🎯 检查播放模式
      final playbackMode = ref.read(playbackModeProvider);

      // 只在直连模式下支持队列功能
      if (playbackMode != PlaybackMode.miIoTDirect) {
        if (mounted) {
          AppSnackBar.showWarning(
            context,
            '⚠️ 播放队列功能仅在直连模式下可用',
            duration: const Duration(seconds: 3),
          );
        }
        return;
      }

      // 创建 PlaylistItem
      final playlistItem = PlaylistItem.fromOnlineMusic(
        title: item.title,
        artist: item.author,
        album: item.album,
        duration: item.duration ?? 0,
        platform: item.platform,
        songId: item.songId,
        coverUrl: item.picture,
      );

      // 添加到队列
      ref.read(playbackQueueProvider.notifier).addToQueue(playlistItem);

      // 显示成功提示
      if (mounted) {
        final queueState = ref.read(playbackQueueProvider);
        final queueLength = queueState.queue?.items.length ?? 1;

        AppSnackBar.showSuccess(
          context,
          '✅ 已加入播放队列: ${item.title}\n当前队列: $queueLength 首歌',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      debugPrint('❌ [MusicSearch] 添加到队列失败: $e');
      if (mounted) {
        AppSnackBar.showError(
          context,
          '❌ 添加失败: $e',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  /// 🎯 显示创建歌单对话框（返回歌单名称，取消返回 null）
  Future<String?> _showCreatePlaylistDialog() async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '新建歌单',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '输入歌单名称',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.pop(context, value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                '取消',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context, name);
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  /// 📋 添加到本地歌单（元音乐）
  Future<void> _addToPlaylist(OnlineMusicResult item) async {
    try {
      final playlists = ref.read(localPlaylistProvider).playlists;

      if (playlists.isEmpty) {
        // 没有歌单，直接在这里创建并添加歌曲
        if (mounted) {
          final newPlaylistName = await _showCreatePlaylistDialog();

          if (newPlaylistName != null && newPlaylistName.isNotEmpty) {
            // 🎯 创建歌单成功，直接添加歌曲
            debugPrint('📋 [MusicSearch] 创建歌单并添加: $newPlaylistName');

            await ref
                .read(localPlaylistProvider.notifier)
                .createPlaylist(newPlaylistName);

            final song = LocalPlaylistSong.fromOnlineMusic(
              title: item.title,
              artist: item.author,
              platform: item.platform ?? 'unknown',
              songId: item.songId ?? '',
              coverUrl: item.picture,
              duration: item.duration,
            );

            await ref
                .read(localPlaylistProvider.notifier)
                .addMusicToPlaylist(
                  playlistName: newPlaylistName,
                  songs: [song],
                );

            // 显示成功提示
            if (mounted) {
              AppSnackBar.showSuccess(
                context,
                '✅ 已创建歌单 "$newPlaylistName" 并添加歌曲',
              );
            }
          }
        }
        return;
      }

      // 显示歌单选择对话框
      if (mounted) {
        final selectedPlaylist = await showDialog<String>(
          context: context,
          builder:
              (context) => _PlaylistSelectionDialog(
                playlists:
                    playlists
                        .map((p) => (p as dynamic).name as String)
                        .toList(),
              ),
        );

        if (selectedPlaylist != null && selectedPlaylist.isNotEmpty) {
          debugPrint('📋 [MusicSearch] 添加到本地歌单: $selectedPlaylist');

          // 🎯 只保存元数据（platform + songId + title + artist），不保存URL
          // 播放时才根据这些元数据解析URL，解析后缓存
          final song = LocalPlaylistSong.fromOnlineMusic(
            title: item.title,
            artist: item.author,
            platform: item.platform ?? 'unknown',
            songId: item.songId ?? '',
            coverUrl: item.picture,
          );

          await ref
              .read(localPlaylistProvider.notifier)
              .addMusicToPlaylist(
                playlistName: selectedPlaylist,
                songs: [song],
              );

          if (mounted) {
            AppSnackBar.showSuccess(
              context,
              '✅ 已添加到 "$selectedPlaylist"',
              duration: const Duration(seconds: 3),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [MusicSearch] 添加到歌单失败: $e');
      if (mounted) {
        AppSnackBar.showError(
          context,
          '❌ 添加失败: $e',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  String _buildServerMusicName(OnlineMusicResult item) {
    final safeTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeAuthor = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return safeAuthor.isNotEmpty ? '$safeTitle - $safeAuthor' : safeTitle;
  }

  /// 🎵 xiaomusic插件模式播放
  ///
  /// 当检测到xiaomusic配置了JS插件时，使用此方法：
  /// 1. 将搜索结果列表推送给xiaomusic服务器
  /// 2. 服务器通过配置的JS插件自行解析URL
  /// 3. APP不需要管理队列，服务器端管理
  Future<void> _playViaXiaomusicPluginMode(OnlineMusicResult item) async {
    try {
      debugPrint('[XiaomusicPlugin] 🔌 开始插件模式播放: ${item.title}');

      // 1. 获取设备ID
      final deviceState = ref.read(deviceProvider);
      final selectedDeviceId = deviceState.selectedDeviceId;

      if (selectedDeviceId == null) {
        if (mounted) {
          AppSnackBar.showError(context, '❌ 请先选择播放设备');
        }
        return;
      }

      // 2. 获取API服务
      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) {
        throw Exception('API服务未初始化');
      }

      // 3. 构建歌曲列表（从搜索结果）
      final searchState = ref.read(musicSearchProvider);
      final List<Map<String, dynamic>> songList =
          searchState.onlineResults.map<Map<String, dynamic>>((result) {
            // 平台映射
            String mappedPlatform;
            switch ((result.platform ?? 'qq').toLowerCase()) {
              case 'qq':
              case 'tencent':
                mappedPlatform = 'tx';
                break;
              case 'netease':
              case 'wangyi':
              case '163':
                mappedPlatform = 'wy';
                break;
              case 'kugou':
                mappedPlatform = 'kg';
                break;
              case 'kuwo':
                mappedPlatform = 'kw';
                break;
              case 'migu':
                mappedPlatform = 'mg';
                break;
              default:
                mappedPlatform = 'tx';
            }

            return {
              'name': '${result.title} - ${result.author}',
              'id': result.songId ?? '',
              'source': mappedPlatform,
              'title': result.title,
              'artist': result.author,
              'album': result.album ?? '',
              'duration': result.duration ?? 0,
              'pic': result.picture ?? '',
            };
          }).toList();

      // 4. 找到当前点击歌曲在列表中的位置，并将其放到第一位
      final clickedIndex = songList.indexWhere(
        (s) => s['id'] == item.songId && s['title'] == item.title,
      );

      if (clickedIndex > 0) {
        // 重排列表：点击的歌曲放到第一位，后面的歌曲依次排列
        final reorderedList = <Map<String, dynamic>>[];
        reorderedList.addAll(songList.sublist(clickedIndex));
        reorderedList.addAll(songList.sublist(0, clickedIndex));
        songList.clear();
        songList.addAll(reorderedList);
      }

      debugPrint('[XiaomusicPlugin] 📋 推送歌曲列表: ${songList.length} 首');

      // 5. 调用 pushList API
      final result = await apiService.pushSongList(
        did: selectedDeviceId,
        songList: songList,
        playlistName: '在线播放',
      );

      debugPrint('[XiaomusicPlugin] ✅ 推送结果: $result');

      // 6. 显示成功提示
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          '🎵 正在播放: ${item.title}',
          duration: const Duration(seconds: 2),
        );
      }

      // 7. 刷新播放状态
      await Future.delayed(const Duration(milliseconds: 1500));
      await ref.read(playbackProvider.notifier).refreshStatus();
    } catch (e, stackTrace) {
      debugPrint('[XiaomusicPlugin] ❌ 插件模式播放失败: $e');
      debugPrint(
        '[XiaomusicPlugin] 堆栈: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );

      if (mounted) {
        AppSnackBar.showError(
          context,
          '❌ 插件模式播放失败: ${e.toString()}',
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  /// 🎵 直连模式播放音乐
  Future<void> _playViaDirectMode(OnlineMusicResult item) async {
    try {
      debugPrint('[DirectMode] 🎵 开始直连模式播放: ${item.title}');

      // 1. 获取直连模式状态
      final directState = ref.read(directModeProvider);

      if (directState is! DirectModeAuthenticated) {
        if (mounted) {
          AppSnackBar.showError(context, '❌ 直连模式未登录，请先登录');
        }
        return;
      }

      if (directState.devices.isEmpty) {
        if (mounted) {
          AppSnackBar.showWarning(context, '❌ 没有可用的小米设备');
        }
        return;
      }

      // 2. 使用第一个设备（后续可以优化为让用户选择）
      final device = directState.devices.first;
      debugPrint('[DirectMode] 🎵 使用设备: ${device.name} (${device.deviceId})');

      // 3. 解析音乐URL（如果需要）
      String playUrl = item.url;
      if (playUrl.isEmpty) {
        // 需要解析直链
        debugPrint('[DirectMode] 🔍 需要解析直链');
        playUrl = await _resolveWithQualityFallback(item, '320k') ?? '';
      }

      if (playUrl.isEmpty) {
        if (mounted) {
          AppSnackBar.showError(context, '❌ 无法解析播放链接');
        }
        return;
      }

      debugPrint(
        '[DirectMode] ✅ 播放链接已准备: ${playUrl.substring(0, playUrl.length > 100 ? 100 : playUrl.length)}...',
      );

      // 🎯 创建播放队列（仅直连模式）
      final searchState = ref.read(musicSearchProvider);
      if (searchState.onlineResults.isNotEmpty) {
        debugPrint(
          '[DirectMode] 🎵 创建播放队列: ${searchState.onlineResults.length} 首',
        );

        // 转换为 PlaylistItem 列表
        final playlistItems =
            searchState.onlineResults.map((result) {
              return PlaylistItem.fromOnlineMusic(
                title: result.title,
                artist: result.author,
                album: result.album,
                duration: result.duration ?? 0,
                platform: result.platform,
                songId: result.songId,
                coverUrl: result.picture,
              );
            }).toList();

        // 找到当前点击歌曲的索引
        final startIndex = searchState.onlineResults.indexWhere(
          (r) => r.songId == item.songId && r.title == item.title,
        );

        // 设置队列
        ref
            .read(playbackQueueProvider.notifier)
            .setQueue(
              queueName: '搜索结果: ${searchState.searchQuery}',
              source: PlaylistSource.searchResult,
              items: playlistItems,
              startIndex: startIndex >= 0 ? startIndex : 0,
            );

        debugPrint(
          '[DirectMode] ✅ 播放队列已创建，起始索引: ${startIndex >= 0 ? startIndex : 0}',
        );
      }

      // 4. 显示播放提示
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          '🎵 正在播放: ${item.title}',
          duration: const Duration(seconds: 2),
        );
      }

      // 5. 🎯 通过 PlaybackProvider 播放（正确的架构！）
      // 这样可以：
      // ✅ 使用已初始化的策略实例（带回调）
      // ✅ 自动更新 UI 状态
      // ✅ 自动搜索封面图
      // ✅ 自动更新通知栏
      await ref
          .read(playbackProvider.notifier)
          .playMusic(
            deviceId: device.deviceId,
            musicName: '${item.title} - ${item.author}',
            url: playUrl,
            albumCoverUrl: item.picture, // 🎨 传入封面图URL（搜索结果自带）
            playlistName: '搜索结果',
          );

      debugPrint('[DirectMode] ✅ 播放请求已通过 PlaybackProvider 发送');
    } catch (e, stackTrace) {
      debugPrint('[DirectMode] ❌ 播放失败: $e');
      debugPrint(
        '[DirectMode] 堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );

      if (mounted) {
        AppSnackBar.showError(
          context,
          '❌ 播放失败: ${e.toString()}',
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  Future<void> _playViaResolver(OnlineMusicResult item) async {
    // 🆕 检查播放模式,优先使用直连模式
    final playbackMode = ref.read(playbackModeProvider);

    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 🎵 直连模式播放
      await _playViaDirectMode(item);
      return;
    }

    // 🎵 xiaomusic 模式播放
    final id = item.songId ?? '';

    if (id.isEmpty) {
      if (mounted) {
        AppSnackBar.showError(context, '❌ 缺少歌曲标识，无法播放');
      }
      return;
    }

    // 🎯 智能路由：检测 xiaomusic 是否配置了 JS 插件
    final hasXiaomusicPlugins = await _checkXiaomusicHasJsPlugins();

    if (hasXiaomusicPlugins) {
      // 🎯 插件模式：使用 pushList，让 xiaomusic 服务器通过插件解析
      debugPrint('[XiaomusicRouter] 🔌 检测到JS插件，使用插件模式');
      await _playViaXiaomusicPluginMode(item);
      return;
    }

    // 🎯 懒加载模式：APP端管理队列，逐个解析URL
    debugPrint('[XiaomusicRouter] 📱 无JS插件，使用懒加载模式');

    // 创建播放队列（懒加载模式需要）
    final searchState = ref.read(musicSearchProvider);
    if (searchState.onlineResults.isNotEmpty) {
      debugPrint(
        '[XiaomusicQueue] 🎵 创建播放队列: ${searchState.onlineResults.length} 首',
      );

      // 转换为 PlaylistItem 列表
      final playlistItems =
          searchState.onlineResults.map((result) {
            return PlaylistItem.fromOnlineMusic(
              title: result.title,
              artist: result.author,
              album: result.album,
              duration: result.duration ?? 0,
              platform: result.platform,
              songId: result.songId,
              coverUrl: result.picture,
            );
          }).toList();

      // 找到当前点击歌曲的索引
      final startIndex = searchState.onlineResults.indexWhere(
        (r) => r.songId == item.songId && r.title == item.title,
      );

      // 设置队列
      ref
          .read(playbackQueueProvider.notifier)
          .setQueue(
            queueName: '搜索结果: ${searchState.searchQuery}',
            source: PlaylistSource.searchResult,
            items: playlistItems,
            startIndex: startIndex >= 0 ? startIndex : 0,
          );

      debugPrint(
        '[XiaomusicQueue] ✅ 播放队列已创建，起始索引: ${startIndex >= 0 ? startIndex : 0}',
      );
    }

    // 🎯 使用统一的 playOnlineItem 方法播放
    // 通过 PlaybackProvider 统一处理 URL 解析 + 播放，确保搜索播放和自动下一首流程一致

    try {
      // 🎯 检查用户音源设置和JS脚本状态（保留用户友好提示）
      final settings = ref.read(sourceSettingsProvider);
      if (settings.primarySource == 'js_external') {
        final scripts = ref.read(jsScriptManagerProvider);
        final scriptManager = ref.read(jsScriptManagerProvider.notifier);
        final selectedScript = scriptManager.selectedScript;

        if (scripts.isEmpty) {
          if (mounted) {
            AppSnackBar.showWarning(
              context,
              '❌ 未导入JS脚本\n请先在设置中导入JS脚本才能播放音乐',
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '去导入',
                textColor: Colors.white,
                onPressed: () {
                  context.push('/settings/source');
                },
              ),
            );
          }
          return;
        } else if (selectedScript == null) {
          if (mounted) {
            AppSnackBar.showWarning(
              context,
              '❌ 未选择JS脚本\n已导入${scripts.length}个脚本，请选择一个使用',
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '去选择',
                textColor: Colors.white,
                onPressed: () {
                  context.push('/settings/source');
                },
              ),
            );
          }
          return;
        }
      }

      // 🎯 设备检查
      final deviceState = ref.read(deviceProvider);
      final selectedDeviceId = deviceState.selectedDeviceId;
      final isLocalPlayback = (selectedDeviceId == 'local_device');

      if (!isLocalPlayback && deviceState.devices.isEmpty) {
        if (mounted) {
          AppSnackBar.showWarning(context, '未找到可用设备，请先在控制页检查设备连接');
        }
        return;
      }

      if (selectedDeviceId == null) {
        if (mounted) {
          final shouldSelectDevice = await _showDeviceSelectionDialog(
            deviceState.devices,
          );
          if (!shouldSelectDevice) return;
        }
        final newSelectedDeviceId = ref.read(deviceProvider).selectedDeviceId;
        if (newSelectedDeviceId == null) return;
      }

      // 🎯 创建 PlaylistItem 并通过统一方法播放
      final playlistItem = PlaylistItem.fromOnlineMusic(
        title: item.title,
        artist: item.author,
        album: item.album,
        duration: item.duration ?? 0,
        platform: item.platform,
        songId: item.songId,
        coverUrl: item.picture,
      );

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          '🎵 正在播放: ${item.title}',
          duration: const Duration(seconds: 3),
        );
      }

      print('[XMC] 🎵 [Play] 使用 playOnlineItem 统一播放: ${item.title}');
      await ref.read(playbackProvider.notifier).playOnlineItem(playlistItem);
      print('[XMC] ✅ [Play] 播放请求已完成');

      // 🎯 刷新播放状态
      try {
        await Future.delayed(const Duration(seconds: 2));
        await ref.read(playbackProvider.notifier).refreshStatus(silent: true);
        print('[XMC] ✅ [Play] 播放状态刷新完成');
      } catch (e) {
        print('[XMC] ⚠️ [Play] 播放状态刷新失败: $e');
      }
    } catch (e) {
      print('[XMC] ❌ [Play] 播放失败: $e');
      if (mounted) {
        AppSnackBar.showError(
          context,
          '❌ 播放失败：$e',
          duration: const Duration(seconds: 5),
        );
      }
    }
  }

  // 🎯 新增：显示设备选择对话框
  Future<bool> _showDeviceSelectionDialog(List<Device> devices) async {
    if (devices.isEmpty) return false;

    final selectedDeviceId = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '选择播放设备',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  devices.map((device) {
                    final isOnline = device.isOnline ?? false;
                    return ListTile(
                      leading: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        device.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        isOnline ? '在线' : '离线',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(device.id),
                    );
                  }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
    );

    if (selectedDeviceId != null) {
      ref.read(deviceProvider.notifier).selectDevice(selectedDeviceId);
      return true;
    }

    return false;
  }
}

/// 📋 歌单选择对话框
class _PlaylistSelectionDialog extends StatelessWidget {
  final List<String> playlists;

  const _PlaylistSelectionDialog({required this.playlists});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '选择歌单',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return ListTile(
              leading: Icon(
                Icons.queue_music_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                playlist,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.of(context).pop(playlist),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }
}
