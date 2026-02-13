import '../../core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../adapters/music_list_json_adapter.dart';
import '../models/online_music_result.dart';

class UploadFile {
  final String fieldName;
  final String filePath;

  const UploadFile({required this.fieldName, required this.filePath});
}

class MusicApiService {
  final DioClient _client;
  // null: 未知（可尝试）/ true: 支持 / false: 不支持（本次运行不再尝试）
  bool? _supportsDownloadOneMusicDirname;
  bool? _supportsDownloadOneMusicPlaylistName;

  MusicApiService(this._client);

  /// 获取登录时的服务器地址（用于URL替换）
  String get baseUrl => _client.baseUrl;

  Future<Map<String, dynamic>> getVersion() async {
    final response = await _client.get('/getversion');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMusicList() async {
    final response = await _client.get('/musiclist');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCurrentPlaying({String? did}) async {
    final response = await _client.get(
      '/playingmusic',
      queryParameters: did != null ? {'did': did} : null,
    );
    return response.data as Map<String, dynamic>;
  }

  // 获取当前播放列表
  // 🔧 修复：返回类型改为 dynamic，因为服务端可能返回字符串（播放列表名）或 Map
  Future<dynamic> getCurrentPlaylist({String? did}) async {
    final response = await _client.get(
      '/curplaylist',
      queryParameters: did != null ? {'did': did} : null,
    );
    return response.data;
  }

  Future<Map<String, dynamic>> getVolume({String? did}) async {
    final response = await _client.get(
      '/getvolume',
      queryParameters: did != null ? {'did': did} : null,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> setVolume({required String did, required int volume}) async {
    await _client.post('/setvolume', data: {'did': did, 'volume': volume});
  }

  // 可选：若服务端支持拖动进度
  Future<void> seek({required String did, required int seconds}) async {
    await _client.post('/seek', data: {'did': did, 'seconds': seconds});
  }

  Future<void> playMusic({
    required String did,
    String? musicName,
    String? searchKey,
  }) async {
    await playMusicList(
      did: did,
      // 🔧 修复：使用 "全部" 作为默认列表，因为 "临时搜索列表" 通常是空的
      listName: "全部",
      musicName: musicName ?? '',
    );
  }

  Future<void> pauseMusic({required String did}) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': '暂停'});
  }

  Future<void> resumeMusic({required String did}) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': '播放歌曲'});
  }

  Future<void> shutdown({required String did}) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': '关机'});
  }

  Future<void> executeCommand({
    required String did,
    required String command,
  }) async {
    await _client.post('/cmd', data: {'did': did, 'cmd': command});
  }

  Future<Map<String, dynamic>> getCommandStatus() async {
    final response = await _client.get('/cmdstatus');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSettings({
    bool needDeviceList = false,
  }) async {
    final response = await _client.get(
      '/getsetting',
      queryParameters: {'need_device_list': needDeviceList},
    );
    return response.data as Map<String, dynamic>;
  }

  // 保存设置接口（完整配置）
  Future<dynamic> saveSetting(Map<String, dynamic> settings) async {
    final response = await _client.post('/savesetting', data: settings);
    return response.data; // 直接返回原始数据，可能是字符串或Map
  }

  // 修改部分设置接口（只更新指定字段）
  // 🎯 这个 API 专门用于修改部分设置，不需要发送完整配置
  Future<Map<String, dynamic>> modifySetting(
    Map<String, dynamic> settings,
  ) async {
    final response = await _client.post(
      '/api/system/modifiysetting',
      data: settings,
    );
    return response.data as Map<String, dynamic>;
  }

  // 播放音乐列表接口
  Future<dynamic> playMusicList({
    required String did,
    required String listName,
    required String musicName,
  }) async {
    final response = await _client.post(
      '/playmusiclist',
      data: {'did': did, 'listname': listName, 'musicname': musicName},
    );
    return response.data; // 直接返回原始数据，可能是字符串或Map
  }

  // 通过设置在线播放列表来播放音乐
  // 🎯 使用 /api/system/modifiysetting API 只更新 music_list_json 字段
  Future<void> playOnlineMusic({
    required String did,
    required String musicUrl,
    required String musicTitle,
    required String musicAuthor,
    Map<String, String>? headers,
  }) async {
    // 🎯 关键：如果 URL 需要代理，转换成代理 URL 格式
    // 格式：http://服务器地址/proxy?urlb64=base64编码的原始URL
    String finalUrl = musicUrl;
    if (_needsProxy(musicUrl)) {
      final baseUrl = _client.baseUrl;
      finalUrl = '$baseUrl/proxy?urlb64=${_encodeUrlToBase64(musicUrl)}';
      debugPrint('🔄 URL需要代理，已转换: $musicUrl -> $finalUrl');
    }

    // 使用新的适配器创建单首歌曲JSON
    final musicListJsonString = MusicListJsonAdapter.createSingleSongJson(
      title: musicTitle,
      artist: musicAuthor,
      url: finalUrl,
      headers: headers,
    );

    debugPrint('🔵 完整的音乐列表JSON: $musicListJsonString');

    // 🎯 使用 saveSetting API 完整保存配置
    // 重要：必须使用 saveSetting 而不是 modifySetting！
    // modifySetting 只会保存配置到文件，但不会触发 xiaomusic 重新加载播放列表
    // saveSetting 会触发 xiaomusic 重新加载 music_list_json 到内存中的"在线播放"列表
    final currentSettings = await getSettings();
    final updatedSettings = Map<String, dynamic>.from(currentSettings);
    updatedSettings['music_list_json'] = musicListJsonString;
    final saveResult = await saveSetting(updatedSettings);
    debugPrint('保存设置结果(saveSetting): $saveResult');

    // 播放音乐
    final playResult = await playMusicList(
      did: did,
      listName: "在线播放",
      musicName: "$musicTitle - $musicAuthor",
    );
    debugPrint('播放结果: $playResult');
  }

  /// 播放在线搜索结果（支持多种格式）
  ///
  /// 这是新的通用方法，支持：
  /// - OnlineMusicResult 对象
  /// - 原始搜索结果JSON
  /// - 多首歌曲的播放列表
  Future<void> playOnlineSearchResult({
    required String did,
    OnlineMusicResult? singleResult,
    List<OnlineMusicResult>? resultList,
    List<Map<String, dynamic>>? rawResults,
    String playlistName = "在线播放",
    Map<String, String>? defaultHeaders,
  }) async {
    String musicListJsonString;
    String targetSongName = "";

    if (singleResult != null) {
      // 播放单首歌曲
      musicListJsonString = MusicListJsonAdapter.convertToMusicListJson(
        results: [singleResult],
        playlistName: playlistName,
        defaultHeaders: defaultHeaders,
      );
      targetSongName = "${singleResult.title} - ${singleResult.author}";
    } else if (resultList != null && resultList.isNotEmpty) {
      // 播放结果列表，默认播放第一首
      musicListJsonString = MusicListJsonAdapter.convertToMusicListJson(
        results: resultList,
        playlistName: playlistName,
        defaultHeaders: defaultHeaders,
      );
      targetSongName = "${resultList.first.title} - ${resultList.first.author}";
    } else if (rawResults != null && rawResults.isNotEmpty) {
      // 播放原始JSON结果
      musicListJsonString = MusicListJsonAdapter.convertFromRawJson(
        rawResults: rawResults,
        playlistName: playlistName,
        defaultHeaders: defaultHeaders,
      );
      // 从原始数据中提取歌曲名
      final firstResult = rawResults.first;
      final title = firstResult['title'] ?? firstResult['name'] ?? '未知标题';
      final artist = firstResult['artist'] ?? firstResult['singer'] ?? '未知艺术家';
      targetSongName = "$title - $artist";
    } else {
      throw ArgumentError('必须提供 singleResult、resultList 或 rawResults 中的至少一个参数');
    }

    debugPrint('🔵 [PlayOnlineSearchResult] 完整的音乐列表JSON: $musicListJsonString');
    debugPrint('🔵 [PlayOnlineSearchResult] 目标歌曲: $targetSongName');

    // 验证生成的JSON格式
    if (!MusicListJsonAdapter.validateMusicListJson(musicListJsonString)) {
      throw FormatException('生成的music_list_json格式无效');
    }

    // 🎯 使用 saveSetting API 完整保存配置
    // 重要：必须使用 saveSetting 而不是 modifySetting！
    // modifySetting 只会保存配置到文件，但不会触发 xiaomusic 重新加载播放列表
    // saveSetting 会触发 xiaomusic 重新加载 music_list_json 到内存中的"在线播放"列表
    final currentSettings = await getSettings();
    final updatedSettings = Map<String, dynamic>.from(currentSettings);
    updatedSettings['music_list_json'] = musicListJsonString;
    final saveResult = await saveSetting(updatedSettings);
    debugPrint('🔵 [PlayOnlineSearchResult] 保存设置结果(saveSetting): $saveResult');

    // 播放音乐
    final playResult = await playMusicList(
      did: did,
      listName: playlistName,
      musicName: targetSongName,
    );
    debugPrint('🔵 [PlayOnlineSearchResult] 播放结果: $playResult');
  }

  Future<List<dynamic>> searchMusic(String name) async {
    final response = await _client.get(
      '/searchmusic',
      queryParameters: {'name': name},
    );
    return response.data as List<dynamic>;
  }

  Future<void> playUrl({required String did, required String url}) async {
    await _client.get('/playurl', queryParameters: {'did': did, 'url': url});
  }

  // 代理播放 - 用于需要代理的链接
  Future<void> playUrlWithProxy({
    required String did,
    required String url,
  }) async {
    // 构建完整的代理URL
    final baseUrl = _client.baseUrl;
    final proxyUrl = '$baseUrl/proxy?urlb64=${_encodeUrlToBase64(url)}';
    debugPrint('构建代理URL: $proxyUrl');
    await _client.get(
      '/playurl',
      queryParameters: {'did': did, 'url': proxyUrl},
    );
  }

  // 智能播放 - 自动判断是否需要代理
  Future<void> playUrlSmart({required String did, required String url}) async {
    if (_needsProxy(url)) {
      debugPrint('使用代理播放: $url');
      await playUrlWithProxy(did: did, url: url);
    } else {
      debugPrint('直接播放: $url');
      await playUrl(did: did, url: url);
    }
  }

  // 判断URL是否需要代理
  // 🎯 改进逻辑：除了本地服务器的 URL，其他外部 URL 都需要代理
  // 因为小爱音箱可能无法直接访问外部链接（防盗链、headers 等限制）
  bool _needsProxy(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // 获取本地服务器地址
    final baseUri = Uri.tryParse(_client.baseUrl);
    if (baseUri == null) return true; // 无法解析服务器地址时，默认需要代理

    // 如果 URL 已经是本地服务器的地址（包括已经是代理 URL），不需要再代理
    if (uri.host == baseUri.host) {
      return false;
    }

    // 如果是本地地址（localhost、127.0.0.1、192.168.x.x 等），可能是本地服务，不需要代理
    if (uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host.startsWith('192.168.') ||
        uri.host.startsWith('10.') ||
        uri.host.startsWith('172.')) {
      // 但如果是其他本地服务器，还是需要检查是否是已知的音乐域名
      // 这里保守起见，本地地址不代理
      return false;
    }

    // 🎯 所有外部 URL 都需要代理！
    // 包括 QQ音乐(wx.music.tc.qq.com, ws.stream.qqmusic.qq.com)、
    // 网易云、咪咕、酷我、酷狗等所有音乐平台
    debugPrint('🔄 检测到外部URL，需要代理: ${uri.host}');
    return true;
  }

  // Base64编码URL
  String _encodeUrlToBase64(String url) {
    return base64Encode(utf8.encode(url));
  }

  Future<void> playTts({required String did, required String text}) async {
    await _client.get('/playtts', queryParameters: {'did': did, 'text': text});
  }

  // 预留：本地音乐上传（待确认服务端路径/参数）
  Future<Map<String, dynamic>> uploadMusic({
    required List<({String fieldName, String filePath})> files,
    Map<String, dynamic>? extraFields,
    String endpoint = '/uploadmusic',
  }) async {
    final formData = FormData();
    for (final f in files) {
      formData.files.add(
        MapEntry(f.fieldName, await MultipartFile.fromFile(f.filePath)),
      );
    }
    if (extraFields != null) {
      formData.fields.addAll(
        extraFields.entries.map((e) => MapEntry(e.key, e.value.toString())),
      );
    }
    final resp = await _client.post(endpoint, data: formData);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // 预留：网络音乐下载（待确认服务端路径/参数）
  Future<Map<String, dynamic>> downloadMusicByUrl({
    required String url,
    Map<String, dynamic>? extraFields,
    String endpoint = '/downloadjson',
  }) async {
    final body = {'url': url, ...?extraFields};
    final resp = await _client.post(endpoint, data: body);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // Download raw log/file text from /downloadlog
  Future<String> getDownloadLog() async {
    final resp = await _client.getPlain('/downloadlog');
    return resp.data ?? '';
  }

  // 播放列表相关方法
  Future<dynamic> getPlaylistNames() async {
    // 兼容不同服务端实现：可能返回 List 或 Map
    final response = await _client.get('/playlistnames');
    return response.data;
  }

  Future<Map<String, dynamic>> getPlaylistMusics(String playlistName) async {
    final response = await _client.get(
      '/playlistmusics',
      queryParameters: {'name': playlistName},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> createPlaylist(String name) async {
    await _client.post('/playlistadd', data: {'name': name});
  }

  Future<void> deletePlaylist(String name) async {
    await _client.post('/playlistdel', data: {'name': name});
  }

  Future<void> renamePlaylist({
    required String oldName,
    required String newName,
  }) async {
    await _client.post(
      '/playlistupdatename',
      data: {'oldname': oldName, 'newname': newName},
    );
  }

  Future<void> addMusicToPlaylist({
    required String playlistName,
    required List<String> musicList,
  }) async {
    await _client.post(
      '/playlistaddmusic',
      data: {'name': playlistName, 'music_list': musicList},
    );
  }

  Future<Map<String, dynamic>> removeMusicFromPlaylist({
    required String playlistName,
    required List<String> musicList,
  }) async {
    final response = await _client.post(
      '/playlistdelmusic',
      data: {'name': playlistName, 'music_list': musicList},
    );
    return response.data as Map<String, dynamic>;
  }

  // 音乐库相关方法
  Future<void> deleteMusic(String musicName) async {
    await _client.post('/delmusic', data: {'name': musicName});
  }

  Future<Map<String, dynamic>> getMusicInfo(
    String musicName, {
    bool includeTag = false,
  }) async {
    final response = await _client.get(
      '/musicinfo',
      queryParameters: {'name': musicName, 'musictag': includeTag},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMusicInfos(
    List<String> musicNames, {
    bool includeTag = false,
  }) async {
    final response = await _client.get(
      '/musicinfos',
      queryParameters: {'name': musicNames, 'musictag': includeTag},
    );
    return response.data as List<dynamic>;
  }

  Future<void> setMusicTag(Map<String, dynamic> musicInfo) async {
    await _client.post('/setmusictag', data: musicInfo);
  }

  // 网络下载：整表
  Future<Map<String, dynamic>> downloadPlaylist({
    required String playlistName,
    String? url,
  }) async {
    final payload = {'dirname': playlistName, if (url != null) 'url': url};
    final resp = await _client.post('/downloadplaylist', data: payload);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // 网络下载：单曲
  Future<Map<String, dynamic>> downloadOneMusic({
    required String musicName,
    String? url,
    String? dirname,
    String? playlistName,
  }) async {
    final payload = {
      'name': musicName,
      if (url != null) 'url': url,
      if (dirname != null && dirname.isNotEmpty) 'dirname': dirname,
      if (playlistName != null && playlistName.isNotEmpty)
        'playlist_name': playlistName,
    };
    final resp = await _client.post('/downloadonemusic', data: payload);
    return (resp.data as Map).cast<String, dynamic>();
  }

  /// 检测当前后端是否支持 downloadonemusic.dirname 参数
  ///
  /// 通过 openapi schema 中 DownloadOneMusic 的字段判断。
  /// 结果会缓存，避免重复请求。
  Future<bool> supportsDownloadOneMusicDirname() async {
    if (_supportsDownloadOneMusicDirname != null) {
      return _supportsDownloadOneMusicDirname!;
    }

    try {
      final response = await _client.get('/openapi.json');
      final root = response.data as Map<String, dynamic>;
      final components = root['components'];
      if (components is! Map) {
        _supportsDownloadOneMusicDirname = false;
        return false;
      }

      final schemas = components['schemas'];
      if (schemas is! Map) {
        _supportsDownloadOneMusicDirname = false;
        return false;
      }

      final downloadOneMusic = schemas['DownloadOneMusic'];
      if (downloadOneMusic is! Map) {
        _supportsDownloadOneMusicDirname = false;
        return false;
      }

      final properties = downloadOneMusic['properties'];
      if (properties is! Map) {
        _supportsDownloadOneMusicDirname = false;
        return false;
      }

      _supportsDownloadOneMusicDirname = properties.containsKey('dirname');
      return _supportsDownloadOneMusicDirname!;
    } catch (e) {
      debugPrint('⚠️ [MusicApiService] 检测 downloadonemusic.dirname 支持失败: $e');
      _supportsDownloadOneMusicDirname = false;
      return false;
    }
  }

  /// 检测当前后端是否支持 downloadonemusic.playlist_name 参数
  ///
  /// 通过 openapi schema 中 DownloadOneMusic 的字段判断。
  /// 结果会缓存，避免重复请求。
  Future<bool> supportsDownloadOneMusicPlaylistName() async {
    if (_supportsDownloadOneMusicPlaylistName != null) {
      return _supportsDownloadOneMusicPlaylistName!;
    }

    try {
      final response = await _client.get('/openapi.json');
      final root = response.data as Map<String, dynamic>;
      final components = root['components'];
      if (components is! Map) {
        _supportsDownloadOneMusicPlaylistName = false;
        return false;
      }

      final schemas = components['schemas'];
      if (schemas is! Map) {
        _supportsDownloadOneMusicPlaylistName = false;
        return false;
      }

      final downloadOneMusic = schemas['DownloadOneMusic'];
      if (downloadOneMusic is! Map) {
        _supportsDownloadOneMusicPlaylistName = false;
        return false;
      }

      final properties = downloadOneMusic['properties'];
      if (properties is! Map) {
        _supportsDownloadOneMusicPlaylistName = false;
        return false;
      }

      _supportsDownloadOneMusicPlaylistName =
          properties.containsKey('playlist_name');
      return _supportsDownloadOneMusicPlaylistName!;
    } catch (e) {
      debugPrint('⚠️ [MusicApiService] 检测 downloadonemusic.playlist_name 支持失败: $e');
      _supportsDownloadOneMusicPlaylistName = false;
      return false;
    }
  }

  /// 本次应用运行中是否还应尝试 dirname 参数。
  ///
  /// - false: 已确认不支持，不再尝试
  /// - true/null: 允许尝试
  bool canAttemptDownloadOneMusicDirname() {
    return _supportsDownloadOneMusicDirname != false;
  }

  /// 本次应用运行中是否还应尝试 playlist_name 参数。
  ///
  /// - false: 已确认不支持，不再尝试
  /// - true/null: 允许尝试
  bool canAttemptDownloadOneMusicPlaylistName() {
    return _supportsDownloadOneMusicPlaylistName != false;
  }

  /// 标记后端支持 dirname 参数。
  void markDownloadOneMusicDirnameSupported() {
    _supportsDownloadOneMusicDirname = true;
  }

  /// 标记后端支持 playlist_name 参数。
  void markDownloadOneMusicPlaylistNameSupported() {
    _supportsDownloadOneMusicPlaylistName = true;
  }

  /// 标记后端不支持 dirname 参数（本次运行不再尝试）。
  void markDownloadOneMusicDirnameUnsupported() {
    _supportsDownloadOneMusicDirname = false;
  }

  /// 标记后端不支持 playlist_name 参数（本次运行不再尝试）。
  void markDownloadOneMusicPlaylistNameUnsupported() {
    _supportsDownloadOneMusicPlaylistName = false;
  }

  // 通用文件上传方法
  Future<Map<String, dynamic>> uploadFiles({
    required String endpoint,
    required List<UploadFile> files,
    Map<String, dynamic>? extraFields,
  }) async {
    final formData = FormData();

    // 添加文件
    for (final f in files) {
      formData.files.add(
        MapEntry(f.fieldName, await MultipartFile.fromFile(f.filePath)),
      );
    }

    // 添加额外字段
    if (extraFields != null) {
      formData.fields.addAll(
        extraFields.entries.map((e) => MapEntry(e.key, e.value.toString())),
      );
    }

    final resp = await _client.post(endpoint, data: formData);
    return (resp.data as Map).cast<String, dynamic>();
  }

  // 上传 ytdlp Cookie 文件供后端下载器使用
  Future<Map<String, dynamic>> uploadYtDlpCookie(String filePath) async {
    return uploadFiles(
      endpoint: '/uploadytdlpcookie',
      files: [UploadFile(fieldName: 'file', filePath: filePath)],
    );
  }

  // ==================== JS插件相关 ====================

  /// 获取JS插件列表
  /// [enabledOnly] 是否只返回已启用的插件
  /// 返回格式: {"success": true, "data": [...]}
  Future<Map<String, dynamic>> getJsPlugins({bool enabledOnly = true}) async {
    final response = await _client.get(
      '/api/js-plugins',
      queryParameters: {'enabled_only': enabledOnly},
    );
    return response.data as Map<String, dynamic>;
  }

  /// 检测是否配置了JS插件
  /// 返回 true 表示有可用的JS插件
  Future<bool> hasJsPlugins() async {
    try {
      final result = await getJsPlugins(enabledOnly: true);
      if (result['success'] == true) {
        final plugins = result['data'] as List<dynamic>?;
        return plugins != null && plugins.isNotEmpty;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ [MusicApiService] 检测JS插件失败: $e');
      return false;
    }
  }

  // ==================== 批量推送歌曲 ====================

  /// 推送歌曲列表给设备播放（用于有JS插件的情况）
  /// [did] 设备ID
  /// [songList] 歌曲列表，格式由xiaomusic定义
  /// [playlistName] 播放列表名称
  Future<Map<String, dynamic>> pushSongList({
    required String did,
    required List<Map<String, dynamic>> songList,
    String playlistName = '在线播放',
  }) async {
    final response = await _client.post(
      '/api/device/pushList',
      data: {'did': did, 'songList': songList, 'playlistName': playlistName},
    );
    return response.data as Map<String, dynamic>;
  }
}
