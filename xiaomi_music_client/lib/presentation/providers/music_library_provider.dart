import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import '../../data/models/music.dart';
import '../../data/adapters/music_list_adapter.dart';
import '../../data/services/music_api_service.dart';
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

  MusicLibraryNotifier(this.ref) : super(const MusicLibraryState()) {
    // 监听认证状态变化，在用户登录后自动加载音乐库
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is AuthAuthenticated && previous is! AuthAuthenticated) {
        debugPrint('MusicLibraryProvider: 用户已认证，自动加载音乐库');
        // 延迟一点时间确保认证完全完成
        Future.delayed(const Duration(milliseconds: 800), () {
          refreshLibrary();
        });
      }
      if (next is AuthInitial) {
        state = const MusicLibraryState();
      }
    });
  }

  Future<void> _loadMusicLibrary() async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) return;

    try {
      state = state.copyWith(isLoading: true);

      final response = await apiService.getMusicList();
      final musicList = MusicListAdapter.parse(response);

      print('解析后的音乐列表数量: ${musicList.length}');

      state = state.copyWith(
        musicList: musicList,
        filteredMusicList: musicList,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      print('获取音乐列表失败: $e');
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
        // 下载一般是异步，稍后刷新库
        await Future.delayed(const Duration(seconds: 1));
        await refreshLibrary();
      } else {
        state = state.copyWith(isLoading: false, error: resp.toString());
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
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
