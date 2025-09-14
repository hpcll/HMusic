import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/js_proxy_provider.dart';

/// JS代理执行器测试页面
class JSProxyTestPage extends ConsumerStatefulWidget {
  const JSProxyTestPage({Key? key}) : super(key: key);

  @override
  ConsumerState<JSProxyTestPage> createState() => _JSProxyTestPageState();
}

class _JSProxyTestPageState extends ConsumerState<JSProxyTestPage> {
  final TextEditingController _scriptController = TextEditingController();
  final TextEditingController _scriptUrlController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController(
    text: 'tx',
  );
  final TextEditingController _songIdController = TextEditingController(
    text: '001NgljR0RUhy1',
  );
  final TextEditingController _qualityController = TextEditingController(
    text: '320k',
  );

  String _testResult = '';
  bool _isFetchingUrl = false;

  @override
  void initState() {
    super.initState();
    // 预填充真实的LX音源脚本
    _scriptController.text = r'''
/*!
 * @name windyday
 * @description 自用
 * @version 1.0.4
 * @author windyday
 * @repository https://github.com/lxmusics/lx-music-api-server
 */

// 是否开启开发模式
const DEV_ENABLE = true
// 是否开启更新提醒
const UPDATE_ENABLE = true
// 服务端地址
const API_URL = "http://43.143.63.234:9763"
// 服务端配置的请求key
const API_KEY = `djbd`
// 音质配置(key为音源名称,不要乱填.如果你账号为VIP可以填写到hires)
// 全部的支持值: ['128k', '320k', 'flac', 'flac24bit']
const MUSIC_QUALITY = JSON.parse('{"kw":["128k"],"kg":["128k"],"tx":["128k","320k","flac","flac24bit"],"wy":["128k"],"mg":["128k"]}')
// 音源配置(默认为自动生成,可以修改为手动)
const MUSIC_SOURCE = Object.keys(MUSIC_QUALITY)
MUSIC_SOURCE.push('local')

/**
 * 下面的东西就不要修改了
 */
const { EVENT_NAMES, request, on, send, utils, env, version } = globalThis.lx

// MD5值,用来检查更新
const SCRIPT_MD5 = 'cf875b238b48c95e27d166a840e3f638'

/**
 * URL请求
 *
 * @param {string} url - 请求的地址
 * @param {object} options - 请求的配置文件
 * @return {Promise} 携带响应体的Promise对象
 */
const httpFetch = (url, options = { method: 'GET' }) => {
  return new Promise((resolve, reject) => {
    console.log('--- start --- ' + url)
    request(url, options, (err, resp) => {
      if (err) {
        console.log('httpFetch error:', err)
        return reject(err)
      }
      console.log('API Response: ', resp)
      console.log('API Response type:', typeof resp)
      console.log('API Response statusCode:', resp ? resp.statusCode : 'no statusCode')
      console.log('API Response body:', resp ? resp.body : 'no body')
      
      // 立即设置Promise结果给全局变量
      if (resp && resp.body && resp.body.code === 0) {
        console.log('🎯 直接设置Promise结果:', resp.body.data)
        globalThis._promiseResult = resp.body.data
        globalThis._promiseComplete = true
      } else if (resp && resp.body) {
        console.log('🎯 直接设置Promise错误:', resp.body.msg || 'API error')
        globalThis._promiseError = resp.body.msg || 'API error'
        globalThis._promiseComplete = true
      }
      
      resolve(resp)
    })
  })
}

/**
 * 
 * @param {string} source - 音源
 * @param {object} musicInfo - 歌曲信息
 * @param {string} quality - 音质
 * @returns {Promise<string>} 歌曲播放链接
 * @throws {Error} - 错误消息
 */
const handleGetMusicUrl = async (source, musicInfo, quality) => {
  console.log('🎵 handleGetMusicUrl 开始执行:', source, musicInfo, quality)
  
  try {
    const songId = musicInfo.hash ?? musicInfo.songmid
    console.log('🎵 songId:', songId)

    const request = await httpFetch(`${API_URL}/url/${source}/${songId}/${quality}`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': `${env ? `lx-music-${env}/${version}` : `lx-music-request/${version}`}`,
        'X-Request-Key': API_KEY,
      },
      follow_max: 5,
    })
    
    console.log('🎵 httpFetch 完成，开始处理响应')
    console.log('🎵 请求对象类型:', typeof request)
    console.log('🎵 请求对象:', request)
    
    // 修复：直接使用request.body而不是解构
    const body = request ? request.body : null
    
    console.log('🎵 提取的body:', body)
    console.log('🎵 body类型:', typeof body)
    
    if (!body) {
      console.log('🎵 body为空，抛出错误')
      throw new Error('empty response body')
    }
    
    // 处理body可能是字符串的情况
    let responseBody = body
    if (typeof body === 'string') {
      try {
        responseBody = JSON.parse(body)
        console.log('🎵 JSON解析成功:', responseBody)
      } catch (e) {
        console.log('🎵 JSON解析失败:', e.message)
        throw new Error('invalid JSON response: ' + e.message)
      }
    } else {
      console.log('🎵 body已是对象类型:', responseBody)
    }
    
    if (!responseBody || typeof responseBody.code === 'undefined') {
      console.log('🎵 响应格式无效:', responseBody)
      throw new Error('invalid response format, expected {code: number}, got: ' + JSON.stringify(responseBody))
    }
    
    console.log('🎵 开始处理响应码:', responseBody.code)
  switch (responseBody.code) {
    case 0:
      console.log(`handleGetMusicUrl(${source}_${musicInfo.songmid}, ${quality}) success, URL: ${responseBody.data}`)
      return responseBody.data
    case 1:
      console.log(`handleGetMusicUrl(${source}_${musicInfo.songmid}, ${quality}) failed: ip被封禁`)
      throw new Error('block ip')
    case 2:
      console.log(`handleGetMusicUrl(${source}_${musicInfo.songmid}, ${quality}) failed, ${responseBody.msg}`)
      throw new Error('get music url failed')
    case 4:
      console.log(`handleGetMusicUrl(${source}_${musicInfo.songmid}, ${quality}) failed, 远程服务器错误`)
      throw new Error('internal server error')
    case 5:
      console.log(`handleGetMusicUrl(${source}_${musicInfo.songmid}, ${quality}) failed, 请求过于频繁，请休息一下吧`)
      throw new Error('too many requests')
    case 6:
      console.log(`handleGetMusicUrl(${source}_${musicInfo.songmid}, ${quality}) failed, 请求参数错误`)
      throw new Error('param error')
    default:
      console.log(`handleGetMusicUrl(${source}_${musicInfo.songmid}, ${quality}) failed, ${responseBody.msg ? responseBody.msg : 'unknow error'}`)
      throw new Error(responseBody.msg ?? 'unknow error')
  }
  } catch (error) {
    console.log('🎵 handleGetMusicUrl 出现异常:', error)
    console.log('🎵 异常类型:', typeof error)
    console.log('🎵 异常消息:', error.message || error.toString())
    throw error
  }
}

// 生成歌曲信息
const musicSources = {}
MUSIC_SOURCE.forEach(item => {
  musicSources[item] = {
    name: item,
    type: 'music',
    actions: ['musicUrl'],
    qualitys: MUSIC_QUALITY[item],
  }
})

// 监听 LX Music 请求事件
on(EVENT_NAMES.request, ({ action, source, info }) => {
  switch (action) {
    case 'musicUrl':
      console.log(`Handle Action(musicUrl)`)
      console.log('source', source)
      console.log('quality', info.type)
      console.log('musicInfo', info.musicInfo)
      return handleGetMusicUrl(source, info.musicInfo, info.type)
        .then(data => {
          console.log('handleGetMusicUrl resolved with data:', data)
          return Promise.resolve(data)
        })
        .catch(err => {
          console.error('handleGetMusicUrl rejected with error:', err)
          return Promise.reject(err)
        })
    default:
      console.error(`action(${action}) not support`)
      return Promise.reject('action not support')
  }
})

// 向 LX Music 发送初始化成功事件
send(EVENT_NAMES.inited, { status: true, openDevTools: DEV_ENABLE, sources: musicSources })
''';
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _scriptUrlController.dispose();
    _sourceController.dispose();
    _songIdController.dispose();
    _qualityController.dispose();
    super.dispose();
  }

  Future<void> _loadScript() async {
    final jsProxy = ref.read(jsProxyProvider.notifier);
    final success = await jsProxy.loadScript(
      _scriptController.text,
      scriptName: '测试脚本',
    );

    setState(() {
      _testResult = success ? '✅ 脚本加载成功' : '❌ 脚本加载失败';
    });
  }

  String _inferScriptNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '远程脚本';
      return last.isNotEmpty ? last : '远程脚本';
    } catch (_) {
      return '远程脚本';
    }
  }

  Future<void> _importScriptFromUrl({bool loadAfterImport = false}) async {
    final rawUrl = _scriptUrlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _testResult = '⚠️ 请输入脚本链接';
      });
      return;
    }

    setState(() {
      _isFetchingUrl = true;
      _testResult = '🔄 正在下载脚本: $rawUrl';
    });

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          followRedirects: true,
          validateStatus: (code) => code != null && code >= 200 && code < 400,
          responseType: ResponseType.plain,
          headers: const {'Accept': 'text/plain, application/javascript, */*'},
        ),
      );

      final resp = await dio.get<String>(rawUrl);
      final content = resp.data ?? '';
      if (content.isEmpty) {
        throw Exception('脚本内容为空');
      }

      _scriptController.text = content;

      if (loadAfterImport) {
        final jsProxy = ref.read(jsProxyProvider.notifier);
        final success = await jsProxy.loadScript(
          content,
          scriptName: _inferScriptNameFromUrl(rawUrl),
        );
        setState(() {
          _testResult = success ? '✅ 已导入并加载脚本' : '❌ 导入成功但加载失败';
        });
      } else {
        setState(() {
          _testResult = '✅ 已从链接导入脚本内容（未加载）';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '❌ 从链接导入失败: $e';
      });
    } finally {
      setState(() {
        _isFetchingUrl = false;
      });
    }
  }

  Future<void> _importScriptFromLocal({bool loadAfterImport = false}) async {
    try {
      setState(() {
        _isFetchingUrl = true;
        _testResult = '📁 正在选择本地脚本文件...';
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _testResult = '⚠️ 已取消选择文件';
        });
        return;
      }

      final file = result.files.first;
      final content =
          file.bytes != null ? String.fromCharCodes(file.bytes!) : '';
      if (content.isEmpty) {
        setState(() {
          _testResult = '❌ 读取文件失败或内容为空';
        });
        return;
      }

      _scriptController.text = content;

      if (loadAfterImport) {
        final jsProxy = ref.read(jsProxyProvider.notifier);
        final success = await jsProxy.loadScript(
          content,
          scriptName: file.name.isNotEmpty ? file.name : '本地脚本',
        );
        setState(() {
          _testResult = success ? '✅ 已导入并加载脚本' : '❌ 导入成功但加载失败';
        });
      } else {
        setState(() {
          _testResult = '✅ 已从本地文件导入脚本内容（未加载）';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '❌ 从本地导入失败: $e';
      });
    } finally {
      setState(() {
        _isFetchingUrl = false;
      });
    }
  }

  Future<void> _getMusicUrl() async {
    try {
      setState(() {
        _testResult =
            '🔄 正在获取音乐链接...\n音源: ${_sourceController.text}\n歌曲ID: ${_songIdController.text}\n音质: ${_qualityController.text}';
      });

      final jsProxy = ref.read(jsProxyProvider.notifier);
      final url = await jsProxy.getMusicUrl(
        source: _sourceController.text,
        songId: _songIdController.text,
        quality: _qualityController.text,
        musicInfo: {
          'title': '测试歌曲',
          'artist': '测试歌手',
          'songmid': _songIdController.text,
          'hash': _songIdController.text,
        },
      );

      setState(() {
        _testResult =
            url != null
                ? '✅ 获取成功!\n\n🎵 音乐链接:\n$url\n\n📊 测试参数:\n音源: ${_sourceController.text}\n歌曲ID: ${_songIdController.text}\n音质: ${_qualityController.text}'
                : '❌ 获取失败 - 返回结果为空';
      });
    } catch (e) {
      setState(() {
        _testResult =
            '❌ 获取失败!\n\n错误信息: $e\n\n📊 测试参数:\n音源: ${_sourceController.text}\n歌曲ID: ${_songIdController.text}\n音质: ${_qualityController.text}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final jsProxyState = ref.watch(jsProxyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('JS代理执行器测试'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态显示
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('状态信息', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      '初始化状态: ${jsProxyState.isInitialized ? "✅ 已初始化" : "❌ 未初始化"}',
                    ),
                    Text(
                      '加载状态: ${jsProxyState.isLoading ? "⏳ 加载中..." : "✅ 空闲"}',
                    ),
                    Text('当前脚本: ${jsProxyState.currentScript ?? "无"}'),
                    Text(
                      '支持的音源: ${jsProxyState.supportedSources.keys.join(', ')}',
                    ),
                    if (jsProxyState.error != null)
                      Text(
                        '错误: ${jsProxyState.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // JS脚本输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('JS脚本', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _scriptUrlController,
                      decoration: const InputDecoration(
                        labelText: '脚本链接（URL）',
                        hintText:
                            '例如：https://raw.githubusercontent.com/xxx/script.js',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        ElevatedButton(
                          onPressed:
                              (jsProxyState.isLoading || _isFetchingUrl)
                                  ? null
                                  : () => _importScriptFromUrl(
                                    loadAfterImport: true,
                                  ),
                          child: Text(_isFetchingUrl ? '下载中...' : '从链接加载'),
                        ),
                        ElevatedButton(
                          onPressed:
                              (jsProxyState.isLoading || _isFetchingUrl)
                                  ? null
                                  : () => _importScriptFromLocal(
                                    loadAfterImport: true,
                                  ),
                          child: const Text('本地导入并加载'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _scriptController,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '在此输入JS脚本...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: jsProxyState.isLoading ? null : _loadScript,
                      child: Text(jsProxyState.isLoading ? '加载中...' : '加载脚本'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 音乐URL测试
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '音乐URL测试',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 600;
                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _sourceController,
                                decoration: const InputDecoration(
                                  labelText: '音源',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _songIdController,
                                decoration: const InputDecoration(
                                  labelText: '歌曲ID',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _qualityController,
                                decoration: const InputDecoration(
                                  labelText: '音质',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _sourceController,
                                decoration: const InputDecoration(
                                  labelText: '音源',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _songIdController,
                                decoration: const InputDecoration(
                                  labelText: '歌曲ID',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _qualityController,
                                decoration: const InputDecoration(
                                  labelText: '音质',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed:
                          (jsProxyState.isInitialized &&
                                  jsProxyState.currentScript != null)
                              ? _getMusicUrl
                              : null,
                      child: const Text('获取音乐链接'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 测试结果
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('测试结果', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        _testResult.isEmpty ? '等待测试结果...' : _testResult,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color:
                              _testResult.startsWith('✅')
                                  ? Colors.green
                                  : _testResult.startsWith('❌')
                                  ? Colors.red
                                  : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 快捷操作
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('快捷操作', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            ref.read(jsProxyProvider.notifier).clearScript();
                            setState(() {
                              _testResult = '🧹 已清除脚本';
                            });
                          },
                          child: const Text('清除脚本'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final sources =
                                ref
                                    .read(jsProxyProvider.notifier)
                                    .getSupportedSourcesList();
                            setState(() {
                              _testResult = '📋 支持的音源: ${sources.join(', ')}';
                            });
                          },
                          child: const Text('查看音源'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // 邓紫棋 - 唯一
                            _sourceController.text = 'tx';
                            _songIdController.text = '001NgljR0RUhy1';
                            _qualityController.text = '320k';
                            setState(() {
                              _testResult =
                                  '🎵 已设置: 邓紫棋 - 唯一 (tx/001NgljR0RUhy1/320k)';
                            });
                          },
                          child: const Text('唯一'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // 邓紫棋 - 泡沫
                            _sourceController.text = 'tx';
                            _songIdController.text = '001X0PDf0W4lBq';
                            _qualityController.text = '320k';
                            setState(() {
                              _testResult =
                                  '🎵 已设置: 邓紫棋 - 泡沫 (tx/001X0PDf0W4lBq/320k)';
                            });
                          },
                          child: const Text('泡沫'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // 邓紫棋 - 光年之外
                            _sourceController.text = 'tx';
                            _songIdController.text = '002E3MtF0IAMMY';
                            _qualityController.text = '320k';
                            setState(() {
                              _testResult =
                                  '🎵 已设置: 邓紫棋 - 光年之外 (tx/002E3MtF0IAMMY/320k)';
                            });
                          },
                          child: const Text('光年之外'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // 使用简化的测试脚本
                            _scriptController.text = '''
// 简化的JS代理测试脚本
console.log('🚀 开始测试JS代理...');

const { EVENT_NAMES, request, on, send } = globalThis.lx;

// 监听请求事件
on(EVENT_NAMES.request, async ({ action, source, info }) => {
  console.log('📨 收到请求:', action, source, info);
  
  if (action === 'musicUrl') {
    const songId = info.musicInfo.songmid || info.musicInfo.hash;
    const url = `https://lxmusicapi.onrender.com/url/\${source}/\${songId}/\${info.type}`;
    
    console.log('🌐 请求URL:', url);
    
    try {
      // 使用callback模式的request
      const response = await new Promise((resolve, reject) => {
        request(url, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'X-Request-Key': 'share-v2',
            'User-Agent': 'lx-music-request/1.0.0'
          }
        }, (err, resp) => {
          if (err) {
            console.error('❌ 请求失败:', err);
            reject(err);
          } else {
            console.log('✅ 请求成功:', resp);
            resolve(resp);
          }
        });
      });
      
      if (response.body && response.body.code === 0) {
        console.log('🎵 获取到音乐链接:', response.body.data);
        return response.body.data;
      } else {
        throw new Error('API返回错误: ' + (response.body?.msg || '未知错误'));
      }
    } catch (error) {
      console.error('💥 处理失败:', error);
      throw error;
    }
  }
  
  throw new Error('不支持的操作: ' + action);
});

// 发送初始化完成事件
send(EVENT_NAMES.inited, {
  status: true,
  sources: {
    tx: { name: 'tx', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac'] },
    wy: { name: 'wy', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac'] }
  }
});

console.log('✅ JS代理测试脚本加载完成');
''';
                            setState(() {
                              _testResult = '📝 已加载简化测试脚本';
                            });
                          },
                          child: const Text('简化脚本'),
                        ),
                        const SizedBox(width: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                          child: Text(
                            '酷我（kw）',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // 酷我 - 唯一
                            _sourceController.text = 'kw';
                            _songIdController.text = '321260769';
                            _qualityController.text = '128k';
                            setState(() {
                              _testResult = '🎵 已设置: 唯一 (kw/321260769/128k)';
                            });
                          },
                          child: const Text('唯一(kw)'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // 酷我 - 多远都要在一起
                            _sourceController.text = 'kw';
                            _songIdController.text = '6307329';
                            _qualityController.text = '128k';
                            setState(() {
                              _testResult = '🎵 已设置: 多远都要在一起 (kw/6307329/128k)';
                            });
                          },
                          child: const Text('多远都要在一起(kw)'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // 酷我 - 泡沫
                            _sourceController.text = 'kw';
                            _songIdController.text = '1245657';
                            _qualityController.text = '128k';
                            setState(() {
                              _testResult = '🎵 已设置: 泡沫 (kw/1245657/128k)';
                            });
                          },
                          child: const Text('泡沫(kw)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
