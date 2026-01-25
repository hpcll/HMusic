import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import '../../data/models/music.dart';
import '../../data/adapters/music_list_adapter.dart';
import '../../data/services/music_api_service.dart';
import '../../data/services/album_cover_service.dart';
import '../../data/services/native_music_search_service.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';

class MusicLibraryState {
  final List<Music> musicList;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final List<Music> filteredMusicList;
  final bool isSelectionMode;
  final Set<String> selectedMusicNames;

  const MusicLibraryState({
    this.musicList = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.filteredMusicList = const [],
    this.isSelectionMode = false,
    this.selectedMusicNames = const {},
  });

  MusicLibraryState copyWith({
    List<Music>? musicList,
    bool? isLoading,
    String? error,
    String? searchQuery,
    List<Music>? filteredMusicList,
    bool? isSelectionMode,
    Set<String>? selectedMusicNames,
  }) {
    return MusicLibraryState(
      musicList: musicList ?? this.musicList,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      filteredMusicList: filteredMusicList ?? this.filteredMusicList,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedMusicNames: selectedMusicNames ?? this.selectedMusicNames,
    );
  }
}

class MusicLibraryNotifier extends StateNotifier<MusicLibraryState> {
  final Ref ref;
  AlbumCoverService? _albumCoverService; // 封面图服务
  Set<String> _fetchedCovers = {}; // 🔧 记录已获取封面的歌曲，避免重复获取

  MusicLibraryNotifier(this.ref) : super(const MusicLibraryState()) {
    debugPrint('MusicLibraryProvider: 初始化完成');

    // 监听认证状态变化，在用户登录后自动加载音乐库
    ref.listen<AuthState>(authProvider, (previous, next) {
      debugPrint('MusicLibraryProvider: 认证状态变化 - previous: ${previous.runtimeType}, next: ${next.runtimeType}');

      if (next is AuthAuthenticated && previous is! AuthAuthenticated) {
        debugPrint('MusicLibraryProvider: 用户已认证，自动加载音乐库');
        // 延迟一点时间确保认证完全完成
        Future.delayed(const Duration(milliseconds: 800), () {
          debugPrint('MusicLibraryProvider: 延迟后开始刷新音乐库');
          refreshLibrary();
        });
      }
      if (next is AuthInitial) {
        debugPrint('MusicLibraryProvider: 用户登出，清空音乐库状态');
        state = const MusicLibraryState();
      }
    });
  }

  Future<void> _loadMusicLibrary() async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('MusicLibrary: API服务未初始化');
      return;
    }

    try {
      debugPrint('MusicLibrary: 开始加载音乐库');
      state = state.copyWith(isLoading: true);

      final response = await apiService.getMusicList();
      debugPrint('MusicLibrary: API响应: $response');

      final musicList = MusicListAdapter.parse(response);
      debugPrint('MusicLibrary: 解析后的音乐列表数量: ${musicList.length}');

      if (musicList.isNotEmpty) {
        debugPrint('MusicLibrary: 前5首歌曲: ${musicList.take(5).map((m) => m.name).toList()}');
      }

      // 🔧 保留已获取的封面图信息
      // 创建旧音乐名称到封面图的映射
      final oldCoverMap = <String, String>{};
      for (final oldMusic in state.musicList) {
        if (oldMusic.picture != null && oldMusic.picture!.isNotEmpty) {
          oldCoverMap[oldMusic.name] = oldMusic.picture!;
        }
      }

      // 将旧的封面图信息应用到新的音乐列表
      final musicListWithCovers = musicList.map((music) {
        final existingCover = oldCoverMap[music.name];
        if (existingCover != null) {
          return Music(
            name: music.name,
            title: music.title,
            artist: music.artist,
            album: music.album,
            duration: music.duration,
            picture: existingCover, // 🖼️ 恢复旧的封面图
          );
        }
        return music;
      }).toList();

      state = state.copyWith(
        musicList: musicListWithCovers,
        filteredMusicList: musicListWithCovers,
        isLoading: false,
        error: null,
      );

      debugPrint('MusicLibrary: 数据加载完成，状态已更新，已恢复 ${oldCoverMap.length} 个封面图');

      // 🖼️ 异步获取所有歌曲的封面图(不阻塞UI)
      // 🔧 只在首次加载或有新歌曲时才获取封面
      if (musicListWithCovers.isNotEmpty) {
        // 找出未获取封面的歌曲
        final needsFetchList = musicListWithCovers.where((music) {
          return !_fetchedCovers.contains(music.name) &&
              (music.picture == null || music.picture!.isEmpty);
        }).toList();

        if (needsFetchList.isNotEmpty) {
          debugPrint('🖼️ [MusicLibrary] 发现 ${needsFetchList.length} 首歌曲需要获取封面');
          _fetchAlbumCoversAsync(needsFetchList, apiService);
        } else {
          debugPrint('🖼️ [MusicLibrary] 所有歌曲封面已缓存，跳过获取');
        }
      }
    } catch (e) {
      debugPrint('MusicLibrary: 获取音乐列表失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void filterMusic(String query) {
    if (query.trim().isEmpty) {
      state = state.copyWith(
        searchQuery: '',
        filteredMusicList: state.musicList,
      );
      return;
    }

    final filteredList =
        state.musicList.where((music) {
          final searchLower = query.toLowerCase();
          return (music.title?.toLowerCase().contains(searchLower) ?? false) ||
              (music.name.toLowerCase().contains(searchLower)) ||
              (music.artist?.toLowerCase().contains(searchLower) ?? false) ||
              (music.album?.toLowerCase().contains(searchLower) ?? false);
        }).toList();

    state = state.copyWith(searchQuery: query, filteredMusicList: filteredList);
  }

  Future<void> refreshLibrary() async {
    await _loadMusicLibrary();
  }

  Future<void> deleteMusic(String musicName) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      await apiService.deleteMusic(musicName);

      // 从本地列表中移除
      final updatedList =
          state.musicList.where((music) => music.name != musicName).toList();

      state = state.copyWith(
        musicList: updatedList,
        filteredMusicList:
            state.searchQuery.isEmpty
                ? updatedList
                : updatedList.where((music) {
                  final searchLower = state.searchQuery.toLowerCase();
                  return (music.title?.toLowerCase().contains(searchLower) ??
                          false) ||
                      (music.name.toLowerCase().contains(searchLower)) ||
                      (music.artist?.toLowerCase().contains(searchLower) ??
                          false) ||
                      (music.album?.toLowerCase().contains(searchLower) ??
                          false);
                }).toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // 触发单曲网络下载
  Future<void> downloadOneMusic(String musicName, {String? url}) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;
    try {
      state = state.copyWith(isLoading: true);
      final resp = await apiService.downloadOneMusic(
        musicName: musicName,
        url: url,
      );
      // 简单成功判断
      if (resp['ret'] == 'OK' || resp['success'] == true) {
        debugPrint('MusicLibrary: 下载请求成功，开始监测下载状态');
        
        // 使用智能下载状态监测
        await _waitForDownloadCompletion(musicName, apiService);
        
        debugPrint('MusicLibrary: 下载监测完成，刷新音乐库');
        await refreshLibrary();
      } else {
        state = state.copyWith(isLoading: false, error: resp.toString());
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // 异步下载 - 不阻塞UI，在后台监测完成状态
  Future<void> downloadOneMusicAsync(String musicName, {String? url}) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;
    
    try {
      debugPrint('MusicLibrary: 开始异步下载: $musicName');
      final resp = await apiService.downloadOneMusic(
        musicName: musicName,
        url: url,
      );
      
      if (resp['ret'] == 'OK' || resp['success'] == true) {
        debugPrint('MusicLibrary: 下载请求成功，启动后台监测');
        
        // 在后台监测下载完成状态，不阻塞当前操作
        _backgroundDownloadMonitor(musicName, apiService);
      } else {
        debugPrint('MusicLibrary: 下载请求失败: ${resp.toString()}');
      }
    } catch (e) {
      debugPrint('MusicLibrary: 异步下载异常: $e');
    }
  }

  // 后台监测下载完成状态
  void _backgroundDownloadMonitor(String musicName, dynamic apiService) {
    // 使用unawaited让这个监测在后台运行，不阻塞其他操作
    unawaited(_waitForDownloadCompletion(musicName, apiService).then((_) {
      debugPrint('MusicLibrary: 后台监测完成，刷新音乐库');
      refreshLibrary();
    }));
  }

  /// 智能监测下载完成状态
  Future<void> _waitForDownloadCompletion(String musicName, dynamic apiService) async {
    const maxAttempts = 30; // 最多等待3分钟 (6秒 * 30)
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      attempts++;
      
      try {
        // 方法1: 检查音乐库中是否已有该音乐
        final currentResponse = await apiService.getMusicList();
        final currentMusicList = MusicListAdapter.parse(currentResponse);
        
        final foundMusic = currentMusicList.any((music) =>
            music.name == musicName ||
            music.name.contains(musicName.split(' - ').first) ||
            (music.title != null && music.title!.contains(musicName.split(' - ').first)));
            
        if (foundMusic) {
          debugPrint('MusicLibrary: 下载完成检测成功 (第${attempts}次检查)');
          return;
        }
        
        // 方法2: 尝试获取下载日志检查状态 (如果API支持)
        try {
          final downloadLog = await apiService.getDownloadLog();
          if (downloadLog.contains(musicName) && 
              (downloadLog.contains('完成') || 
               downloadLog.contains('success') || 
               downloadLog.contains('下载成功'))) {
            debugPrint('MusicLibrary: 通过下载日志检测到完成 (第${attempts}次检查)');
            return;
          }
        } catch (e) {
          debugPrint('MusicLibrary: 下载日志检查失败: $e');
        }
        
        debugPrint('MusicLibrary: 第${attempts}次检查未完成，等待6秒后重试');
        await Future.delayed(const Duration(seconds: 6));
        
      } catch (e) {
        debugPrint('MusicLibrary: 下载状态检查异常: $e');
        await Future.delayed(const Duration(seconds: 6));
      }
    }
    
    debugPrint('MusicLibrary: 下载监测超时，可能下载仍在进行中');
  }

  // 上传多个音乐文件
  Future<void> uploadMusics(List<PlatformFile> files) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      // 转换为上传文件格式
      final uploadFiles =
          files
              .where((file) => file.path != null)
              .map(
                (file) => UploadFile(fieldName: 'files', filePath: file.path!),
              )
              .toList();

      if (uploadFiles.isEmpty) {
        throw Exception('没有有效的文件路径');
      }

      final resp = await apiService.uploadFiles(
        endpoint: '/uploadmusic',
        files: uploadFiles,
      );

      // 简单成功判断
      if (resp['ret'] == 'OK' || resp['success'] == true) {
        // 上传成功后刷新音乐库
        await Future.delayed(const Duration(seconds: 2));
        await refreshLibrary();
      } else {
        state = state.copyWith(isLoading: false, error: resp.toString());
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // 直接通过 SSH/SCP 上传（无服务端HTTP上传时的替代方案）
  Future<void> uploadViaScp({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remoteDir,
    required List<PlatformFile> files,
    String subDir = '',
  }) async {
    try {
      state = state.copyWith(isLoading: true);
      // 实现基于 dartssh2 的 SFTP 复制
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
      );
      final client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      final sftp = await client.sftp();

      Future<void> _ensureDir(String path) async {
        if (path == '/' || path.isEmpty) return;
        try {
          await sftp.stat(path);
        } catch (_) {
          final idx = path.lastIndexOf('/');
          if (idx > 0) await _ensureDir(path.substring(0, idx));
          await sftp.mkdir(path);
        }
      }

      final targetDir =
          subDir.isEmpty
              ? remoteDir
              : (remoteDir.endsWith('/')
                  ? '$remoteDir$subDir'
                  : '$remoteDir/$subDir');
      await _ensureDir(targetDir);

      for (final f in files) {
        if (f.path == null) continue;
        final localFile = File(f.path!);
        if (!await localFile.exists()) continue;
        final data = await localFile.readAsBytes();
        final remotePath =
            targetDir.endsWith('/')
                ? '${targetDir}${f.name}'
                : '$targetDir/${f.name}';
        final remote = await sftp.open(
          remotePath,
          mode:
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate |
              SftpFileOpenMode.write,
        );
        await remote.writeBytes(data);
        await remote.close();
      }

      sftp.close();
      client.close();

      await refreshLibrary();
      state = state.copyWith(isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 🖼️ 异步获取封面图（后台执行，不阻塞UI）
  void _fetchAlbumCoversAsync(List<Music> musicList, MusicApiService apiService) {
    // 使用 Future 在后台执行
    Future(() async {
      try {
        // 初始化 AlbumCoverService（如果未初始化）
        if (_albumCoverService == null) {
          final nativeSearch = ref.read(nativeMusicSearchServiceProvider);
          _albumCoverService = AlbumCoverService(
            musicApi: apiService,
            nativeSearch: nativeSearch,
          );
          debugPrint('🖼️ [MusicLibrary] AlbumCoverService 已初始化');
        }

        debugPrint('🖼️ [MusicLibrary] 开始批量获取封面图，共 ${musicList.length} 首歌曲');

        // 批量处理，每次处理 5 首歌曲，避免同时发起太多请求
        const batchSize = 5;
        for (int i = 0; i < musicList.length; i += batchSize) {
          final endIndex = (i + batchSize < musicList.length) ? i + batchSize : musicList.length;
          final batch = musicList.sublist(i, endIndex);

          // 并发获取当前批次的封面图
          await Future.wait(
            batch.map((music) => _fetchSingleAlbumCover(music, apiService)),
          );

          debugPrint('🖼️ [MusicLibrary] 已处理 $endIndex / ${musicList.length} 首歌曲');

          // 每批次之间延迟一下，避免请求过于密集
          if (endIndex < musicList.length) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }

        debugPrint('✅ [MusicLibrary] 所有封面图获取完成');
      } catch (e) {
        debugPrint('❌ [MusicLibrary] 批量获取封面图失败: $e');
      }
    });
  }

  /// 🖼️ 获取单首歌曲的封面图
  Future<void> _fetchSingleAlbumCover(Music music, MusicApiService apiService) async {
    try {
      // 如果歌曲已经有封面图，跳过
      if (music.picture != null && music.picture!.isNotEmpty) {
        debugPrint('🖼️ [MusicLibrary] 跳过已有封面的歌曲: ${music.name}');
        _fetchedCovers.add(music.name); // 🔧 标记为已获取
        return;
      }

      debugPrint('🖼️ [MusicLibrary] 获取封面图: ${music.name}');

      // 调用 AlbumCoverService 获取封面图
      final coverUrl = await _albumCoverService!.getOrFetchAlbumCover(
        musicName: music.name,
        loginBaseUrl: apiService.baseUrl,
        autoScrape: true,
      );

      if (coverUrl != null && coverUrl.isNotEmpty) {
        debugPrint('✅ [MusicLibrary] 封面图获取成功: ${music.name}');

        // 🔧 标记为已获取（成功）
        _fetchedCovers.add(music.name);

        // 更新 Music 对象的 picture 字段
        final updatedMusic = Music(
          name: music.name,
          title: music.title,
          artist: music.artist,
          album: music.album,
          duration: music.duration,
          picture: coverUrl,
        );

        // 更新状态中的音乐列表
        final updatedMusicList = state.musicList.map((m) {
          return m.name == music.name ? updatedMusic : m;
        }).toList();

        final updatedFilteredList = state.filteredMusicList.map((m) {
          return m.name == music.name ? updatedMusic : m;
        }).toList();

        // 刷新 UI
        state = state.copyWith(
          musicList: updatedMusicList,
          filteredMusicList: updatedFilteredList,
        );
      } else {
        debugPrint('⚠️ [MusicLibrary] 未找到封面图: ${music.name}');
        // 🔧 标记为已尝试获取（失败），避免重复尝试
        _fetchedCovers.add(music.name);
      }
    } catch (e) {
      debugPrint('❌ [MusicLibrary] 获取封面图失败: ${music.name}, 错误: $e');
      // 🔧 标记为已尝试获取（失败），避免重复尝试
      _fetchedCovers.add(music.name);
      // 静默失败，不影响其他歌曲
    }
  }

  // 批量删除相关方法
  void toggleSelectionMode() {
    state = state.copyWith(
      isSelectionMode: !state.isSelectionMode,
      selectedMusicNames: {},
    );
  }

  void toggleMusicSelection(String musicName) {
    final selected = Set<String>.from(state.selectedMusicNames);
    if (selected.contains(musicName)) {
      selected.remove(musicName);
    } else {
      selected.add(musicName);
    }
    state = state.copyWith(selectedMusicNames: selected);
  }

  void selectAllMusic() {
    final allNames = state.filteredMusicList.map((music) => music.name).toSet();
    state = state.copyWith(selectedMusicNames: allNames);
  }

  void clearSelection() {
    state = state.copyWith(selectedMusicNames: {});
  }

  Future<void> deleteSelectedMusic() async {
    if (state.selectedMusicNames.isEmpty) return;

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      // 批量删除音乐文件
      for (final musicName in state.selectedMusicNames) {
        await apiService.deleteMusic(musicName);
      }

      // 从本地列表中移除被删除的音乐
      final updatedList = state.musicList
          .where((music) => !state.selectedMusicNames.contains(music.name))
          .toList();

      final updatedFilteredList = state.filteredMusicList
          .where((music) => !state.selectedMusicNames.contains(music.name))
          .toList();

      state = state.copyWith(
        musicList: updatedList,
        filteredMusicList: updatedFilteredList,
        isLoading: false,
        isSelectionMode: false,
        selectedMusicNames: {},
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final musicLibraryProvider =
    StateNotifierProvider<MusicLibraryNotifier, MusicLibraryState>((ref) {
      return MusicLibraryNotifier(ref);
    });
