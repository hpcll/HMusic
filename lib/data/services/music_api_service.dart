import '../../core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../adapters/music_list_json_adapter.dart';
import '../models/online_music_result.dart';

class UploadFile {
  final String fieldName;
  final String filePath;

  const UploadFile({required this.fieldName, required this.filePath});
}

class MusicApiService {
  final DioClient _client;

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

  // 保存设置接口
  Future<dynamic> saveSetting(Map<String, dynamic> settings) async {
    final response = await _client.post('/savesetting', data: settings);
    return response.data; // 直接返回原始数据，可能是字符串或Map
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

  // 通过设置在线播放列表来播放音乐（兼容旧版本）
  Future<void> playOnlineMusic({
    required String did,
    required String musicUrl,
    required String musicTitle,
    required String musicAuthor,
    Map<String, String>? headers,
  }) async {
    // 使用新的适配器创建单首歌曲JSON
    final musicListJsonString = MusicListJsonAdapter.createSingleSongJson(
      title: musicTitle,
      artist: musicAuthor,
      url: musicUrl,
      headers: headers,
    );

    debugPrint('🔵 完整的音乐列表JSON: $musicListJsonString');

    // 获取当前设置，然后更新音乐列表
    final currentSettings = await getSettings();
    final updatedSettings = Map<String, dynamic>.from(currentSettings);
    updatedSettings['music_list_json'] = musicListJsonString;

    // 保存设置
    final saveResult = await saveSetting(updatedSettings);
    debugPrint('保存设置结果: $saveResult');

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

    // 获取当前设置，然后更新音乐列表
    final currentSettings = await getSettings();
    final updatedSettings = Map<String, dynamic>.from(currentSettings);
    updatedSettings['music_list_json'] = musicListJsonString;

    // 保存设置
    final saveResult = await saveSetting(updatedSettings);
    debugPrint('🔵 [PlayOnlineSearchResult] 保存设置结果: $saveResult');

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
  bool _needsProxy(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // 需要代理的域名列表
    const proxyDomains = [
      'ws.stream.qqmusic.qq.com', // QQ音乐
      'music.163.com', // 网易云音乐
      'freetyst.nf.migu.cn', // 咪咕音乐
      'antiserver.kuwo.cn', // 酷我音乐
      'fs.taihe.com', // 百度音乐
      // 可以根据需要添加更多需要代理的域名
    ];

    return proxyDomains.any((domain) => uri.host.contains(domain));
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
  }) async {
    final payload = {'name': musicName, if (url != null) 'url': url};
    final resp = await _client.post('/downloadonemusic', data: payload);
    return (resp.data as Map).cast<String, dynamic>();
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
}
