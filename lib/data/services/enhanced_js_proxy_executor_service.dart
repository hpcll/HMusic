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
          
          // 兼容：也存储到事件监听器列表
          if (!globalThis._eventListeners[eventName]) {
            globalThis._eventListeners[eventName] = [];
          }
          globalThis._eventListeners[eventName].push(handler);
        },
        
        // 事件发送（发送到Flutter）
        send: function(eventName, data) {
          console.log('[LXEnv] 发送事件到Flutter:', eventName, data);
          const eventData = { event: eventName, data: data };
          globalThis._flutterEventSender(JSON.stringify(eventData));
          return Promise.resolve(data);
        },
        
        // emit别名（向后兼容）
        emit: function(eventName, data) {
          try {
            if (typeof globalThis._dispatchEventToScript === 'function') {
              return globalThis._dispatchEventToScript(eventName, data);
            }
            return null;
          } catch (e) {
            console.warn('[LXEnv] emit 分发失败:', e);
            return null;
          }
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
      // 🔥 关键修复：确保window.lx指向正确的lx对象
      window.lx = globalThis.lx;
      
      // 🔥 同时确保window上也有这些函数的直接访问
      window.EVENT_NAMES = globalThis.lx.EVENT_NAMES;
      window.request = globalThis.lx.request;
      window.on = globalThis.lx.on;
      window.send = globalThis.lx.send;
      window.emit = globalThis.lx.emit;
      window.utils = globalThis.lx.utils;
      window.env = globalThis.lx.env;
      window.version = globalThis.lx.version;
      
      // 内部事件分发器：分发事件到脚本内已注册的处理器
      globalThis._dispatchEventToScript = function(eventName, data) {
        try {
          console.log('[LXEnv] 分发事件到脚本:', eventName, data);
          const handlers = globalThis._lxHandlers && globalThis._lxHandlers[eventName]
            ? (Array.isArray(globalThis._lxHandlers[eventName]) ? globalThis._lxHandlers[eventName] : [globalThis._lxHandlers[eventName]])
            : [];
          let lastResult = null;
          for (const handler of handlers) {
            if (typeof handler === 'function') {
              try {
                const r = handler(data);
                lastResult = r !== undefined ? r : lastResult;
              } catch (e) {
                console.warn('[LXEnv] 分发事件处理器执行出错:', e);
              }
            }
          }
          return lastResult;
        } catch (e) {
          console.warn('[LXEnv] 分发事件出错:', e);
          return null;
        }
      };
      
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

      // 🔥 关键修复：将lx对象的函数暴露到全局作用域
      // 这样脚本可以使用: const { EVENT_NAMES, request, on, send, utils, env, version } = globalThis.lx
      globalThis.EVENT_NAMES = globalThis.lx.EVENT_NAMES;
      globalThis.request = globalThis.lx.request;
      globalThis.on = globalThis.lx.on;
      globalThis.send = globalThis.lx.send;
      globalThis.emit = globalThis.lx.emit;
      globalThis.utils = globalThis.lx.utils;
      globalThis.env = globalThis.lx.env;
      globalThis.version = globalThis.lx.version;
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
              console.log('[EnhancedJSProxy] 📊 [HTTP层] statusCode=' + response.statusCode + ' (200=成功,404=未找到,500=服务器错误)');
              console.log('[EnhancedJSProxy] 📦 [响应体] body=' + JSON.stringify(response.body));

              // 🔧 关键修复：为不同脚本提供兼容的响应格式
              // 有些脚本期望直接收到 body，有些期望收到完整的 response 对象
              // 我们同时提供两种格式，让回调函数选择使用
              const compatResponse = {
                ...response,
                // 提供直接访问 body 的快捷方式
                data: response.body,
                // 兼容性：如果 body 是对象，将其属性展开到 response 上
                ...(typeof response.body === 'object' ? response.body : {})
              };

              console.log('[EnhancedJSProxy] 🔍 [兼容层] 脚本可用的访问方式:');
              console.log('  response.statusCode =', compatResponse.statusCode, '← [HTTP层状态码] (200=HTTP成功)');
              console.log('  response.body =', JSON.stringify(compatResponse.body), '← [原始响应体]');
              console.log('  response.data =', JSON.stringify(compatResponse.data), '← [快捷访问=body]');

              // 检查业务状态码
              if (compatResponse.body && typeof compatResponse.body === 'object' && compatResponse.body.code !== undefined) {
                console.log('  response.code =', compatResponse.code, '← [业务层状态码] (从body展开,0=业务成功)');
                console.log('  ⚠️  重要: HTTP成功(200) ≠ 业务成功,需检查 code 值判断业务结果!');
              }

              // 执行回调（优先使用兼容格式）
              callback(null, compatResponse);
              console.log('[EnhancedJSProxy] 回调执行完成');

              // ✨ 双保险机制：如果 Promise 还没设置结果，网络回调作为后备
              // 策略：不判断具体的 code 值，只检查是否有有效结果
              // 让 JS 脚本负责业务逻辑判断，Flutter 只做快速缓存
              if (!globalThis._promiseComplete && compatResponse.body && typeof compatResponse.body === 'object') {
                // 尝试提取可能的结果字段
                const result = compatResponse.body.data || compatResponse.body.url || compatResponse.body.result;

                if (result && typeof result === 'string' && result.length > 0) {
                  // 有明确的字符串结果，设置快速路径
                  globalThis._promiseResult = result;
                  globalThis._promiseComplete = true;
                  console.log('[EnhancedJSProxy] 🚀 快速路径: 检测到有效结果');
                }
                // 注意：不设置错误，让 JS Promise 自己判断失败情况
                // 因为我们不知道什么 code 代表失败
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
            print(
              '[EnhancedJSProxy] 📋 已存储音源信息: ${eventPayload['sources'].keys.join(', ')}',
            );
          }
          break;
        case 'updateAlert':
          print('[EnhancedJSProxy] 🔄 脚本更新提醒: ${eventPayload?['log']}');
          break;
        case 'request':
          print('[EnhancedJSProxy] 🔄 收到request事件，但现在直接在JS中处理');
          // 不需要额外处理，JS中已经直接调用了事件处理器
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

      // 为避免上次脚本遗留的全局函数影响当前脚本，重置JS运行时并重新注入环境
      try {
        print('[EnhancedJSProxy] ♻️ 重置JS运行时，清理旧脚本环境');
        _runtime?.dispose();
        _runtime = getJavascriptRuntime();
        await _setupCompleteLXMusicEnvironment();
      } catch (e) {
        print('[EnhancedJSProxy] ⚠️ 重置JS运行时失败，继续使用现有环境: $e');
      }

      // 保存脚本内容供检测使用
      _runtime!.evaluate(
        'globalThis._currentScriptContent = ${jsonEncode(scriptContent)};',
      );

      // 执行JS脚本
      print('[EnhancedJSProxy] 🚀 执行脚本内容，长度: ${scriptContent.length} 字符');
      print(
        '[EnhancedJSProxy] 🚀 脚本前100字符: ${scriptContent.substring(0, scriptContent.length > 100 ? 100 : scriptContent.length)}',
      );

      _runtime!.evaluate(scriptContent);
      _currentScript = scriptContent;

      // 立即触发一次 inited 到脚本（部分官方脚本在收到 inited 后注册处理器）
      try {
        _runtime!.evaluate(
          "typeof _dispatchEventToScript === 'function' && _dispatchEventToScript('inited', { status: true });",
        );
      } catch (_) {}

      // 试探性调用常见入口函数，促进脚本完成自注册
      try {
        _runtime!.evaluate('''
          (function() {
            const candidates = [
              'main', 'init', 'initialize', 'bootstrap', 'start', 'setup',
              'registerSource', 'registerScript', 'lxInit'
            ];
            candidates.forEach(name => {
              try {
                if (typeof globalThis[name] === 'function') {
                  console.log('[LXEnv] 调用入口函数:', name);
                  try { globalThis[name](); } catch (e) { console.log('[LXEnv] 入口函数调用失败:', name, e && e.message); }
                }
              } catch (e) {}
            });
            if (typeof window !== 'undefined' && window.lx && typeof window.lx.init === 'function') {
              console.log('[LXEnv] 调用 window.lx.init');
              try { window.lx.init(); } catch (e) { console.log('[LXEnv] window.lx.init 调用失败:', e && e.message); }
            }
          })()
        ''');
      } catch (_) {}

      // 延迟再次触发一次 inited，给脚本留出注册时间
      try {
        _runtime!.evaluate(
          'setTimeout(function(){ try { if (typeof _dispatchEventToScript === "function") _dispatchEventToScript("inited", { status: true, delayed: true }); } catch(e){} }, 500);',
        );
      } catch (_) {}

      // 🔥 立即检查脚本执行后的状态（增强版诊断）
      final immediateCheck = _runtime!.evaluate('''
        JSON.stringify({
          // 基础环境检查
          globalThisKeys: Object.keys(globalThis).filter(k => k.includes('lx') || k.includes('on') || k.includes('EVENT')),
          windowKeys: typeof window !== 'undefined' ? Object.keys(window).filter(k => k.includes('lx') || k.includes('on') || k.includes('EVENT')) : null,
          lxKeys: globalThis.lx ? Object.keys(globalThis.lx) : null,
          windowLxKeys: typeof window !== 'undefined' && window.lx ? Object.keys(window.lx) : null,
          handlersAfterScript: globalThis._lxHandlers,
          hasOnFunction: typeof globalThis.on === 'function',
          hasWindowLx: typeof window !== 'undefined' && typeof window.lx !== 'undefined',
          hasWindowOn: typeof window !== 'undefined' && typeof window.lx !== 'undefined' && typeof window.lx.on === 'function',

          // 🔥 混淆脚本专项检查
          obfuscationCheck: {
            // 检查常见混淆变量名
            hasShortVars: {
              r: typeof globalThis.r !== 'undefined' ? typeof globalThis.r : null,
              t: typeof globalThis.t !== 'undefined' ? typeof globalThis.t : null,
              e: typeof globalThis.e !== 'undefined' ? typeof globalThis.e : null,
              o: typeof globalThis.o !== 'undefined' ? typeof globalThis.o : null,
              k: typeof globalThis.k !== 'undefined' ? typeof globalThis.k : null,
            },
            // 检查解构赋值是否成功
            lxAccessible: typeof globalThis.lx !== 'undefined',
            lxType: typeof globalThis.lx,
            lxIsObject: typeof globalThis.lx === 'object',
            lxHasOn: globalThis.lx && typeof globalThis.lx.on === 'function',
            lxHasRequest: globalThis.lx && typeof globalThis.lx.request === 'function',
            // 检查脚本是否尝试调用 on() 注册事件
            attemptedRegistration: globalThis._lxHandlers && Object.keys(globalThis._lxHandlers).length > 0,
            // 🔧 检查是否通过解构赋值创建了 r 变量（野花音源.js的模式）
            rIsFunction: typeof globalThis.r === 'function',
            rEqualsOn: globalThis.r === globalThis.on || (globalThis.lx && globalThis.r === globalThis.lx.on),
            // 🔧 检查脚本的混淆模式
            hasHexEncoding: (function() {
              try {
                // 检查脚本源码是否包含十六进制编码（形如 \\x6c 的模式）
                const scriptContent = globalThis._currentScriptContent || '';
                return scriptContent.includes('\\\\x');
              } catch(e) { return false; }
            })(),
          },

          scriptExecuted: true
        }, null, 2)
      ''');
      print('[EnhancedJSProxy] 🔍 脚本执行后立即检查:\n${immediateCheck.stringResult}');

      // 🚀 自动修复：如果检测到混淆脚本使用了解构赋值但未成功注册处理器
      try {
        final checkData = jsonDecode(immediateCheck.stringResult) as Map<String, dynamic>;
        final obfuscationCheck = checkData['obfuscationCheck'] as Map<String, dynamic>?;
        final attemptedRegistration = obfuscationCheck?['attemptedRegistration'] == true;
        final rIsFunction = obfuscationCheck?['rIsFunction'] == true;

        print('[EnhancedJSProxy] 🔍 混淆检测结果: rIsFunction=$rIsFunction, attemptedRegistration=$attemptedRegistration');

        if (rIsFunction && !attemptedRegistration) {
          print('[EnhancedJSProxy] 🔧 检测到混淆脚本使用解构赋值但未注册处理器');
          print('[EnhancedJSProxy] 🔧 可能原因：脚本使用了异步注册或setTimeout延迟注册');

          // 🔥 核心修复：手动触发一次 inited 事件到所有可能的监听器
          _runtime!.evaluate('''
            (function() {
              try {
                console.log('[EnhancedJSProxy-AutoFix] 尝试触发延迟注册...');

                // 方式1: 如果脚本定义了 r 变量（解构赋值的 on 函数）
                if (typeof globalThis.r === 'function') {
                  console.log('[EnhancedJSProxy-AutoFix] 发现 r 变量，尝试通过它触发注册');
                  // 检查是否有未注册的监听器
                  if (typeof globalThis.e === 'object' && globalThis.e.inited) {
                    console.log('[EnhancedJSProxy-AutoFix] 触发 inited 事件');
                    // 模拟脚本可能需要的初始化事件
                  }
                }

                // 方式2: 检查是否有全局的初始化函数
                const initFunctions = ['init', 'initialize', 'onInit', 'onReady', 'ready'];
                for (const fname of initFunctions) {
                  if (typeof globalThis[fname] === 'function') {
                    console.log('[EnhancedJSProxy-AutoFix] 调用初始化函数:', fname);
                    try {
                      globalThis[fname]();
                    } catch (e) {
                      console.log('[EnhancedJSProxy-AutoFix] 初始化函数执行失败:', e.message);
                    }
                  }
                }

                console.log('[EnhancedJSProxy-AutoFix] 延迟注册触发完成');
                return true;
              } catch (e) {
                console.error('[EnhancedJSProxy-AutoFix] 触发延迟注册失败:', e);
                return false;
              }
            })()
          ''');

          // 等待脚本完成异步初始化（某些混淆脚本可能在setTimeout中注册）
          await Future.delayed(const Duration(milliseconds: 800));

          // 再次检查是否成功注册
          final delayedCheck = _runtime!.evaluate('''
            JSON.stringify({
              handlersAfterDelay: globalThis._lxHandlers,
              requestHandlerCount: globalThis._lxHandlers && globalThis._lxHandlers.request ?
                (Array.isArray(globalThis._lxHandlers.request) ? globalThis._lxHandlers.request.length : 1) : 0,
              allHandlerKeys: globalThis._lxHandlers ? Object.keys(globalThis._lxHandlers) : []
            })
          ''');
          print('[EnhancedJSProxy] 🔍 延迟后再次检查: ${delayedCheck.stringResult}');
        }
      } catch (e) {
        print('[EnhancedJSProxy] ⚠️ 混淆脚本检测失败（继续执行）: $e');
      }

      // 等待脚本初始化
      await Future.delayed(const Duration(milliseconds: 1000));

      // 再次检查是否已注册处理器
      final delayedCheck = _runtime!.evaluate('''
        JSON.stringify({
          requestHandlerCount: globalThis._lxHandlers && globalThis._lxHandlers.request ? 
            (Array.isArray(globalThis._lxHandlers.request) ? globalThis._lxHandlers.request.length : 1) : 0,
          handlers: globalThis._lxHandlers
        })
      ''');
      print('[EnhancedJSProxy] 🔍 脚本延迟检查: ${delayedCheck.stringResult}');

      // 如果仍未注册request处理器，自动注入兼容处理器
      try {
        final needCompat = _runtime!.evaluate('''
          (function(){
            try {
              const count = (globalThis._lxHandlers && globalThis._lxHandlers.request) ?
                (Array.isArray(globalThis._lxHandlers.request) ? globalThis._lxHandlers.request.length : 1) : 0;
              return count === 0;
            } catch(e) { return true; }
          })()
        ''');
        if (needCompat.rawResult == true) {
          print('[EnhancedJSProxy] ♻️ 注入兼容request处理器');
          _runtime!.evaluate('''
            (function(){
              try {
                if (!globalThis._lxHandlers) globalThis._lxHandlers = {};
                if (!globalThis._lxHandlers.request) globalThis._lxHandlers.request = [];
                
                const compatHandler = function(request){
                  try {
                    let result = null;
                    const src = request && request.source;
                    const info = request && request.info;
                    const musicInfo = info && info.musicInfo;
                    const quality = info && info.type;
                    
                    // 1) 严格优先：你的标准签名 (source, musicInfo, quality)
                    if (typeof handleGetMusicUrl === 'function') {
                      try { result = handleGetMusicUrl(src, musicInfo, quality); } catch(_) {}
                    }
                    if (!result && typeof getMusicUrl === 'function') {
                      try { result = getMusicUrl(src, musicInfo, quality); } catch(_) {}
                    }
                    
                    // 2) 其次：常见双参 (musicInfo, quality)
                    if (!result && typeof handleGetMusicUrl === 'function') {
                      try { result = handleGetMusicUrl(musicInfo, quality); } catch(_) {}
                    }
                    if (!result && typeof getMusicUrl === 'function') {
                      try { result = getMusicUrl(musicInfo, quality); } catch(_) {}
                    }
                    
                    // 3) 最后再尝试单参 info（旧实现）
                    if (!result && typeof handleGetMusicUrl === 'function') {
                      try { result = handleGetMusicUrl(info); } catch(_) {}
                    }
                    if (!result && typeof getMusicUrl === 'function') {
                      try { result = getMusicUrl(info); } catch(_) {}
                    }
                    
                    // 4) 平台特定函数名模式
                    if (!result) {
                      const names = [
                        request.source + 'GetMusicUrl',
                        'get' + request.source.toUpperCase() + 'Url',
                        request.source + '_getMusicUrl',
                        request.source + 'Music',
                        'handle' + request.source.toUpperCase() + 'Url',
                        request.source.toUpperCase() + '_MUSIC_URL'
                      ];
                      for (const n of names) {
                        if (typeof globalThis[n] === 'function') { 
                          let r = null;
                          try { r = globalThis[n](src, musicInfo, quality); } catch(_) {}
                          if (!r) { try { r = globalThis[n](musicInfo, quality); } catch(_) {} }
                          if (!r) { try { r = globalThis[n](info); } catch(_) {} }
                          if (r) { result = r; break; }
                        }
                      }
                    }
                    
                    // 5) 对象风格
                    if (!result && typeof apis === 'object' && apis && apis[request.source] && typeof apis[request.source].musicUrl === 'function') {
                      const q = quality; const mi = musicInfo;
                      let r = null; try { r = apis[request.source].musicUrl(mi, q); } catch(_) {}
                      if (!r) { try { r = apis[request.source].musicUrl(info); } catch(_) {} }
                      if (r) result = r;
                    }
                    if (!result && typeof sources === 'object' && sources && sources[request.source] && typeof sources[request.source].musicUrl === 'function') {
                      let r = null; try { r = sources[request.source].musicUrl(src, musicInfo, quality); } catch(_) {}
                      if (!r) { try { r = sources[request.source].musicUrl(musicInfo, quality); } catch(_) {} }
                      if (!r) { try { r = sources[request.source].musicUrl(info); } catch(_) {} }
                      if (r) result = r;
                    }
                    
                    // 6) 兜底扫描
                    if (!result) {
                      const allFunctions = Object.getOwnPropertyNames(globalThis).filter(name => 
                        typeof globalThis[name] === 'function' &&
                        (name.toLowerCase().includes('music') || name.toLowerCase().includes('url') || name.toLowerCase().includes(request.source.toLowerCase()))
                      );
                      for (const fn of allFunctions) {
                        let r = null;
                        try { r = globalThis[fn](src, musicInfo, quality); } catch(_) {}
                        if (!r) { try { r = globalThis[fn](musicInfo, quality); } catch(_) {} }
                        if (!r) { try { r = globalThis[fn](info || request); } catch(_) {} }
                        if (r) { result = r; break; }
                      }
                    }
                    
                    return result;
                  } catch(e) { console.warn('[CompatHandler] 执行失败:', e); return null; }
                };
                
                globalThis._lxHandlers.request.push(compatHandler);
                return true;
              } catch (e) { return false; }
            })()
          ''');
        }
      } catch (_) {}

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
              hasGetMusicUrl: typeof getMusicUrl !== 'undefined',
              // 详细调试信息
              requestHandlers: globalThis._lxHandlers ? globalThis._lxHandlers.request : null,
              requestHandlerCount: globalThis._lxHandlers && globalThis._lxHandlers.request ? 
                (Array.isArray(globalThis._lxHandlers.request) ? globalThis._lxHandlers.request.length : 1) : 0,
              onFunctionExists: typeof globalThis.on === 'function',
              lxOnExists: globalThis.lx && typeof globalThis.lx.on === 'function',
              allHandlers: globalThis._lxHandlers
            };
          } catch (e) {
            return { error: e.toString() };
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 脚本加载检查结果: ${checkResult.stringResult}');

      // 仅当顶层存在 error 字段时判定失败，避免因 handler 源码中的 console.error 误判
      bool hasTopLevelError = false;
      try {
        final Map<String, dynamic> parsed = jsonDecode(
          checkResult.stringResult,
        );
        hasTopLevelError =
            parsed.containsKey('error') && parsed['error'] != null;
      } catch (_) {
        // 如果解析失败，不据此判失败
        hasTopLevelError = false;
      }

      if (hasTopLevelError) {
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
          'musicInfo': {'songmid': songId, 'hash': songId, ...?musicInfo},
        },
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
            
            // 方式1: 调用已注册的request事件处理器（主要方式）
            if (globalThis._lxHandlers && globalThis._lxHandlers.request) {
              console.log('[EnhancedJSProxy] 尝试调用已注册的request事件处理器');
              const handlers = Array.isArray(globalThis._lxHandlers.request) ? 
                globalThis._lxHandlers.request : [globalThis._lxHandlers.request];
              
              console.log('[EnhancedJSProxy] 找到', handlers.length, '个request处理器');
              
              for (const handler of handlers) {
                if (typeof handler === 'function') {
                  console.log('[EnhancedJSProxy] 调用处理器，参数:', request);
                  result = handler(request);
                  console.log('[EnhancedJSProxy] 处理器返回:', result);
                  if (result) break;
                }
              }
            }
            
            // 方式1.5: 通过 lx.emit 触发（如果脚本使用官方事件模型）
            if (!result && typeof lx !== 'undefined' && typeof lx.emit === 'function') {
              console.log('[EnhancedJSProxy] 尝试通过 lx.emit 分发 request');
              result = lx.emit(lx.EVENT_NAMES.request, request);
              console.log('[EnhancedJSProxy] lx.emit 返回:', result);
            }
            
            // 方式2: 使用内部分发器
            if (!result && typeof _dispatchEventToScript === 'function') {
              console.log('[EnhancedJSProxy] 尝试通过内部分发器分发 request');
              result = _dispatchEventToScript('request', request);
              console.log('[EnhancedJSProxy] 内部分发器返回:', result);
            }
            
            // 方式3: 查找专用函数 (多种命名模式)
            const platformFunctions = [
              request.source + 'GetMusicUrl',     // txGetMusicUrl
              'get' + request.source.toUpperCase() + 'Url',  // getTXUrl
              request.source + '_getMusicUrl',    // tx_getMusicUrl
              request.source + 'Music',           // txMusic
              'handle' + request.source.toUpperCase() + 'Url', // handleTXUrl
              request.source.toUpperCase() + '_MUSIC_URL'      // TX_MUSIC_URL
            ];
            
            for (const funcName of platformFunctions) {
              if (!result && typeof globalThis[funcName] === 'function') {
                console.log('[EnhancedJSProxy] 尝试调用专用函数:', funcName);
                result = globalThis[funcName](request.info);
                console.log('[EnhancedJSProxy] 专用函数返回:', result);
                if (result) break;
              }
            }
            
            // 方式4: 通用getMusicUrl
            if (!result && typeof getMusicUrl === 'function') {
              console.log('[EnhancedJSProxy] 尝试调用通用 getMusicUrl');
              result = getMusicUrl(request.info);
              console.log('[EnhancedJSProxy] getMusicUrl 返回:', result);
            }
            
            // 方式5: 检查脚本是否定义了处理函数
            if (!result) {
              console.log('[EnhancedJSProxy] 检查脚本中的处理函数...');
              const possibleHandlers = [
                'handleRequest',
                'processRequest', 
                'handleMusicUrl',
                'musicUrlHandler',
                'getUrl',
                'resolveUrl'
              ];
              
              for (const handlerName of possibleHandlers) {
                if (typeof globalThis[handlerName] === 'function') {
                  console.log('[EnhancedJSProxy] 尝试调用处理函数:', handlerName);
                  result = globalThis[handlerName](request);
                  console.log('[EnhancedJSProxy] 处理函数返回:', result);
                  if (result) break;
                }
              }
            }
            
            // 方式6: 查找任何可能的音乐URL获取函数
            if (!result) {
              console.log('[EnhancedJSProxy] 最后尝试：查找所有可能的函数...');
              const allFunctions = Object.getOwnPropertyNames(globalThis).filter(name =>
                typeof globalThis[name] === 'function' &&
                (name.toLowerCase().includes('music') ||
                 name.toLowerCase().includes('url') ||
                 name.toLowerCase().includes(request.source.toLowerCase()))
              );
              console.log('[EnhancedJSProxy] 找到可能的函数:', allFunctions);

              for (const funcName of allFunctions) {
                try {
                  result = globalThis[funcName](request.info || request);
                  console.log('[EnhancedJSProxy] 函数', funcName, '返回:', result);
                  if (result) break;
                } catch (e) {
                  console.log('[EnhancedJSProxy] 函数', funcName, '调用失败:', e.message);
                }
              }
            }

            if (result && typeof result.then === 'function') {
              console.log('[EnhancedJSProxy] 检测到Promise，开始等待...');
              try {
                result.then(function(v){
                  try {
                    console.log('[EnhancedJSProxy] 📦 JS脚本返回结果(Promise resolved):', JSON.stringify(v));
                    globalThis._promiseResult = v;
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                }).catch(function(err){
                  try {
                    console.log('[EnhancedJSProxy] ❌ JS脚本返回错误(Promise rejected):', err);
                    globalThis._promiseError = (err && (err.message || err.toString())) || 'Unknown error';
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                });
              } catch (e) { console.log('[EnhancedJSProxy] 绑定Promise回调失败:', e && e.message); }
              return JSON.stringify({ success: true, isPromise: true });
            } else if (result) {
              console.log('[EnhancedJSProxy] 📦 JS脚本返回结果(同步):', JSON.stringify(result));
              return JSON.stringify({ success: true, result: result });
            } else {
              console.log('[EnhancedJSProxy] ⚠️ JS脚本未返回任何结果');
              return JSON.stringify({ success: false, error: 'No suitable handler found' });
            }
          } catch (e) {
            console.error('[EnhancedJSProxy] JS执行失败:', e);
            return JSON.stringify({ success: false, error: e.toString() });
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 JS执行结果: ${jsResult.stringResult}');

      // 解析JS返回结果
      Map<String, dynamic> resultData;
      try {
        resultData = jsonDecode(jsResult.stringResult);
      } catch (e) {
        print('[EnhancedJSProxy] ❌ JSON解析失败: $e');
        print('[EnhancedJSProxy] 原始结果: ${jsResult.stringResult}');
        return null;
      }

      if (resultData['success'] == true) {
        if (resultData['isPromise'] == true) {
          // 等待Promise完成（最多3秒）
          for (int i = 0; i < 30; i++) {
            // 3秒超时
            await Future.delayed(const Duration(milliseconds: 100));

            final checkResult = _runtime!.evaluate('''
              (function() {
                try {
                  console.log('[EnhancedJSProxy] 检查Promise状态:', globalThis._promiseComplete, globalThis._promiseResult, globalThis._promiseError);

                  if (globalThis._promiseComplete) {
                    if (globalThis._promiseResult !== null && globalThis._promiseResult !== undefined) {
                      console.log('[EnhancedJSProxy] ✅ Promise成功，结果:', JSON.stringify(globalThis._promiseResult));
                      return JSON.stringify({ success: true, result: globalThis._promiseResult });
                    } else if (globalThis._promiseError) {
                      console.log('[EnhancedJSProxy] ❌ Promise失败，错误:', globalThis._promiseError);
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
            } else if (checkData['success'] == false &&
                checkData['pending'] != true) {
              print('[EnhancedJSProxy] ❌ Promise失败: ${checkData['error']}');
              return null;
            }

            // 每秒显示一次等待状态
            if (i % 10 == 0) {
              print('[EnhancedJSProxy] ⏳ 等待Promise完成... ${i / 10}秒');
            }
          }

          print('[EnhancedJSProxy] ⏰ Promise等待超时 (3秒)');
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

  /// 获取专辑封面图
  Future<String?> getPic({
    required String source,
    required String songId,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!_isInitialized || _currentScript == null) {
      print('[EnhancedJSProxy] ⚠️ 服务未初始化或脚本未加载');
      return null;
    }

    try {
      print('[EnhancedJSProxy] 🖼️  开始获取专辑封面: $source/$songId');

      // 构建请求参数
      final requestParams = {
        'action': 'pic',
        'source': source,
        'info': {
          'musicInfo': {'songmid': songId, 'hash': songId, ...?musicInfo},
        },
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
            console.log('musicInfo', request.info.musicInfo);
            
            // 尝试多种调用方式
            let result = null;
            
            // 方式1: 调用已注册的request事件处理器（主要方式）
            if (globalThis._lxHandlers && globalThis._lxHandlers.request) {
              console.log('[EnhancedJSProxy] 尝试调用已注册的request事件处理器');
              const handlers = Array.isArray(globalThis._lxHandlers.request) ? 
                globalThis._lxHandlers.request : [globalThis._lxHandlers.request];
              
              for (const handler of handlers) {
                if (typeof handler === 'function') {
                  console.log('[EnhancedJSProxy] 调用处理器，参数:', request);
                  result = handler(request);
                  console.log('[EnhancedJSProxy] 处理器返回:', result);
                  if (result) break;
                }
              }
            }
            
            // 方式2: 通过 lx.emit 触发
            if (!result && typeof lx !== 'undefined' && typeof lx.emit === 'function') {
              console.log('[EnhancedJSProxy] 尝试通过 lx.emit 分发 request');
              result = lx.emit(lx.EVENT_NAMES.request, request);
              console.log('[EnhancedJSProxy] lx.emit 返回:', result);
            }

            if (result && typeof result.then === 'function') {
              console.log('[EnhancedJSProxy] 检测到Promise，开始等待...');
              try {
                result.then(function(v){
                  try {
                    console.log('[EnhancedJSProxy] 📦 JS脚本返回封面URL(Promise resolved):', JSON.stringify(v));
                    globalThis._promiseResult = v;
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                }).catch(function(err){
                  try {
                    console.log('[EnhancedJSProxy] ❌ JS脚本返回错误(Promise rejected):', err);
                    globalThis._promiseError = (err && (err.message || err.toString())) || 'Unknown error';
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                });
              } catch (e) { console.log('[EnhancedJSProxy] 绑定Promise回调失败:', e && e.message); }
              return JSON.stringify({ success: true, isPromise: true });
            } else if (result) {
              console.log('[EnhancedJSProxy] 📦 JS脚本返回封面URL(同步):', JSON.stringify(result));
              return JSON.stringify({ success: true, result: result });
            } else {
              console.log('[EnhancedJSProxy] ⚠️ JS脚本未返回任何封面URL');
              return JSON.stringify({ success: false, error: 'No suitable handler found' });
            }
          } catch (e) {
            console.error('[EnhancedJSProxy] JS执行失败:', e);
            return JSON.stringify({ success: false, error: e.toString() });
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 JS执行结果: ${jsResult.stringResult}');

      // 解析JS返回结果
      Map<String, dynamic> resultData;
      try {
        resultData = jsonDecode(jsResult.stringResult);
      } catch (e) {
        print('[EnhancedJSProxy] ❌ JSON解析失败: $e');
        return null;
      }

      if (resultData['success'] == true) {
        if (resultData['isPromise'] == true) {
          // 等待Promise完成（最多3秒）
          for (int i = 0; i < 30; i++) {
            await Future.delayed(const Duration(milliseconds: 100));

            final checkResult = _runtime!.evaluate('''
              (function() {
                try {
                  if (globalThis._promiseComplete) {
                    if (globalThis._promiseResult !== null && globalThis._promiseResult !== undefined) {
                      console.log('[EnhancedJSProxy] Promise成功，封面URL:', globalThis._promiseResult);
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
              final picUrl = checkData['result'];
              print('[EnhancedJSProxy] ✅ 获取封面成功: $picUrl');
              return picUrl;
            } else if (checkData['success'] == false &&
                checkData['pending'] != true) {
              print('[EnhancedJSProxy] ❌ 获取封面失败: ${checkData['error']}');
              return null;
            }
          }

          print('[EnhancedJSProxy] ⏰ Promise等待超时 (3秒)');
          return null;
        } else {
          final picUrl = resultData['result'];
          print('[EnhancedJSProxy] ✅ 获取封面成功: $picUrl');
          return picUrl;
        }
      } else {
        print('[EnhancedJSProxy] ❌ 获取封面失败: ${resultData['error']}');
        return null;
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 获取封面异常: $e');
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

  /// 检查是否有 request 处理器注册
  /// 🎯 用于判断脚本是否真正可用（某些脚本不调用 registerScript，但会注册 request 处理器）
  bool hasRequestHandler() {
    if (!_isInitialized || _currentScript == null) {
      return false;
    }

    try {
      final result = _runtime!.evaluate('''
        (function() {
          try {
            // 检查是否有注册的 request 事件处理器
            const handlers = globalThis._lxHandlers && globalThis._lxHandlers.request;
            if (!handlers) return false;

            // 如果是数组，检查长度
            if (Array.isArray(handlers)) {
              return handlers.length > 0;
            }

            // 如果是单个函数，返回 true
            if (typeof handlers === 'function') {
              return true;
            }

            return false;
          } catch (e) {
            return false;
          }
        })()
      ''');

      final hasHandler = result.rawResult == true;
      print('[EnhancedJSProxy] 🔍 检查 request 处理器: $hasHandler');
      return hasHandler;
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 检查 request 处理器失败: $e');
      return false;
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
