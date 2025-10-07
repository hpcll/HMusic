import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
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
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/music_library_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../providers/device_provider.dart';
import '../providers/dio_provider.dart';
import '../../data/models/device.dart';
import '../providers/playback_provider.dart';

class MusicSearchPage extends ConsumerStatefulWidget {
  const MusicSearchPage({super.key});

  @override
  ConsumerState<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends ConsumerState<MusicSearchPage> {
  // legacy dialog removed

  // legacy play removed
  late final WebViewController _wvController;
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
    return Center(
      key: const ValueKey('search_error'),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              '哦豁，出错了',
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
            ),
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
              itemBuilder:
                  (context) => const [
                    PopupMenuItem(value: 'play', child: Text('解析直链并播放')),
                    PopupMenuItem(value: 'server', child: Text('下载到服务器')),
                    PopupMenuItem(value: 'local', child: Text('下载到本地')),
                  ],
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
    // 获取用户设置的默认下载音质
    final settings = ref.read(sourceSettingsProvider);
    final quality = settings.defaultDownloadQuality;

    try {
      var url = item.url;
      if (url.isEmpty) {
        // 使用音质降级逻辑解析
        url = await _resolveWithQualityFallback(item, quality) ?? '';
      }

      if (url.isEmpty) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('❌ 无法解析直链，下载失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 使用"歌曲名 - 作者名"作为服务端下载名称
      final safeTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeAuthor = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final serverName =
          safeAuthor.isNotEmpty ? '$safeTitle - $safeAuthor' : safeTitle;

      await ref
          .read(musicLibraryProvider.notifier)
          .downloadOneMusic(serverName, url: url);
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('已提交下载任务：${item.title}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('下载失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadToLocal(OnlineMusicResult item) async {
    // 获取用户设置的默认下载音质
    final settings = ref.read(sourceSettingsProvider);
    final quality = settings.defaultDownloadQuality;

    try {
      var url = item.url;
      if (url.isEmpty) {
        // 使用音质降级逻辑解析
        url = await _resolveWithQualityFallback(item, quality) ?? '';
      }

      if (url.isEmpty) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('❌ 无法解析直链，无法下载'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 确定下载目录
      Directory dir;
      if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        // Android 11+ 需要 MANAGE_EXTERNAL_STORAGE 权限写入公共目录
        bool hasPermission = await Permission.storage.isGranted;

        // Android 11+ (API 30+) 检查 MANAGE_EXTERNAL_STORAGE
        if (!hasPermission && await Permission.manageExternalStorage.isDenied) {
          hasPermission = await Permission.manageExternalStorage.request().isGranted;
        }

        // 回退到普通存储权限
        if (!hasPermission) {
          hasPermission = await Permission.storage.request().isGranted;
        }

        if (!hasPermission) {
          if (mounted) {
            AppSnackBar.show(
              context,
              const SnackBar(
                content: Text('❌ 需要存储权限才能下载到本地'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // 直接使用公共 Download 目录
        dir = Directory('/storage/emulated/0/Download/HMusic');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      final titlePart = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final authorPart = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName =
          authorPart.isNotEmpty ? '$titlePart - $authorPart' : titlePart;
      final ext = p.extension(Uri.parse(url).path);
      final filePath = p.join(
        dir.path,
        '$safeName${ext.isEmpty ? '.m4a' : ext}',
      );

      final client = dio.Dio();
      await client.download(
        url,
        filePath,
        options: dio.Options(
          responseType: dio.ResponseType.bytes,
          followRedirects: true,
        ),
      );

      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('已保存到本地: ${p.basename(filePath)}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: '打开',
              textColor: Colors.white,
              onPressed: () => OpenFilex.open(filePath),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('本地下载失败：$e'), backgroundColor: Colors.red),
        );
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
      case 'lossless':
        return ['hires', 'flac', '320k', '128k'];
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
            musicInfo: {'songmid': id, 'hash': id},
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
                var payload = { action: 'musicUrl', source: mapPlat('$platform'), info: { type: '$quality', musicInfo: { songmid: '$id', hash: '$id' } } };
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

  Future<void> _playViaResolver(OnlineMusicResult item) async {
    final platform = (item.platform ?? 'qq');
    final id = item.songId ?? '';

    if (id.isEmpty) {
      if (mounted) {
        AppSnackBar.show(
          context,
          const SnackBar(
            content: Text('❌ 缺少歌曲标识，无法播放'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // 🎯 检查用户音源设置和JS脚本状态
      final settings = ref.read(sourceSettingsProvider);
      if (settings.primarySource == 'js_external') {
        final scripts = ref.read(jsScriptManagerProvider);
        final scriptManager = ref.read(jsScriptManagerProvider.notifier);
        final selectedScript = scriptManager.selectedScript;

        if (scripts.isEmpty) {
          // 用户选择了JS音源但没有导入任何脚本
          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: const Text('❌ 未导入JS脚本\n请先在设置中导入JS脚本才能播放音乐'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: '去导入',
                  textColor: Colors.white,
                  onPressed: () {
                    // 导航到音源设置页面
                    context.push('/settings/source');
                  },
                ),
              ),
            );
          }
          return;
        } else if (selectedScript == null) {
          // 有脚本但没有选中任何脚本
          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: Text('❌ 未选择JS脚本\n已导入${scripts.length}个脚本，请选择一个使用'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: '去选择',
                  textColor: Colors.white,
                  onPressed: () {
                    context.push('/settings/source');
                  },
                ),
              ),
            );
          }
          return;
        }
      }

      String? playUrl;
      // 保留设置读取逻辑如后续需要；当前未使用，移除避免未使用告警

      // 🎯 检查歌曲来源，使用对应的播放源
      final sourceApi = item.extra?['sourceApi'] as String?;
      print('[XMC] 🎵 [Play] 开始播放，来源: $sourceApi, 平台: $platform, ID: $id');

      if (sourceApi == 'js_builtin' || sourceApi == null) {
        // 🎯 JS源：优先用 JS 解析（QuickJS -> WebView），失败再回退静态API链接
        print('[XMC] 🎵 [Play] JS源播放：解析直链或构造API链接');

        try {
          if (id.isEmpty) throw Exception('缺少歌曲ID');

          // 平台映射到脚本音源
          String mapped;
          switch (platform.toLowerCase()) {
            case 'auto':
            case 'qq':
            case 'tencent':
              mapped = 'tx';
              break;
            case 'wangyi':
            case 'netease':
            case '163':
              mapped = 'wy';
              break;
            case 'kugou':
              mapped = 'kg';
              break;
            case 'kuwo':
              mapped = 'kw';
              break;
            case 'migu':
              mapped = 'mg';
              break;
            default:
              mapped = 'tx';
              print('[XMC] ⚠️ [Play] 未知平台 $platform，使用默认平台 tx');
          }

          // 设备校验/选择
          final deviceState = ref.read(deviceProvider);
          if (deviceState.devices.isEmpty) {
            if (mounted) {
              AppSnackBar.show(
                context,
                const SnackBar(
                  content: Text('未找到可用设备，请先在控制页检查设备连接'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
          if (deviceState.selectedDeviceId == null) {
            if (mounted) {
              final shouldSelectDevice = await _showDeviceSelectionDialog(
                deviceState.devices,
              );
              if (!shouldSelectDevice) return;
            }
          }
          final selectedDeviceId = deviceState.selectedDeviceId;
          if (selectedDeviceId == null) return;

          final apiService = ref.read(apiServiceProvider);
          if (apiService == null) throw Exception('API服务未初始化，请先登录');

          // 解析直链
          String? resolvedUrl;
          final jsProxy = ref.read(jsProxyProvider.notifier);
          final jsProxyState = ref.read(jsProxyProvider);

          // 🎯 严格检查：不仅要初始化，还要有脚本和音源
          final bool jsReady =
              jsProxyState.isInitialized &&
              jsProxyState.currentScript != null &&
              jsProxyState.supportedSources.isNotEmpty;

          print('[XMC] 🔍 [Play] JS状态检查:');
          print('  - isInitialized: ${jsProxyState.isInitialized}');
          print('  - currentScript: ${jsProxyState.currentScript}');
          print(
            '  - supportedSources: ${jsProxyState.supportedSources.length}',
          );
          print('  - jsReady: $jsReady');

          if (jsReady) {
            print('[XMC] ✅ [Play] JS已就绪，开始解析音乐链接');
            resolvedUrl = await jsProxy.getMusicUrl(
              source: mapped,
              songId: id,
              quality: '320k',
              musicInfo: {'songmid': id, 'hash': id},
            );
            print(
              '[XMC] 🎵 [Play] JS解析结果: ${resolvedUrl?.isNotEmpty == true ? "成功" : "失败"}',
            );
          } else {
            print('[XMC] ⚠️ [Play] JS未就绪，等待自动加载...');

            // 🎯 等待 JS 自动加载（最多3秒）
            int waitCount = 0;
            const maxWait = 30; // 30 * 100ms = 3秒
            while (waitCount < maxWait) {
              await Future.delayed(const Duration(milliseconds: 100));
              waitCount++;

              final currentState = ref.read(jsProxyProvider);
              final nowReady =
                  currentState.isInitialized &&
                  currentState.currentScript != null &&
                  currentState.supportedSources.isNotEmpty;

              if (nowReady) {
                print('[XMC] ✅ [Play] JS加载完成，等待了 ${waitCount * 100}ms');
                resolvedUrl = await jsProxy.getMusicUrl(
                  source: mapped,
                  songId: id,
                  quality: '320k',
                  musicInfo: {'songmid': id, 'hash': id},
                );
                print(
                  '[XMC] 🎵 [Play] JS解析结果: ${resolvedUrl?.isNotEmpty == true ? "成功" : "失败"}',
                );
                break;
              }
            }

            if (waitCount >= maxWait) {
              print('[XMC] ❌ [Play] JS加载超时（3秒），继续尝试其他方法');
            }
          }
          if (resolvedUrl == null || resolvedUrl.isEmpty) {
            final webSvc = await ref.read(
              webviewJsSourceServiceProvider.future,
            );
            if (webSvc != null) {
              resolvedUrl = await webSvc.resolveMusicUrl(
                platform: mapped,
                songId: id,
                quality: '320k',
              );
            }
          }

          // 调用播放
          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: Text('🎵 正在播放: ${item.title}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }

          if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
            print('[XMC] 🎵 [Play] 使用解析直链播放');

            // 🎯 通过 PlaybackProvider 播放，自动适配本地/远程模式
            await ref
                .read(playbackProvider.notifier)
                .playMusic(
                  deviceId: selectedDeviceId,
                  musicName: '${item.title} - ${item.author}',
                  url: resolvedUrl,
                  albumCoverUrl: item.picture, // 🖼️ 传递搜索结果的封面图
                );

            print('[XMC] ✅ [Play] 播放请求已发送到 PlaybackProvider');
          } else {
            // 🚫 JS 音源解析失败：不再回退到统一API
            print('[XMC] ❌ [Play] JS解析失败，无法获取播放链接');
            if (mounted) {
              AppSnackBar.show(
                context,
                SnackBar(
                  content: Text('播放失败: JS脚本无法解析该歌曲\n请尝试其他歌曲或重新加载脚本'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return; // 直接返回，不继续执行
          }

          print('[XMC] ✅ [Play] JS源播放流程完成');

          try {
            print('[XMC] 🔄 [Play] 刷新播放状态...');
            await Future.delayed(const Duration(seconds: 2));
            await ref
                .read(playbackProvider.notifier)
                .refreshStatus(silent: true);
            print('[XMC] ✅ [Play] 播放状态刷新完成');
            // 🖼️ 封面图已在 playMusic 中统一处理，不需要单独更新
          } catch (e) {
            print('[XMC] ⚠️ [Play] 播放状态刷新失败: $e');
          }

          return;
        } catch (e) {
          print('[XMC] ❌ [Play] JS源播放失败: $e');
          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: Text('JS源播放失败: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // 🎯 统一API源和其他源：保持原有的解析播放逻辑
      print('[XMC] 🎵 [Play] 非JS源播放：使用解析播放逻辑');

      if (sourceApi == 'unified') {
        // 🎯 统一API源：使用统一API解析播放链接
        print('[XMC] 🎵 [Play] 统一API源：使用统一API解析播放链接...');

        try {
          final unifiedService = ref.read(unifiedApiServiceProvider);
          playUrl = await unifiedService.getMusicUrl(
            songId: id,
            platform: platform,
            quality: '320k',
          );

          if (playUrl != null && playUrl.isNotEmpty) {
            print('[XMC] ✅ [Play] 统一API解析成功: $playUrl');
          } else {
            print('[XMC] ❌ [Play] 统一API解析失败，尝试备用方案');
            // 🎯 备用方案：尝试使用JS源解析
            try {
              final webSvc = await ref.read(
                webviewJsSourceServiceProvider.future,
              );
              if (webSvc != null) {
                print('[XMC] 🔄 [Play] 尝试JS源备用解析...');
                playUrl = await webSvc.resolveMusicUrl(
                  platform: platform,
                  songId: id,
                  quality: '320k',
                );
                if (playUrl != null && playUrl.isNotEmpty) {
                  print('[XMC] ✅ [Play] JS源备用解析成功: $playUrl');
                }
              }
            } catch (e) {
              print('[XMC] ⚠️ [Play] JS源备用解析失败: $e');
            }
          }
        } catch (e) {
          print('[XMC] ❌ [Play] 统一API解析异常: $e');
          throw Exception('统一API解析失败: $e');
        }
      } else {
        // 🎯 其他源：使用JS源解析
        print('[XMC] 🎵 [Play] 其他源：使用JS源解析播放链接...');

        try {
          final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
          final jsSvc = await ref.read(jsSourceServiceProvider.future);
          final jsProxy = ref.read(jsProxyProvider.notifier);
          final jsProxyState = ref.read(jsProxyProvider);

          if (webSvc == null && jsSvc == null) {
            throw Exception('JS解析服务未就绪');
          }

          // 优先使用 QuickJS 代理解析
          if (jsProxyState.isInitialized &&
              jsProxyState.currentScript != null) {
            final mapped =
                (platform == 'qq')
                    ? 'tx'
                    : (platform == 'netease' || platform == '163')
                    ? 'wy'
                    : platform;
            playUrl = await jsProxy.getMusicUrl(
              source: mapped,
              songId: id,
              quality: '320k',
              musicInfo: {'songmid': id, 'hash': id},
            );

            if (playUrl != null && playUrl.isNotEmpty) {
              print('[XMC] ✅ [Play] QuickJS解析成功: $playUrl');
            }
          }

          // 次选 WebView JS解析（仅在QuickJS失败时尝试）
          if ((playUrl == null || playUrl.isEmpty) && webSvc != null) {
            print('[XMC] 🔄 [Play] QuickJS解析失败，尝试WebView解析...');
            playUrl = await webSvc.resolveMusicUrl(
              platform: platform,
              songId: id,
              quality: '320k',
            );

            if (playUrl != null && playUrl.isNotEmpty) {
              print('[XMC] ✅ [Play] WebView解析成功: $playUrl');
            }
          }

          // 回退到内置JS解析
          if ((playUrl == null || playUrl.isEmpty) &&
              jsSvc != null &&
              jsSvc.isReady) {
            print('[XMC] 🔄 [Play] 回退到内置JS解析...');
            final js = """
              (function(){
                try{
                  if (!lx || !lx.EVENT_NAMES) return '';
                  // 平台映射
                  function mapPlat(p){ p=(p||'').toLowerCase(); if(p==='qq'||p==='tencent') return 'tx'; if(p==='netease'||p==='163') return 'wy'; if(p==='kuwo') return 'kw'; if(p==='kugou') return 'kg'; if(p==='migu') return 'mg'; return p; }
                  var payload = { action: 'musicUrl', source: mapPlat('$platform'), info: { type: '320k', musicInfo: { songmid: '$id', hash: '$id' } } };
                  var res = lx.emit(lx.EVENT_NAMES.request, payload);
                  if (res && typeof res.then === 'function') return '';
                  if (typeof res === 'string') return res; if (res && res.url) return res.url; return '';
                }catch(e){ return '' }
              })()
            """;
            playUrl = jsSvc.evaluateToString(js);
          }

          if (playUrl != null && playUrl.isNotEmpty) {
            print('[XMC] ✅ [Play] JS源解析成功: $playUrl');
          } else {
            throw Exception('JS源无法解析播放链接');
          }
        } catch (e) {
          print('[XMC] ❌ [Play] JS源解析异常: $e');
          throw Exception('JS源解析失败: $e');
        }
      }

      // 🎯 检查解析结果
      if (playUrl == null || playUrl.isEmpty) {
        throw Exception('所有播放源都无法解析播放链接，请检查网络连接或尝试其他歌曲');
      }

      // 🎯 检查是否有可用的播放设备
      final deviceState = ref.read(deviceProvider);
      if (deviceState.devices.isEmpty) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('未找到可用设备，请先在控制页检查设备连接'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 🎯 检查是否选择了设备
      if (deviceState.selectedDeviceId == null) {
        if (mounted) {
          final shouldSelectDevice = await _showDeviceSelectionDialog(
            deviceState.devices,
          );
          if (!shouldSelectDevice) return;
        }
      }

      final selectedDeviceId = deviceState.selectedDeviceId;
      if (selectedDeviceId == null) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('请先选择播放设备'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final apiService = ref.read(apiServiceProvider);
      if (apiService == null) {
        throw Exception('API服务未初始化，请先登录');
      }

      // 🎯 显示播放中提示
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('🎵 正在播放: ${item.title}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      print(
        '[XMC] 🎵 [Play] 开始播放解析后的链接: ${playUrl.substring(0, playUrl.length > 100 ? 100 : playUrl.length)}...',
      );

      // 🎯 通过 PlaybackProvider 播放，自动适配本地/远程模式
      await ref
          .read(playbackProvider.notifier)
          .playMusic(
            deviceId: selectedDeviceId,
            musicName: '${item.title} - ${item.author}',
            url: playUrl,
            albumCoverUrl: item.picture, // 🖼️ 传递搜索结果的封面图
          );

      print('[XMC] ✅ [Play] 播放请求已发送到 PlaybackProvider');

      // 🎯 刷新播放状态
      try {
        print('[XMC] 🔄 [Play] 刷新播放状态...');
        await Future.delayed(const Duration(seconds: 2));
        await ref.read(playbackProvider.notifier).refreshStatus(silent: true);
        print('[XMC] ✅ [Play] 播放状态刷新完成');
      } catch (e) {
        print('[XMC] ⚠️ [Play] 播放状态刷新失败: $e');
      }
    } catch (e) {
      print('[XMC] ❌ [Play] 播放失败: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('❌ 播放失败：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
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

  // 🎯 新增：显示下载确认对话框
}
