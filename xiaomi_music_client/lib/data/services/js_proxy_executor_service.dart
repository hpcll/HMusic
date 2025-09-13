import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';

/// JS脚本代理执行器服务
/// 让JS脚本自己处理所有请求，我们只负责接收结果
class JSProxyExecutorService {
  final Dio _dio = Dio();
  JavascriptRuntime? _runtime;
  String? _currentScript;
  bool _isInitialized = false;

  /// 初始化JS执行环境
  Future<void> initialize() async {
    if (_isInitialized) return;

    _runtime = getJavascriptRuntime();
    await _setupLXMusicEnvironment();
    _isInitialized = true;

    print('[JSProxy] ✅ JS执行环境初始化完成');
  }

  /// 设置LX Music运行环境
  Future<void> _setupLXMusicEnvironment() async {
    if (_runtime == null) return;

    // 注入LX Music环境模拟
    final lxEnvironment = '''
      // 模拟globalThis.lx环境
      globalThis.lx = {
        EVENT_NAMES: {
          request: 'request',
          inited: 'inited',
          updateAlert: 'updateAlert'
        },
        
        // 网络请求函数 - 通过Flutter代理
        request: function(url, options, callback) {
          console.log('[LXEnv] 发起网络请求:', url);
          
          // 调用Flutter的网络请求代理
          const requestId = 'req_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
          globalThis._pendingRequests = globalThis._pendingRequests || {};
          globalThis._pendingRequests[requestId] = callback;
          
          // 发送请求给Flutter
          const requestData = {
            id: requestId,
            url: url,
            options: options || {}
          };
          console.log('[LXEnv] 调用Flutter网络请求代理，请求数据:', requestData);
          globalThis._flutterRequestProxy(requestData);
        },
        
        // 事件监听
        on: function(eventName, handler) {
          console.log('[LXEnv] 注册事件监听:', eventName);
          globalThis._lxHandlers = globalThis._lxHandlers || {};
          globalThis._lxHandlers[eventName] = handler;
        },
        
        // 发送事件
        send: function(eventName, data) {
          console.log('[LXEnv] 发送事件:', eventName, data);
          globalThis._flutterEventSender(JSON.stringify({
            event: eventName,
            data: data
          }));
        },
        
        // 工具函数
        utils: {
          buffer: {
            from: function(data, encoding) {
              return { data: data, encoding: encoding || 'utf-8' };
            },
            bufToString: function(buf, encoding) {
              if (encoding === 'base64') {
                return btoa(unescape(encodeURIComponent(buf.data)));
              } else if (encoding === 'hex') {
                return buf.data.split('').map(c => 
                  c.charCodeAt(0).toString(16).padStart(2, '0')
                ).join('');
              }
              return buf.data;
            }
          }
        },
        
        // 环境信息
        env: 'desktop',
        version: '1.0.0',
        currentScriptInfo: {
          version: '1.0.0'
        }
      };
      
      // 初始化全局变量
      globalThis._lxHandlers = {};
      globalThis._pendingRequests = {};
      globalThis._musicSources = {};
      
      console.log('[LXEnv] ✅ LX Music环境初始化完成');
    ''';

    _runtime!.evaluate(lxEnvironment);

    // 注入 console.* polyfill，避免脚本使用 console.group 等时报错
    _runtime!.evaluate('''
      (function() {
        try {
          if (typeof globalThis.console === 'undefined') globalThis.console = {};
          if (typeof console.log !== 'function') console.log = function() {};
          if (typeof console.warn !== 'function') console.warn = function() {};
          if (typeof console.error !== 'function') console.error = function() {};
          if (typeof console.group !== 'function') console.group = function() { try { console.log.apply(console, arguments); } catch (e) {} };
          if (typeof console.groupCollapsed !== 'function') console.groupCollapsed = console.group;
          if (typeof console.groupEnd !== 'function') console.groupEnd = function() {};
        } catch (e) {}
      })();
    ''');

    // 使用sendMessage机制注册Flutter函数供JS调用
    _runtime!.evaluate('''
      globalThis._flutterRequestProxy = function(args) {
        console.log('[LXEnv] 调用Flutter网络请求代理');
        console.log('[LXEnv] 发送的参数:', args);
        console.log('[LXEnv] 参数类型:', typeof args);
        try {
          // 确保参数是字符串或可以序列化的对象
          const argsToSend = typeof args === 'string' ? args : JSON.stringify(args);
          console.log('[LXEnv] 序列化后的参数:', argsToSend);
          sendMessage('_flutterRequestProxy', argsToSend);
        } catch (e) {
          console.error('[LXEnv] 发送消息失败:', e);
        }
      };
      
      globalThis._flutterEventSender = function(args) {
        console.log('[LXEnv] 调用Flutter事件发送器');
        console.log('[LXEnv] 事件参数:', args);
        console.log('[LXEnv] 事件参数类型:', typeof args);
        try {
          // 确保参数是字符串
          const argsToSend = typeof args === 'string' ? args : JSON.stringify(args);
          console.log('[LXEnv] 事件序列化后的参数:', argsToSend);
          sendMessage('_flutterEventSender', argsToSend);
        } catch (e) {
          console.error('[LXEnv] 发送事件失败:', e);
        }
      };
    ''');

    // 注册Flutter网络请求代理
    _runtime!.onMessage('_flutterRequestProxy', (args) async {
      print('[JSProxy] 📥 收到网络请求代理消息: $args');
      print('[JSProxy] 📥 参数类型: ${args.runtimeType}');

      // 现在args应该是字符串，需要解析为Map
      try {
        Map<String, dynamic> requestData;
        if (args is String) {
          requestData = jsonDecode(args);
        } else if (args is Map) {
          requestData = Map<String, dynamic>.from(args);
        } else {
          throw Exception('Unexpected args type: ${args.runtimeType}');
        }

        print('[JSProxy] 📥 解析后的请求数据: $requestData');
        await _handleNetworkRequest(requestData);
      } catch (e) {
        print('[JSProxy] ❌ 处理网络请求代理参数失败: $e, args: $args');
        print('[JSProxy] ❌ 错误堆栈: ${StackTrace.current}');
      }
    });

    // 注册Flutter事件发送器
    _runtime!.onMessage('_flutterEventSender', (args) {
      print('[JSProxy] 📥 收到事件发送器消息: $args');
      print('[JSProxy] 📥 事件参数类型: ${args.runtimeType}');

      try {
        Map<String, dynamic> eventData;
        if (args is String) {
          eventData = jsonDecode(args);
        } else if (args is Map) {
          eventData = Map<String, dynamic>.from(args);
        } else {
          throw Exception('Unexpected event args type: ${args.runtimeType}');
        }

        print('[JSProxy] 📥 解析后的事件数据: $eventData');
        _handleEventSend(eventData);
      } catch (e) {
        print('[JSProxy] ❌ 处理事件发送器参数失败: $e, args: $args');
        print('[JSProxy] ❌ 错误堆栈: ${StackTrace.current}');
      }
    });
  }

  /// 处理JS发起的网络请求
  Future<void> _handleNetworkRequest(Map<String, dynamic> requestData) async {
    try {
      final requestId = requestData['id'];
      final url = requestData['url'];
      final options = requestData['options'] ?? {};

      print('[JSProxy] 🌐 处理网络请求: $url');
      print('[JSProxy] 🔍 请求参数详情: $requestData');

      // 发起实际的网络请求
      final response = await _dio.request(
        url,
        options: Options(
          method: options['method'] ?? 'GET',
          headers: Map<String, String>.from(options['headers'] ?? {}),
          followRedirects: options['follow_max'] != null,
          maxRedirects: options['follow_max'] ?? 5,
        ),
        data: options['data'],
      );

      // 构造响应数据 - 确保body是JS脚本期望的格式
      dynamic bodyData = response.data;

      // 如果响应数据是字符串，尝试解析为JSON
      if (bodyData is String) {
        try {
          bodyData = jsonDecode(bodyData);
        } catch (e) {
          // 如果解析失败，保持原始字符串
          print('[JSProxy] 响应数据不是有效JSON，保持原始格式: $e');
        }
      }

      // 兼容：部分脚本期望 body.url，但服务端返回的是 body.data
      try {
        if (bodyData is Map) {
          final Map<String, dynamic> tmp = Map<String, dynamic>.from(bodyData);
          if (!tmp.containsKey('url') && tmp['data'] is String) {
            tmp['url'] = tmp['data'];
          }
          bodyData = tmp;
        }
      } catch (_) {}

      final responseData = {
        'statusCode': response.statusCode,
        'body': bodyData,
        'headers': response.headers.map,
      };

      // 调用JS回调
      final callbackScript = '''
        (function() {
          try {
            if (globalThis._pendingRequests['$requestId']) {
              const callback = globalThis._pendingRequests['$requestId'];
              delete globalThis._pendingRequests['$requestId'];
              
              const response = ${jsonEncode(responseData)};
              
              console.log('[JSProxy] 调用网络请求回调，请求ID: $requestId');
              console.log('[JSProxy] 响应状态:', response.statusCode);
              console.log('[JSProxy] 响应数据类型:', typeof response.body);
              
              // 确保回调正确执行
              callback(null, response);
              console.log('[JSProxy] 回调执行完成');
              
              // 设置Promise结果供轮询检查
              if (response.body && typeof response.body === 'object') {
                if (response.body.code === 0) {
                  globalThis._promiseResult = response.body.data || response.body.url;
                  globalThis._promiseComplete = true;
                  console.log('[JSProxy] Promise结果已设置:', globalThis._promiseResult);
                } else if (response.body.code !== undefined) {
                  globalThis._promiseError = response.body.msg || response.body.message || 'API返回错误';
                  globalThis._promiseComplete = true;
                  console.log('[JSProxy] Promise错误已设置:', globalThis._promiseError);
                }
              }
              
              return true;
            } else {
              console.log('[JSProxy] 未找到请求ID对应的回调: $requestId');
              console.log('[JSProxy] 当前待处理请求:', Object.keys(globalThis._pendingRequests || {}));
              return false;
            }
          } catch (e) {
            console.error('[JSProxy] 回调执行错误:', e);
            return false;
          }
        })()
      ''';

      _runtime!.evaluate(callbackScript);
      print('[JSProxy] ✅ 网络请求完成: ${response.statusCode}');
    } catch (e) {
      print('[JSProxy] ❌ 网络请求失败: $e');

      // 通知JS请求失败
      final requestId = requestData['id'] ?? 'unknown';
      final errorScript = '''
        (function() {
          try {
            if (globalThis._pendingRequests['$requestId']) {
              const callback = globalThis._pendingRequests['$requestId'];
              delete globalThis._pendingRequests['$requestId'];
              console.log('[JSProxy] 调用错误回调，请求ID: $requestId');
              callback(new Error('${e.toString().replaceAll("'", "\\'")}'), null);
              return true;
            } else {
              console.log('[JSProxy] 未找到错误回调: $requestId');
              return false;
            }
          } catch (callbackError) {
            console.error('[JSProxy] 错误回调执行失败:', callbackError);
            return false;
          }
        })()
      ''';

      _runtime!.evaluate(errorScript);
    }
  }

  /// 处理JS发送的事件
  void _handleEventSend(Map<String, dynamic> eventData) {
    try {
      final eventName = eventData['event'];
      final data = eventData['data'];

      print('[JSProxy] 📡 收到JS事件: $eventName');

      // 处理特定事件
      switch (eventName) {
        case 'inited':
          print('[JSProxy] 🎵 JS脚本初始化完成');
          // 存储音源信息到全局变量
          if (data != null && data['sources'] != null) {
            final sourcesJson = jsonEncode(data['sources']);
            _runtime!.evaluate('globalThis._musicSources = $sourcesJson;');
            print('[JSProxy] 📋 已存储音源信息: ${data['sources'].keys.join(', ')}');
          }
          break;
        case 'updateAlert':
          print('[JSProxy] 🔄 脚本更新提醒: ${data?['log']}');
          break;
        default:
          print('[JSProxy] 📨 未处理的事件: $eventName');
      }
    } catch (e) {
      print('[JSProxy] ❌ 事件处理失败: $e');
    }
  }

  /// 加载JS脚本
  Future<bool> loadScript(String scriptContent) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('[JSProxy] 📜 开始加载JS脚本...');

      // 保存脚本内容供检测使用
      _runtime!.evaluate(
        'globalThis._currentScriptContent = ${jsonEncode(scriptContent)};',
      );

      // 执行JS脚本
      _runtime!.evaluate(scriptContent);
      _currentScript = scriptContent;

      // 等待脚本初始化
      await Future.delayed(const Duration(milliseconds: 500));

      // 检查脚本是否正确加载
      final checkResult = _runtime!.evaluate('''
        (function() {
          try {
            return {
              hasHandlers: Object.keys(globalThis._lxHandlers || {}).length > 0,
              hasMusicSources: Object.keys(globalThis._musicSources || {}).length > 0,
              handlers: Object.keys(globalThis._lxHandlers || {}),
              hasLxExport: typeof globalThis.lx !== 'undefined',
              hasScriptManifest: typeof scriptManifest !== 'undefined',
              hasGetMusicUrl: typeof getMusicUrl !== 'undefined',
              globalKeys: Object.keys(globalThis).filter(k => !k.startsWith('_')).slice(0, 10)
            };
          } catch (e) {
            return { error: e.toString() };
          }
        })()
      ''');

      print('[JSProxy] 🔍 脚本加载检查结果: ${checkResult.stringResult}');

      // 尝试手动触发脚本初始化或查找音源定义
      try {
        final initResult = _runtime!.evaluate('''
          (function() {
            try {
              // 查找可能的音源定义
              const possibleSources = {};
              
              // 检查是否有 scriptManifest
              if (typeof scriptManifest !== 'undefined' && scriptManifest.supportedPlatforms) {
                scriptManifest.supportedPlatforms.forEach(p => {
                  possibleSources[p] = { name: p, supported: true };
                });
              }
              
              // 检查常见的平台标识和函数
              const commonPlatforms = ['tx', 'wy', 'kg', 'kw', 'qq', 'netease', 'kugou', 'kuwo'];
              const functionPatterns = [
                p => p + 'GetMusicUrl',
                p => 'get' + p.toUpperCase() + 'Url', 
                p => p + '_getMusicUrl',
                p => p + 'Music',
                p => 'handle' + p.toUpperCase(),
                p => p.toUpperCase() + '_MUSIC_URL'
              ];
              
              commonPlatforms.forEach(p => {
                // 检查各种函数命名模式
                const hasFunction = functionPatterns.some(pattern => {
                  const funcName = pattern(p);
                  return typeof globalThis[funcName] === 'function';
                });
                
                if (hasFunction) {
                  possibleSources[p] = { name: p, supported: true };
                }
              });
              
              // 检查是否有通用的处理函数
              if (typeof getMusicUrl === 'function' || typeof handleGetMusicUrl === 'function') {
                // 如果有通用函数，假设支持所有常见平台
                commonPlatforms.forEach(p => {
                  possibleSources[p] = { name: p, supported: true };
                });
              }
              
              // 检查脚本头部注释中的支持信息
              if (typeof globalThis._currentScriptContent === 'string') {
                const scriptContent = globalThis._currentScriptContent;
                const supportedMatch = scriptContent.match(/@supported\\s*[:|=]\\s*([\\w,\\s]+)/i);
                if (supportedMatch) {
                  const supportedList = supportedMatch[1].split(',').map(s => s.trim());
                  supportedList.forEach(platform => {
                    if (platform && commonPlatforms.includes(platform)) {
                      possibleSources[platform] = { name: platform, supported: true };
                    }
                  });
                }
              }
              
              // 如果找到音源，存储到 _musicSources
              if (Object.keys(possibleSources).length > 0) {
                globalThis._musicSources = possibleSources;
                return { success: true, sources: possibleSources };
              }
              
              return { success: false, message: 'No sources detected' };
            } catch (e) {
              return { error: e.toString() };
            }
          })()
        ''');

        print('[JSProxy] 🔍 手动初始化结果: ${initResult.stringResult}');
      } catch (e) {
        print('[JSProxy] ⚠️ 手动初始化失败: $e');
      }

      if (checkResult.stringResult.contains('error')) {
        print('[JSProxy] ❌ 脚本加载失败');
        return false;
      }

      print('[JSProxy] ✅ JS脚本加载成功');
      return true;
    } catch (e) {
      print('[JSProxy] ❌ JS脚本加载异常: $e');
      return false;
    }
  }

  /// 获取音乐播放链接
  Future<String?> getMusicUrl({
    required String source, // tx, wy, kg等
    required String songId, // 歌曲ID
    required String quality, // 320k, flac等
    Map<String, dynamic>? musicInfo, // 额外音乐信息
  }) async {
    if (!_isInitialized || _currentScript == null) {
      print('[JSProxy] ❌ JS环境未初始化或脚本未加载');
      return null;
    }

    try {
      print('[JSProxy] 🎵 开始获取音乐链接: $source/$songId/$quality');

      // 构造请求参数
      final requestParams = {
        'action': 'musicUrl',
        'source': source,
        'info': {
          'musicInfo': {'songmid': songId, 'hash': songId, ...?musicInfo},
          'type': quality,
        },
      };

      // 清除之前的结果
      _runtime!.evaluate(
        'globalThis._promiseResult = null; globalThis._promiseError = null; globalThis._promiseComplete = false;',
      );

      // 调用JS处理函数
      final executeScript = '''
        (function() {
          try {
            const params = ${jsonEncode(requestParams)};
            console.log('[JSProxy] 调用JS处理函数:', params);
            
            if (globalThis._lxHandlers && globalThis._lxHandlers.request) {
              const result = globalThis._lxHandlers.request(params);
              
              // 检查是否是Promise
              if (result && typeof result.then === 'function') {
                console.log('[JSProxy] 检测到Promise，开始等待...');
                result.then(function(resolvedValue) {
                  console.log('[JSProxy] Promise resolved:', resolvedValue);
                  globalThis._promiseResult = resolvedValue;
                  globalThis._promiseComplete = true;
                  console.log('[JSProxy] 设置Promise结果完成');
                }).catch(function(error) {
                  console.log('[JSProxy] Promise rejected:', error);
                  globalThis._promiseError = error ? error.toString() : 'Unknown Promise error';
                  globalThis._promiseComplete = true;
                  console.log('[JSProxy] 设置Promise错误完成');
                });
                return JSON.stringify({ success: true, isPromise: true });
              } else {
                console.log('[JSProxy] 直接返回结果:', result);
                return JSON.stringify({ success: true, result: result });
              }
            } else {
              return JSON.stringify({ success: false, error: '未找到请求处理函数' });
            }
          } catch (e) {
            console.error('[JSProxy] JS执行错误:', e);
            return JSON.stringify({ success: false, error: e.toString() });
          }
        })()
      ''';

      final result = _runtime!.evaluate(executeScript);
      print('[JSProxy] 🔍 JS执行结果: ${result.stringResult}');

      // 解析结果
      Map<String, dynamic> resultData;
      try {
        resultData = jsonDecode(result.stringResult);
      } catch (e) {
        print('[JSProxy] ❌ JSON解析失败: $e');
        print('[JSProxy] 原始结果: ${result.stringResult}');
        return null;
      }

      if (resultData['success'] == true) {
        if (resultData['isPromise'] == true) {
          // 等待Promise完成
          print('[JSProxy] ⏳ 等待Promise完成...');

          for (int i = 0; i < 200; i++) {
            // 最多等待20秒
            await Future.delayed(Duration(milliseconds: 100));

            final checkResult = _runtime!.evaluate('''
              (function() {
                try {
                  console.log('[JSProxy] 检查Promise状态:', globalThis._promiseComplete, globalThis._promiseResult, globalThis._promiseError);
                  
                  if (globalThis._promiseComplete === true) {
                    if (globalThis._promiseResult !== null && globalThis._promiseResult !== undefined) {
                      console.log('[JSProxy] Promise成功，结果:', globalThis._promiseResult);
                      return JSON.stringify({ success: true, result: globalThis._promiseResult });
                    } else if (globalThis._promiseError !== null && globalThis._promiseError !== undefined) {
                      console.log('[JSProxy] Promise失败，错误:', globalThis._promiseError);
                      return JSON.stringify({ success: false, error: globalThis._promiseError });
                    } else {
                      console.log('[JSProxy] Promise完成但无结果');
                      return JSON.stringify({ success: false, error: 'Promise完成但无结果' });
                    }
                  } else {
                    return JSON.stringify({ waiting: true });
                  }
                } catch (e) {
                  console.error('[JSProxy] 检查Promise状态错误:', e);
                  return JSON.stringify({ success: false, error: 'Check promise error: ' + e.toString() });
                }
              })()
            ''');

            final checkData = jsonDecode(checkResult.stringResult);

            if (checkData['success'] == true) {
              final musicUrl = checkData['result'];
              print('[JSProxy] ✅ Promise完成，获取音乐链接: $musicUrl');
              return musicUrl;
            } else if (checkData['success'] == false) {
              print('[JSProxy] ❌ Promise失败: ${checkData['error']}');
              return null;
            }

            // 每秒显示一次等待状态
            if (i % 10 == 0) {
              print('[JSProxy] ⏳ 等待Promise完成... ${i / 10}秒');
            }
          }

          print('[JSProxy] ⏰ Promise等待超时 (20秒)');
          return null;
        } else {
          final musicUrl = resultData['result'];
          print('[JSProxy] ✅ 成功获取音乐链接: $musicUrl');
          return musicUrl;
        }
      } else {
        print('[JSProxy] ❌ 获取音乐链接失败: ${resultData['error']}');
        return null;
      }
    } catch (e) {
      print('[JSProxy] ❌ 获取音乐链接异常: $e');
      return null;
    }
  }

  /// 获取支持的音源列表
  Map<String, dynamic> getSupportedSources() {
    if (!_isInitialized || _currentScript == null) {
      return {};
    }

    try {
      final result = _runtime!.evaluate('''
        (function() {
          try {
            return JSON.stringify(globalThis._musicSources || {});
          } catch (e) {
            return '{}';
          }
        })()
      ''');

      return Map<String, dynamic>.from(jsonDecode(result.stringResult));
    } catch (e) {
      print('[JSProxy] ❌ 获取音源列表失败: $e');
      return {};
    }
  }

  /// 释放资源
  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    _currentScript = null;
    _isInitialized = false;
    print('[JSProxy] 🧹 资源已释放');
  }
}
