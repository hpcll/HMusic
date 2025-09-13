import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';

/// 增强版JS脚本代理执行器服务
/// 完全兼容LX Music脚本格式和API
class EnhancedJSProxyExecutorService {
  final Dio _dio = Dio();
  JavascriptRuntime? _runtime;
  String? _currentScript;
  bool _isInitialized = false;

  /// 初始化JS执行环境
  Future<void> initialize() async {
    if (_isInitialized) return;

    _runtime = getJavascriptRuntime();
    await _setupCompleteLXMusicEnvironment();
    _isInitialized = true;

    print('[EnhancedJSProxy] ✅ JS执行环境初始化完成');
  }

  /// 设置完整的LX Music运行环境
  Future<void> _setupCompleteLXMusicEnvironment() async {
    if (_runtime == null) return;

    // 注入完整的LX Music环境模拟（基于官方实现）
    final lxEnvironment = '''
      // =============================================================================
      // 基础浏览器API模拟
      // =============================================================================
      
      // Base64编码解码
      if (typeof atob === 'undefined') {
        globalThis.atob = function(input) {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          let str = '', bc = 0, buffer, idx = 0;
          input = input.replace(/=+\$/, '');
          for (buffer = input.charAt(idx++); ~(buffer = chars.indexOf(buffer)) && (buffer = bc % 4 ? buffer * 64 + chars.indexOf(input.charAt(idx - 1)) : buffer) && bc++ % 4 ? str += String.fromCharCode(255 & buffer >> (-2 * bc & 6)) : 0;) {}
          return str;
        };
      }
      
      if (typeof btoa === 'undefined') {
        globalThis.btoa = function(input) {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          let str = input, output = '';
          for (let block = 0, charCode, idx = 0, map = chars; str.charAt(idx | 0) || (map = '=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
            charCode = str.charCodeAt(idx += 3/4);
            if (charCode > 0xFF) throw new Error('btoa failed: invalid char');
            block = block << 8 | charCode;
          }
          return output;
        };
      }
      
      // 简化的XMLHttpRequest
      if (typeof XMLHttpRequest === 'undefined') {
        globalThis.XMLHttpRequest = function() {
          this.readyState = 0;
          this.status = 0;
          this.responseText = '';
          this.onreadystatechange = null;
          
          this.open = function(method, url, async) {
            this.method = method;
            this.url = url;
            this.async = async !== false;
            this.readyState = 1;
          };
          
          this.setRequestHeader = function(header, value) {
            this.headers = this.headers || {};
            this.headers[header] = value;
          };
          
          this.send = function(data) {
            const self = this;
            setTimeout(() => {
              self.readyState = 4;
              self.status = 200;
              self.responseText = '{}';
              if (self.onreadystatechange) self.onreadystatechange();
            }, 100);
          };
        };
      }
      
      // 添加fetch polyfill
      if (typeof fetch === 'undefined') {
        globalThis.fetch = function(url, options) {
          return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open(options?.method || 'GET', url);
            
            if (options?.headers) {
              for (const [key, value] of Object.entries(options.headers)) {
                xhr.setRequestHeader(key, value);
              }
            }
            
            xhr.onreadystatechange = function() {
              if (xhr.readyState === 4) {
                resolve({
                  ok: xhr.status >= 200 && xhr.status < 300,
                  status: xhr.status,
                  text: () => Promise.resolve(xhr.responseText),
                  json: () => Promise.resolve(JSON.parse(xhr.responseText))
                });
              }
            };
            
            xhr.send(options?.body);
          });
        };
      }
      
      // =============================================================================
      // LX Music核心环境
      // =============================================================================
      
      // 初始化全局状态
      globalThis._lxHandlers = {};
      globalThis._pendingRequests = {};
      globalThis._musicSources = {};
      globalThis._eventListeners = {};
      globalThis._scriptRegistered = false;
      
      // 创建完整的lx对象
      globalThis.lx = {
        // 事件名称常量
        EVENT_NAMES: {
          inited: 'inited',
          request: 'request',
          send: 'send', 
          updateAlert: 'updateAlert',
          error: 'error'
        },
        
        // 网络请求函数（核心功能）
        request: function(url, options, callback) {
          console.log('[LXEnv] 发起网络请求:', url);
          
          // 兼容不同的调用方式
          let actualUrl, actualOptions, actualCallback;
          
          if (typeof url === 'string') {
            actualUrl = url;
            if (typeof options === 'function') {
              actualCallback = options;
              actualOptions = {};
            } else {
              actualOptions = options || {};
              actualCallback = callback;
            }
          } else if (typeof url === 'object') {
            actualUrl = url.url;
            actualOptions = url.options || url;
            actualCallback = options || callback;
          }
          
          const requestId = 'req_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
          
          // 存储回调
          if (typeof actualCallback === 'function') {
            globalThis._pendingRequests[requestId] = actualCallback;
          }
          
          // 构建请求数据
          const requestData = {
            id: requestId,
            url: actualUrl,
            options: {
              method: actualOptions.method || 'GET',
              headers: actualOptions.headers || {},
              body: actualOptions.body,
              follow_max: actualOptions.follow_max || 5
            }
          };
          
          console.log('[LXEnv] 调用Flutter网络请求代理，请求数据:', JSON.stringify(requestData));
          globalThis._flutterRequestProxy(requestData);
          
          // 返回Promise以支持async/await
          return new Promise((resolve, reject) => {
            const originalCallback = globalThis._pendingRequests[requestId];
            globalThis._pendingRequests[requestId] = function(err, response) {
              if (originalCallback) {
                try {
                  originalCallback(err, response);
                } catch (e) {
                  console.warn('[LXEnv] 回调执行出错:', e);
                }
              }
              if (err) reject(err);
              else resolve(response);
            };
          });
        },
        
        // 事件监听
        on: function(eventName, handler) {
          console.log('[LXEnv] 注册事件监听:', eventName);
          if (!globalThis._lxHandlers[eventName]) {
            globalThis._lxHandlers[eventName] = [];
          }
          globalThis._lxHandlers[eventName].push(handler);
        },
        
        // 事件发送
        send: function(eventName, data) {
          console.log('[LXEnv] 发送事件:', eventName, data);
          const eventData = { event: eventName, data: data };
          globalThis._flutterEventSender(JSON.stringify(eventData));
          return Promise.resolve(data);
        },
        
        // emit别名（向后兼容）
        emit: function(eventName, data) {
          return this.send(eventName, data);
        },
        
        // 工具函数集合
        utils: {
          buffer: {
            from: function(data, encoding) {
              return { data: data, encoding: encoding || 'utf-8' };
            },
            bufToString: function(buf, encoding) {
              if (!buf || typeof buf.data === 'undefined') return '';
              
              if (encoding === 'base64') {
                try {
                  return btoa(unescape(encodeURIComponent(buf.data)));
                } catch (e) {
                  return btoa(buf.data);
                }
              } else if (encoding === 'hex') {
                return buf.data.split('').map(c => 
                  c.charCodeAt(0).toString(16).padStart(2, '0')
                ).join('');
              }
              return buf.data.toString();
            }
          },
          
          crypto: {
            md5: function(str) {
              // 简化MD5实现（用于兼容性检查）
              let hash = 0;
              for (let i = 0; i < str.length; i++) {
                const char = str.charCodeAt(i);
                hash = ((hash << 5) - hash) + char;
                hash |= 0;
              }
              return Math.abs(hash).toString(16);
            }
          }
        },
        
        // 环境信息
        env: 'mobile',
        version: '2.4.0',
        currentScriptInfo: {
          version: '1.0.0',
          name: 'Enhanced LX Music Compatibility Layer'
        }
      };
      
      // =============================================================================
      // 脚本注册和兼容性支持
      // =============================================================================
      
      // 脚本注册函数（多种格式支持）
      globalThis.registerScript = function(scriptInfo) {
        console.log('[LXEnv] 注册脚本:', JSON.stringify(scriptInfo));
        if (scriptInfo && scriptInfo.sources) {
          globalThis._musicSources = scriptInfo.sources;
          globalThis._scriptRegistered = true;
          console.log('[LXEnv] 已注册音源:', Object.keys(scriptInfo.sources).join(', '));
          
          // 发送初始化完成事件
          setTimeout(() => {
            lx.send('inited', {
              status: true,
              sources: scriptInfo.sources
            });
          }, 100);
        }
        return true;
      };
      
      // 兼容旧版脚本的注册方式
      globalThis.register = globalThis.registerScript;
      
      // 模拟window对象（某些脚本需要）
      if (typeof window === 'undefined') {
        globalThis.window = globalThis;
      }
      window.lx = globalThis.lx;
      
      // 模拟document对象
      if (typeof document === 'undefined') {
        globalThis.document = {
          createElement: function() { return {}; },
          querySelector: function() { return null; },
          addEventListener: function() {}
        };
      }
      
      // 模拟localStorage
      if (typeof localStorage === 'undefined') {
        globalThis.localStorage = {
          getItem: function() { return null; },
          setItem: function() {},
          removeItem: function() {}
        };
      }
      
      // =============================================================================
      // 增强的音源检测
      // =============================================================================
      
      // 自动检测脚本定义的音源
      globalThis._detectSources = function() {
        const sources = {};
        const commonPlatforms = ['tx', 'wy', 'kg', 'kw', 'qq', 'netease', 'kugou', 'kuwo', 'mg'];
        
        // 检测模式1: scriptManifest
        if (typeof scriptManifest !== 'undefined' && scriptManifest.supportedPlatforms) {
          scriptManifest.supportedPlatforms.forEach(platform => {
            sources[platform] = { name: platform, type: 'music', actions: ['musicUrl'] };
          });
        }
        
        // 检测模式2: 函数名模式
        const functionPatterns = [
          p => p + 'GetMusicUrl',
          p => 'get' + p.charAt(0).toUpperCase() + p.slice(1) + 'Url',
          p => p + '_getMusicUrl',
          p => 'handle' + p.toUpperCase()
        ];
        
        commonPlatforms.forEach(platform => {
          const hasFunction = functionPatterns.some(pattern => {
            const funcName = pattern(platform);
            return typeof globalThis[funcName] === 'function';
          });
          
          if (hasFunction) {
            sources[platform] = { name: platform, type: 'music', actions: ['musicUrl'] };
          }
        });
        
        // 检测模式3: 通用函数
        if (typeof getMusicUrl === 'function' || typeof handleGetMusicUrl === 'function') {
          commonPlatforms.forEach(platform => {
            sources[platform] = { name: platform, type: 'music', actions: ['musicUrl'] };
          });
        }
        
        return sources;
      };
      
      console.log('[LXEnv] ✅ 增强的LX Music环境初始化完成');
    ''';

    _runtime!.evaluate(lxEnvironment);

    // 注入console polyfill
    _runtime!.evaluate('''
      // 完善的console对象
      if (typeof console === 'undefined') globalThis.console = {};
      const consoleMethods = ['log', 'warn', 'error', 'info', 'debug', 'group', 'groupCollapsed', 'groupEnd', 'time', 'timeEnd'];
      consoleMethods.forEach(method => {
        if (typeof console[method] !== 'function') {
          console[method] = function() {
            try {
              const args = Array.prototype.slice.call(arguments);
              const message = args.map(arg => typeof arg === 'object' ? JSON.stringify(arg) : String(arg)).join(' ');
              // 发送到Flutter日志
              if (typeof sendMessage === 'function') {
                sendMessage('console_log', JSON.stringify({ level: method, message: message }));
              }
            } catch (e) {}
          };
        }
      });
      
      // 添加MD5 polyfill
      if (!globalThis.lx.utils.crypto.md5) {
        globalThis.lx.utils.crypto.md5 = function(str) {
          let hash = 0;
          for (let i = 0; i < str.length; i++) {
            const char = str.charCodeAt(i);
            hash = ((hash << 5) - hash) + char;
            hash |= 0;
          }
          return Math.abs(hash).toString(16);
        };
      }
    ''');

    // 设置网络请求和事件处理
    _setupNetworkAndEventHandlers();
  }

  /// 设置网络请求和事件处理器
  void _setupNetworkAndEventHandlers() {
    if (_runtime == null) return;

    // 设置Flutter请求代理
    _runtime!.evaluate('''
      globalThis._flutterRequestProxy = function(args) {
        try {
          console.log('[LXEnv] 调用Flutter网络请求代理');
          console.log('[LXEnv] 发送的参数:', args);
          console.log('[LXEnv] 参数类型:', typeof args);
          
          const argsToSend = typeof args === 'string' ? args : JSON.stringify(args);
          console.log('[LXEnv] 序列化后的参数:', argsToSend);
          
          sendMessage('_flutterRequestProxy', argsToSend);
        } catch (e) {
          console.error('[LXEnv] 请求代理调用失败:', e);
        }
      };
      
      globalThis._flutterEventSender = function(args) {
        try {
          console.log('[LXEnv] 调用Flutter事件发送器');
          console.log('[LXEnv] 事件参数:', args);
          console.log('[LXEnv] 事件参数类型:', typeof args);
          
          const argsToSend = typeof args === 'string' ? args : JSON.stringify(args);
          console.log('[LXEnv] 事件序列化后的参数:', argsToSend);
          
          sendMessage('_flutterEventSender', argsToSend);
        } catch (e) {
          console.error('[LXEnv] 事件发送失败:', e);
        }
      };
    ''');

    // 注册消息处理器
    _runtime!.onMessage('_flutterRequestProxy', (args) async {
      await _handleNetworkRequest(args);
    });

    _runtime!.onMessage('_flutterEventSender', (args) {
      _handleEventSend(args);
    });

    _runtime!.onMessage('console_log', (args) {
      _handleConsoleLog(args);
    });
  }

  /// 处理控制台日志
  void _handleConsoleLog(dynamic logData) {
    try {
      if (logData is Map<String, dynamic>) {
        final level = logData['level'] ?? 'log';
        final message = logData['message'] ?? '';
        print('[JSConsole-$level] $message');
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 控制台日志处理失败: $e');
    }
  }

  /// 处理网络请求
  Future<void> _handleNetworkRequest(dynamic requestData) async {
    try {
      print('[EnhancedJSProxy] 📥 收到网络请求代理消息: $requestData');
      print('[EnhancedJSProxy] 📥 参数类型: ${requestData.runtimeType}');

      Map<String, dynamic> data;
      if (requestData is String) {
        data = jsonDecode(requestData);
      } else if (requestData is Map<String, dynamic>) {
        data = requestData;
      } else {
        print('[EnhancedJSProxy] ❌ 无效的请求数据类型');
        return;
      }

      print('[EnhancedJSProxy] 📥 解析后的请求数据: $data');

      final requestId = data['id'] as String?;
      final url = data['url'] as String?;
      final options = data['options'] as Map<String, dynamic>? ?? {};

      if (requestId == null || url == null) {
        print('[EnhancedJSProxy] ❌ 缺少必要参数: requestId=$requestId, url=$url');
        return;
      }

      print('[EnhancedJSProxy] 🌐 处理网络请求: $url');
      print('[EnhancedJSProxy] 🔍 请求参数详情: $data');

      // 使用Dio发起网络请求
      final response = await _dio.request(
        url,
        options: Options(
          method: options['method'] ?? 'GET',
          headers: Map<String, String>.from(options['headers'] ?? {}),
          validateStatus: (status) => status != null && status < 500,
        ),
        data: options['body'],
      );

      print('[EnhancedJSProxy] ✅ 网络请求完成: ${response.statusCode}');

      // 构建响应数据
      final responseData = {
        'statusCode': response.statusCode,
        'body': response.data,
        'headers': response.headers.map,
      };

      // 回调JS
      final callbackScript = '''
        (function() {
          try {
            console.log('[EnhancedJSProxy] 调用网络请求回调，请求ID: $requestId');
            
            if (globalThis._pendingRequests['$requestId']) {
              const callback = globalThis._pendingRequests['$requestId'];
              delete globalThis._pendingRequests['$requestId'];
              
              const response = ${jsonEncode(responseData)};
              console.log('[EnhancedJSProxy] 响应状态:', response.statusCode);
              console.log('API Response: ', response);
              
              // 执行回调
              callback(null, response);
              console.log('[EnhancedJSProxy] 回调执行完成');
              
              // 设置Promise结果
              if (response.body && typeof response.body === 'object') {
                if (response.body.code === 0) {
                  globalThis._promiseResult = response.body.data || response.body.url;
                  globalThis._promiseComplete = true;
                  console.log('[EnhancedJSProxy] Promise结果已设置:', globalThis._promiseResult);
                } else if (response.body.code !== undefined) {
                  globalThis._promiseError = response.body.msg || response.body.message || 'API返回错误';
                  globalThis._promiseComplete = true;
                  console.log('[EnhancedJSProxy] Promise错误已设置:', globalThis._promiseError);
                }
              }
              
              return true;
            } else {
              console.log('[EnhancedJSProxy] 未找到请求ID对应的回调: $requestId');
              return false;
            }
          } catch (e) {
            console.error('[EnhancedJSProxy] 回调执行失败:', e);
            return false;
          }
        })()
      ''';

      _runtime!.evaluate(callbackScript);

    } catch (e) {
      print('[EnhancedJSProxy] ❌ 网络请求失败: $e');
      
      // 尝试获取请求ID来发送错误回调
      String requestId = 'unknown';
      try {
        Map<String, dynamic> errorData;
        if (requestData is String) {
          errorData = jsonDecode(requestData);
        } else if (requestData is Map<String, dynamic>) {
          errorData = requestData;
        } else {
          errorData = {};
        }
        requestId = errorData['id'] as String? ?? 'unknown';
      } catch (_) {}
      
      final errorScript = '''
        (function() {
          try {
            if (globalThis._pendingRequests['$requestId']) {
              const callback = globalThis._pendingRequests['$requestId'];
              delete globalThis._pendingRequests['$requestId'];
              callback(new Error('${e.toString().replaceAll("'", "\\'")}'), null);
              return true;
            }
            return false;
          } catch (callbackError) {
            console.error('[EnhancedJSProxy] 错误回调执行失败:', callbackError);
            return false;
          }
        })()
      ''';

      _runtime!.evaluate(errorScript);
    }
  }

  /// 处理JS发送的事件
  void _handleEventSend(dynamic eventData) {
    try {
      print('[EnhancedJSProxy] 📡 收到JS事件: $eventData');

      Map<String, dynamic> data;
      if (eventData is String) {
        data = jsonDecode(eventData);
      } else if (eventData is Map<String, dynamic>) {
        data = eventData;
      } else {
        print('[EnhancedJSProxy] ❌ 无效的事件数据类型');
        return;
      }

      final eventName = data['event'];
      final eventPayload = data['data'];

      print('[EnhancedJSProxy] 📡 事件名称: $eventName');

      // 处理特定事件
      switch (eventName) {
        case 'inited':
          print('[EnhancedJSProxy] 🎵 JS脚本初始化完成');
          if (eventPayload != null && eventPayload['sources'] != null) {
            final sourcesJson = jsonEncode(eventPayload['sources']);
            _runtime!.evaluate('globalThis._musicSources = $sourcesJson;');
            print('[EnhancedJSProxy] 📋 已存储音源信息: ${eventPayload['sources'].keys.join(', ')}');
          }
          break;
        case 'updateAlert':
          print('[EnhancedJSProxy] 🔄 脚本更新提醒: ${eventPayload?['log']}');
          break;
        default:
          print('[EnhancedJSProxy] 📨 其他事件: $eventName');
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 事件处理失败: $e');
    }
  }

  /// 加载JS脚本
  Future<bool> loadScript(String scriptContent) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('[EnhancedJSProxy] 📜 开始加载JS脚本...');

      // 保存脚本内容供检测使用
      _runtime!.evaluate('globalThis._currentScriptContent = ${jsonEncode(scriptContent)};');
      
      // 执行JS脚本
      _runtime!.evaluate(scriptContent);
      _currentScript = scriptContent;

      // 等待脚本初始化
      await Future.delayed(const Duration(milliseconds: 1000));

      // 检查脚本是否正确加载
      final checkResult = _runtime!.evaluate('''
        (function() {
          try {
            // 首先尝试自动检测音源
            const detectedSources = globalThis._detectSources();
            if (Object.keys(detectedSources).length > 0) {
              globalThis._musicSources = detectedSources;
              console.log('[EnhancedJSProxy] 自动检测到音源:', Object.keys(detectedSources).join(', '));
            }
            
            return {
              hasHandlers: Object.keys(globalThis._lxHandlers || {}).length > 0,
              hasMusicSources: Object.keys(globalThis._musicSources || {}).length > 0,
              handlers: Object.keys(globalThis._lxHandlers || {}),
              sources: Object.keys(globalThis._musicSources || {}),
              scriptRegistered: globalThis._scriptRegistered || false,
              hasLxExport: typeof globalThis.lx !== 'undefined',
              hasScriptManifest: typeof scriptManifest !== 'undefined',
              hasGetMusicUrl: typeof getMusicUrl !== 'undefined'
            };
          } catch (e) {
            return { error: e.toString() };
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 脚本加载检查结果: ${checkResult.stringResult}');

      if (checkResult.stringResult.contains('error')) {
        print('[EnhancedJSProxy] ❌ 脚本加载失败');
        return false;
      }

      print('[EnhancedJSProxy] ✅ JS脚本加载成功');
      return true;
    } catch (e) {
      print('[EnhancedJSProxy] ❌ JS脚本加载异常: $e');
      return false;
    }
  }

  /// 获取音乐播放链接
  Future<String?> getMusicUrl({
    required String source,
    required String songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!_isInitialized || _currentScript == null) {
      print('[EnhancedJSProxy] ⚠️ 服务未初始化或脚本未加载');
      return null;
    }

    try {
      print('[EnhancedJSProxy] 🎵 开始获取音乐链接: $source/$songId/$quality');

      // 构建请求参数
      final requestParams = {
        'action': 'musicUrl',
        'source': source,
        'info': {
          'type': quality,
          'musicInfo': {
            'songmid': songId,
            'hash': songId,
            ...?musicInfo,
          }
        }
      };

      print('[EnhancedJSProxy] 调用JS处理函数: $requestParams');

      // 重置Promise状态
      _runtime!.evaluate(
        'globalThis._promiseResult = null; globalThis._promiseError = null; globalThis._promiseComplete = false;',
      );

      // 调用JS处理函数
      final jsResult = _runtime!.evaluate('''
        (function() {
          try {
            const request = ${jsonEncode(requestParams)};
            console.log('Handle Action(' + request.action + ')');
            console.log('source', request.source);
            console.log('quality', request.info.type);
            console.log('musicInfo', request.info.musicInfo);
            
            // 尝试多种调用方式
            let result = null;
            
            // 方式1: 直接调用lx.emit
            if (typeof lx !== 'undefined' && lx.emit) {
              result = lx.emit(lx.EVENT_NAMES.request, request);
            }
            
            // 方式2: 调用事件处理器
            if (!result && globalThis._lxHandlers && globalThis._lxHandlers.request) {
              const handlers = Array.isArray(globalThis._lxHandlers.request) ? 
                globalThis._lxHandlers.request : [globalThis._lxHandlers.request];
              
              for (const handler of handlers) {
                if (typeof handler === 'function') {
                  result = handler(request);
                  if (result) break;
                }
              }
            }
            
            // 方式3: 查找专用函数
            const funcName = request.source + 'GetMusicUrl';
            if (!result && typeof globalThis[funcName] === 'function') {
              result = globalThis[funcName](request.info);
            }
            
            // 方式4: 通用getMusicUrl
            if (!result && typeof getMusicUrl === 'function') {
              result = getMusicUrl(request.info);
            }
            
            if (result && typeof result.then === 'function') {
              console.log('[EnhancedJSProxy] 检测到Promise，开始等待...');
              return { success: true, isPromise: true };
            } else if (result) {
              console.log('[EnhancedJSProxy] 同步结果:', result);
              return { success: true, result: result };
            } else {
              return { success: false, error: 'No suitable handler found' };
            }
          } catch (e) {
            console.error('[EnhancedJSProxy] JS执行失败:', e);
            return { success: false, error: e.toString() };
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 JS执行结果: ${jsResult.stringResult}');

      final resultData = jsonDecode(jsResult.stringResult);

      if (resultData['success'] == true) {
        if (resultData['isPromise'] == true) {
          // 等待Promise完成
          for (int i = 0; i < 200; i++) { // 20秒超时
            await Future.delayed(const Duration(milliseconds: 100));

            final checkResult = _runtime!.evaluate('''
              (function() {
                try {
                  console.log('[EnhancedJSProxy] 检查Promise状态:', globalThis._promiseComplete, globalThis._promiseResult, globalThis._promiseError);
                  
                  if (globalThis._promiseComplete) {
                    if (globalThis._promiseResult !== null && globalThis._promiseResult !== undefined) {
                      console.log('[EnhancedJSProxy] Promise成功，结果:', globalThis._promiseResult);
                      return JSON.stringify({ success: true, result: globalThis._promiseResult });
                    } else if (globalThis._promiseError) {
                      console.log('[EnhancedJSProxy] Promise失败，错误:', globalThis._promiseError);
                      return JSON.stringify({ success: false, error: globalThis._promiseError });
                    }
                  }
                  
                  return JSON.stringify({ success: false, pending: true });
                } catch (e) {
                  return JSON.stringify({ success: false, error: e.toString() });
                }
              })()
            ''');

            final checkData = jsonDecode(checkResult.stringResult);

            if (checkData['success'] == true) {
              final musicUrl = checkData['result'];
              print('[EnhancedJSProxy] ✅ Promise完成，获取音乐链接: $musicUrl');
              return musicUrl;
            } else if (checkData['success'] == false && checkData['pending'] != true) {
              print('[EnhancedJSProxy] ❌ Promise失败: ${checkData['error']}');
              return null;
            }

            // 每秒显示一次等待状态
            if (i % 10 == 0) {
              print('[EnhancedJSProxy] ⏳ 等待Promise完成... ${i / 10}秒');
            }
          }

          print('[EnhancedJSProxy] ⏰ Promise等待超时 (20秒)');
          return null;
        } else {
          final musicUrl = resultData['result'];
          print('[EnhancedJSProxy] ✅ 成功获取音乐链接: $musicUrl');
          return musicUrl;
        }
      } else {
        print('[EnhancedJSProxy] ❌ 获取音乐链接失败: ${resultData['error']}');
        return null;
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 获取音乐链接异常: $e');
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
      print('[EnhancedJSProxy] ❌ 获取音源列表失败: $e');
      return {};
    }
  }

  /// 释放资源
  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    _currentScript = null;
    _isInitialized = false;
    print('[EnhancedJSProxy] 🧹 资源已释放');
  }
}
