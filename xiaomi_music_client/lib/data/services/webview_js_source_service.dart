import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../presentation/providers/source_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A minimal transformer that always treats responses as plain text and
/// never attempts to parse JSON based on Content-Type. This avoids
/// noisy "Failed to parse the media type" logs from dio/http_parser
/// when servers return invalid media type strings (e.g. trailing semicolons).
class PlainTextTransformer extends Transformer {
  PlainTextTransformer();

  @override
  Future<String> transformRequest(RequestOptions options) async {
    final data = options.data;
    if (data == null) return '';
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody response,
  ) async {
    // Read all chunks into a single list of bytes
    final List<int> chunks = <int>[];
    await for (final List<int> chunk in response.stream) {
      chunks.addAll(chunk);
    }
    // Decode as UTF-8 string; allow malformed to avoid exceptions
    return utf8.decode(chunks, allowMalformed: true);
  }
}

class WebViewJsSourceService {
  final WebViewController controller;
  final Completer<void> _ready = Completer<void>();
  bool _inited = false;
  bool _hasValidAdapter = false;
  List<String> _lastFoundFunctions = <String>[];
  Completer<List<String>>? _pendingProbe;
  Completer<List<Map<String, dynamic>>>? _pendingSearchCompleter;
  Completer<String>? _pendingUrlCompleter;
  String? _activeSearchId;
  SourceSettings? _currentSettings;
  String? _loadedScriptUrlFromJs;
  Map<String, dynamic> _strategyCache = <String, dynamic>{};
  String? _currentApiKey; // 存储当前脚本的API密钥
  String? _currentScriptContent; // 存储当前脚本内容

  WebViewJsSourceService(this.controller);

  /// 从文本中提取指定关键字后的引号值
  String? _extractQuotedValue(String content, String keyword) {
    try {
      // 查找关键字位置
      int index = content.indexOf(keyword);
      if (index == -1) return null;

      // 从关键字位置开始搜索引号
      final substring = content.substring(index);

      // 查找引号并提取值
      final quotes = ['"', "'", '`'];
      for (final quote in quotes) {
        // 寻找等号或冒号后的引号开始
        int eqIndex = substring.indexOf('=');
        int colonIndex = substring.indexOf(':');

        // 选择最近的分隔符
        int separatorIndex = -1;
        if (eqIndex != -1 && colonIndex != -1) {
          separatorIndex = eqIndex < colonIndex ? eqIndex : colonIndex;
        } else if (eqIndex != -1) {
          separatorIndex = eqIndex;
        } else if (colonIndex != -1) {
          separatorIndex = colonIndex;
        }

        if (separatorIndex == -1) continue;

        final afterSeparator = substring.substring(separatorIndex + 1);
        final startIndex = afterSeparator.indexOf(quote);
        if (startIndex == -1) continue;

        final endIndex = afterSeparator.indexOf(quote, startIndex + 1);
        if (endIndex == -1) continue;

        final value = afterSeparator.substring(startIndex + 1, endIndex);
        print('🔍 [KeyExtractor] 找到候选值: "$value" (关键字: $keyword)');

        // 验证密钥格式：只接受英文字母数字组合，长度3-50
        if (value.isNotEmpty &&
            value.length >= 3 &&
            value.length <= 50 &&
            !value.contains(' ') &&
            !value.contains('音乐') && // 排除中文标识符
            !value.contains('小秋') && // 排除脚本名称
            !value.contains('music') && // 排除一般性描述
            RegExp(r'^[a-zA-Z0-9\-_]+$').hasMatch(value)) {
          print('✅ [KeyExtractor] 验证通过: "$value"');
          return value;
        } else {
          print('❌ [KeyExtractor] 验证失败: "$value" (可能是中文或无效格式)');
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 从脚本内容中提取API密钥
  String? _extractApiKeyFromScript() {
    if (_currentScriptContent == null) {
      print('❌ [KeyExtractor] 脚本内容为空');
      return null;
    }

    try {
      final content = _currentScriptContent!;
      print('🔍 [KeyExtractor] 开始分析脚本内容，长度: ${content.length}');

      // 1. 检测明文JS的API_KEY模式
      final apiKeySearch = _extractQuotedValue(content, 'API_KEY');
      if (apiKeySearch != null) {
        print('🔑 [KeyExtractor] 明文API_KEY提取到密钥: $apiKeySearch');
        return apiKeySearch;
      }

      // 2. 检测X-Request-Key模式
      final requestKeySearch = _extractQuotedValue(content, 'X-Request-Key');
      if (requestKeySearch != null) {
        print('🔑 [KeyExtractor] X-Request-Key提取到密钥: $requestKeySearch');
        return requestKeySearch;
      }

      // 3. 特殊已知密钥检测
      if (content.contains('share-v2')) {
        print('🔑 [KeyExtractor] 检测到已知密钥: share-v2');
        return 'share-v2';
      }

      // 4. 根据脚本URL特征判断
      if (_loadedScriptUrlFromJs != null) {
        final scriptUrl = _loadedScriptUrlFromJs!.toLowerCase();
        if (scriptUrl.contains('xiaoqiu')) {
          print('🔑 [KeyExtractor] xiaoqiu脚本使用已知密钥: share-v2');
          return 'share-v2';
        }
      }

      print('❌ [KeyExtractor] 未找到有效密钥，脚本可能已加密或使用未知格式');
      return null;
    } catch (e) {
      print('❌ [KeyExtractor] 密钥提取异常: $e');
      return null;
    }
  }

  /// 注入运行时密钥监听器，用于捕获加密脚本中的API密钥
  Future<void> _injectRuntimeKeyListener(WebViewController controller) async {
    try {
      print('🔍 [RuntimeKeyListener] 注入密钥监听器，用于加密脚本');

      await controller.runJavaScript(r'''
        (function() {
          // 拦截原始fetch函数
          if (typeof window.originalFetch === 'undefined') {
            window.originalFetch = window.fetch;
            
            window.fetch = function(url, options) {
              try {
                // 检查是否是LX Music API请求
                if (url && typeof url === 'string' && 
                    (url.includes('/url/') || url.includes('/search/'))) {
                  
                  // 提取X-Request-Key
                  if (options && options.headers) {
                    const headers = options.headers;
                    let extractedKey = null;
                    
                    // 检查不同格式的headers
                    if (typeof headers === 'object') {
                      // 对象格式: { "X-Request-Key": "value" }
                      for (const key in headers) {
                        if (key === 'X-Request-Key' || key === 'x-request-key') {
                          extractedKey = headers[key];
                          break;
                        }
                      }
                      
                      // Headers实例
                      if (headers.get && typeof headers.get === 'function') {
                        extractedKey = headers.get('X-Request-Key') || headers.get('x-request-key');
                      }
                    }
                    
                    // 发现密钥时通知Flutter
                    if (extractedKey && extractedKey.length > 3) {
                      console.log('[RuntimeKeyListener] 捕获到API密钥:', extractedKey);
                      try {
                        JSBridge.postMessage('runtime_key_found:' + extractedKey);
                      } catch(e) {
                        console.warn('[RuntimeKeyListener] 密钥传递失败:', e);
                      }
                    }
                  }
                }
              } catch(e) {
                console.warn('[RuntimeKeyListener] 监听异常:', e);
              }
              
              // 继续执行原始请求
              return window.originalFetch.apply(this, arguments);
            };
            
            console.log('[RuntimeKeyListener] 密钥监听器已注入');
          }
        })();
      ''');
    } catch (e) {
      print('❌ [RuntimeKeyListener] 注入失败: $e');
    }
  }

  void _completeSearchResult(List<Map<String, dynamic>> results) {
    if (_pendingSearchCompleter != null &&
        !_pendingSearchCompleter!.isCompleted) {
      _pendingSearchCompleter!.complete(results);
      _pendingSearchCompleter = null;
    }
  }

  void _completeUrlResult(String url) {
    if (_pendingUrlCompleter != null && !_pendingUrlCompleter!.isCompleted) {
      print('🔗 [WebViewJsSource] 完成URL解析: $url');
      _pendingUrlCompleter!.complete(url);
    }
  }

  // 内置脚本加载已完全移除

  Future<String?> _downloadScriptWithFallback(List<String> urls) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 6),
        responseType: ResponseType.plain,
        validateStatus: (code) => code != null && code >= 200 && code < 400,
        headers: {
          'Accept': 'text/javascript,application/javascript;q=0.9,*/*;q=0.1',
          'User-Agent': 'xiaoaitongxue-webview-loader',
        },
      ),
    );
    for (final u in urls) {
      try {
        final res = await dio.get<String>(u);
        final text = res.data ?? '';
        if (text.isNotEmpty) return text;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> init(SourceSettings settings) async {
    _currentSettings = settings;
    await _loadStrategyCache();
    print('🔧 [WebViewJsSource] 开始初始化WebView音源');
    print('🔧 [WebViewJsSource] 启用状态: ${settings.enabled}');
    print('🔧 [WebViewJsSource] 使用内置脚本: ${settings.useBuiltinScript}');
    print('🔧 [WebViewJsSource] 脚本URL长度: ${settings.scriptUrl.length}');
    print('🔧 [WebViewJsSource] 脚本URL: ${settings.scriptUrl}');
    // 分段打印长URL，避免截断
    if (settings.scriptUrl.length > 100) {
      print(
        '🔧 [WebViewJsSource] URL前半部分: ${settings.scriptUrl.substring(0, settings.scriptUrl.length ~/ 2)}',
      );
      print(
        '🔧 [WebViewJsSource] URL后半部分: ${settings.scriptUrl.substring(settings.scriptUrl.length ~/ 2)}',
      );
    }

    if (_inited) {
      print('ℹ️ [WebViewJsSource] 已经初始化过了');
      return;
    }

    print('⚙️ [WebViewJsSource] 配置WebView...');
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // macOS 上 setBackgroundColor/opaque 未实现，调用会抛 UnimplementedError
    try {
      if (!Platform.isMacOS) {
        await controller.setBackgroundColor(const Color(0x00000000));
      }
    } catch (_) {}

    // 配置导航代理，允许所有请求
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) {
          return NavigationDecision.navigate;
        },
      ),
    );

    // 设置用户代理，模拟真实浏览器
    await controller.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );

    // 先注册 JS Channel，再加载页面，保证页面侧可见
    print('📡 [WebViewJsSource] 注册JS桥接器...');

    // 注册适配器状态桥接器
    await controller.addJavaScriptChannel(
      'JSBridge',
      onMessageReceived: (msg) {
        print('📨 [JSBridge] 收到消息: ${msg.message}');

        // 检查运行时密钥捕获
        if (msg.message.startsWith('runtime_key_found:')) {
          final key = msg.message.substring('runtime_key_found:'.length);
          if (key.isNotEmpty && key.length > 3) {
            _currentApiKey = key;
            print('🔑 [RuntimeKeyListener] 成功捕获加密脚本密钥: $key');
          }
          return;
        }

        // 检查适配器状态
        if (msg.message.startsWith('loaded:')) {
          _loadedScriptUrlFromJs = msg.message.substring('loaded:'.length);
          print('📦 [WebViewJsSource] 实际加载脚本URL: $_loadedScriptUrlFromJs');
          // 若预置为 xiaoqiu，则预先绑定策略为 S1
          if ((_currentSettings?.scriptPreset ?? '') == 'xiaoqiu') {
            final key =
                _loadedScriptUrlFromJs ?? _currentSettings?.scriptUrl ?? '';
            if (key.isNotEmpty && (_strategyCache[key] == null)) {
              _strategyCache[key] = {
                'strategyId': 'S1',
                'lastSuccess': DateTime.now().millisecondsSinceEpoch,
              };
              _saveStrategyCache();
              print('🧠 [Strategy] 预置 xiaoqiu → 绑定策略 S1 到 $key');
            }
          }
        }
        if (msg.message.startsWith('adapter_found:')) {
          final adapter = msg.message.substring('adapter_found:'.length);
          _hasValidAdapter = adapter.isNotEmpty;
          _lastFoundFunctions =
              adapter
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
          print(
            '🔍 [WebViewJsSource] 适配器检测结果: ${_hasValidAdapter ? "有效" : "无效"}',
          );
          if (_pendingProbe != null && !(_pendingProbe!.isCompleted)) {
            _pendingProbe!.complete(_lastFoundFunctions);
          }
        }
        if (msg.message.startsWith('strategy_selected:')) {
          final strategy = msg.message.substring('strategy_selected:'.length);
          final key = _computeScriptKey();
          if (key.isNotEmpty) {
            print('🧠 [Strategy] 记录策略: 脚本=$key, 策略=$strategy');
            _strategyCache[key] = {
              'strategyId': strategy,
              'lastSuccess': DateTime.now().millisecondsSinceEpoch,
            };
            _saveStrategyCache();
          }
        }
        if (msg.message.startsWith('ready_state:')) {
          final state = msg.message.substring('ready_state:'.length);
          print('🧩 [WebViewJsSource] ReadyState: ' + state);
        }
        // 适配器已注入的标记（即使未探测到脚本自带函数，也可用我们注入的适配器）
        if (msg.message == 'adapter_injected') {
          _hasValidAdapter = true;
          print('✅ [WebViewJsSource] 适配器已注入，标记为可用');
        }
        // 处理搜索结果事件（带请求ID，丢弃过期结果）
        if (msg.message.startsWith('search_result:')) {
          final payload = msg.message.substring('search_result:'.length);
          String resultJson = payload;
          // 兼容格式：search_result:<id>:<json>
          final sep = payload.indexOf(':');
          if (sep > 0) {
            final incomingId = payload.substring(0, sep);
            resultJson = payload.substring(sep + 1);
            if (_activeSearchId != null && incomingId != _activeSearchId) {
              print(
                '⚠️ [JSBridge] 丢弃过期搜索结果 id=$incomingId, 当前=${_activeSearchId}',
              );
              return;
            }
          } else {
            // 无ID旧格式：若当前存在活动ID，则仅当无并发时接受
            if (_activeSearchId != null) {
              print('⚠️ [JSBridge] 无ID结果在并发期间到达，已忽略');
              return;
            }
          }

          print('🔍 [JSBridge] 收到搜索结果: ${resultJson.length} 字符');
          try {
            final parsed = jsonDecode(resultJson);
            if (parsed is List) {
              final results =
                  parsed
                      .where((e) => e is Map)
                      .map((e) => (e as Map).cast<String, dynamic>())
                      .toList();
              print('✅ [JSBridge] 解析搜索结果: ${results.length} 项');
              // 如果有等待中的搜索，完成它
              _completeSearchResult(results);
            }
          } catch (e) {
            print('⚠️ [JSBridge] 解析搜索结果失败: $e');
            _completeSearchResult(<Map<String, dynamic>>[]);
          } finally {
            // 本次搜索完成，清空活动ID
            _activeSearchId = null;
          }
        }
        // 处理URL解析结果事件
        else if (msg.message.startsWith('url_result:')) {
          final url = msg.message.substring('url_result:'.length);

          // 检查版权问题
          if (url == 'COPYRIGHT_ERROR') {
            print('❌ [WebViewJsSource] 版权错误：该歌曲在当前音源没有播放权限');
            print('💡 [WebViewJsSource] 建议：尝试搜索其他版本或使用不同音源');
            _completeUrlResult(''); // 返回空结果
            return;
          }

          print('🔗 [JSBridge] 收到URL解析结果: $url');

          // 检查是否是回退的酷我音乐链接
          if (url.contains('kuwo.cn')) {
            print('⚠️ [WebViewJsSource] 注意：QQ音乐直链获取失败，使用酷我音乐作为备用播放源');
          }

          _completeUrlResult(url);
        }
      },
    );

    // 注册网络请求代理桥接器
    await controller.addJavaScriptChannel(
      'NetworkBridge',
      onMessageReceived: (msg) async {
        try {
          final data = jsonDecode(msg.message);
          final requestId = data['id'] as String;
          final urlData = data['url'];
          final method = data['method'] as String? ?? 'GET';
          final headers = Map<String, String>.from(data['headers'] ?? {});
          final body = data['body'];

          // 检查URL有效性
          String url;
          if (urlData is String) {
            url = urlData;
          } else {
            // 如果URL不是字符串，返回错误
            print('❌ [NetworkBridge] URL不是字符串: ${urlData.runtimeType}');
            final result = {
              'id': requestId,
              'success': false,
              'error': 'Invalid URL type: ${urlData.runtimeType}',
            };
            await controller.runJavaScript(
              'window.__networkCallback && window.__networkCallback(${jsonEncode(result)})',
            );
            return;
          }

          // 验证URL格式
          if (!url.startsWith('http://') && !url.startsWith('https://')) {
            print('❌ [NetworkBridge] 无效URL格式: $url');
            final result = {
              'id': requestId,
              'success': false,
              'error': 'Invalid URL format: $url',
            };
            await controller.runJavaScript(
              'window.__networkCallback && window.__networkCallback(${jsonEncode(result)})',
            );
            return;
          }

          print('🌐 [NetworkBridge] 代理请求: $method $url');

          // 添加常用请求头，绕过反爬虫
          headers.putIfAbsent(
            'User-Agent',
            () =>
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          );
          headers.putIfAbsent(
            'Accept',
            () => 'application/json, text/plain, */*',
          );
          headers.putIfAbsent(
            'Accept-Language',
            () => 'zh-CN,zh;q=0.9,en;q=0.8',
          );
          headers.putIfAbsent('Cache-Control', () => 'no-cache');
          headers.putIfAbsent('Pragma', () => 'no-cache');

          // 若为 LX Music API 相关请求，自动补齐认证头
          final lowerUrl = url.toLowerCase();
          final isLxApi =
              lowerUrl.contains('/url/') || lowerUrl.contains('/search/');
          if (isLxApi) {
            // 尝试使用提取的API密钥；若为空，则使用已知默认密钥 share-v2 作为回退
            if (_currentApiKey == null || _currentApiKey!.isEmpty) {
              print('⚠️ [NetworkBridge] 未提取到API密钥，使用默认密钥 share-v2');
              _currentApiKey = 'share-v2';
            }

            headers.putIfAbsent('X-Request-Key', () => _currentApiKey!);
            // 对齐示例：即便是GET也显式设置 Content-Type
            headers['Content-Type'] = 'application/json';
            // 模拟 LX 客户端 UA
            headers['User-Agent'] = 'lx-music-request/2.4.0';
            print('🔑 [NetworkBridge] 使用提取的API密钥: $_currentApiKey');
          }

          // 使用Dio执行请求
          final dio = Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 500,
              followRedirects: true,
              maxRedirects: 3,
              // 禁用自动JSON解析，避免content-type问题
              contentType: 'application/json',
            ),
          );

          // 强制以纯文本处理，避免 dio 根据 content-type 解析导致报错
          dio.transformer = PlainTextTransformer();

          // 处理请求体数据
          dynamic requestData;
          if (body != null) {
            if (body is String) {
              requestData = body;
            } else if (body is Map) {
              // 如果是对象，转换为JSON字符串
              requestData = jsonEncode(body);
              headers['Content-Type'] = 'application/json';
            } else {
              requestData = body.toString();
            }
          }

          final response = await dio.request(
            url,
            options: Options(
              method: method,
              headers: headers,
              responseType: ResponseType.plain,
            ),
            data: requestData,
          );

          print('✅ [NetworkBridge] 请求成功: ${response.statusCode}');
          print(
            '📦 [NetworkBridge] 响应长度: ${response.data?.toString().length ?? 0}',
          );

          // 特别打印音乐API的返回结果
          if (url.contains('lxmusicapi.onrender.com')) {
            print('🎵 [MusicAPI] URL: $url');
            print('🎵 [MusicAPI] 返回数据: ${response.data}');
            try {
              final apiResult = jsonDecode(response.data.toString());
              print('🎵 [MusicAPI] 解析结果: $apiResult');
              if (apiResult['data'] != null) {
                print(
                  '🎵 [MusicAPI] 播放链接: ${apiResult['data']['url'] ?? apiResult['data']}',
                );
              }
            } catch (parseError) {
              print('🎵 [MusicAPI] JSON解析失败: $parseError');
            }
          }

          // 返回结果给JS
          final result = {
            'id': requestId,
            'success': true,
            'status': response.statusCode,
            'data': response.data,
            'headers': response.headers.map,
          };

          await controller.runJavaScript(
            'window.__networkCallback && window.__networkCallback(${jsonEncode(result)})',
          );
        } catch (e) {
          print('❌ [NetworkBridge] 请求失败: $e');
          // 如果是 LX 接口，尝试在 WebView 内直接使用 fetch 作为回退（规避原生网络栈问题）
          try {
            final lower =
                (msg.message.contains('http')
                        ? jsonDecode(msg.message)['url']?.toString()
                        : '')
                    ?.toLowerCase() ??
                '';
            if (lower.contains('lxmusicapi.onrender.com')) {
              final data = jsonDecode(msg.message);
              final requestId = data['id'] as String;
              final jsHeaders = jsonEncode((data['headers'] as Map?) ?? {});
              final jsMethod = jsonEncode(data['method'] ?? 'GET');
              final jsUrl = jsonEncode(data['url']);
              final fallbackJs = '''(async function(){
                try{
                  const res = await fetch(${jsUrl}, { method: ${jsMethod}, headers: ${jsHeaders} });
                  const text = await res.text();
                  const result = { id: ${jsonEncode(requestId)}, success: true, status: res.status, data: text };
                  window.__networkCallback && window.__networkCallback(result);
                }catch(err){
                  const result = { id: ${jsonEncode(requestId)}, success: false, error: String(err) };
                  window.__networkCallback && window.__networkCallback(result);
                }
              })();''';
              await controller.runJavaScript(fallbackJs);
              return;
            }
          } catch (_) {}

          // 非 LX 接口或回退失败，返回错误给 JS
          try {
            final data = jsonDecode(msg.message);
            final requestId = data['id'] as String;
            final result = {
              'id': requestId,
              'success': false,
              'error': e.toString(),
            };
            await controller.runJavaScript(
              'window.__networkCallback && window.__networkCallback(${jsonEncode(result)})',
            );
          } catch (_) {}
        }
      },
    );

    // 空白页作为容器
    print('📄 [WebViewJsSource] 加载HTML容器...');
    await controller.loadHtmlString(
      '<html><head><meta name="viewport" content="width=device-width, initial-scale=1"/></head><body></body></html>',
    );

    // 注入 Cookie 全局变量
    print('🍪 [WebViewJsSource] 注入Cookie变量...');
    final cookieInit =
        "var MUSIC_U='${settings.cookieNetease}'; var ts_last='${settings.cookieTencent}';";
    await controller.runJavaScript(cookieInit);

    // 拉取并注入脚本（带多镜像自动降级）
    if (settings.scriptUrl.isNotEmpty) {
      print('🌐 [WebViewJsSource] 开始加载JS脚本...');

      // 检查URL是否被截断，如果是xiaoqiu相关且不以.js结尾，尝试修复
      String finalUrl = settings.scriptUrl;
      if (finalUrl.contains('xiaoqiu') &&
          !finalUrl.endsWith('.js') &&
          !finalUrl.endsWith('/')) {
        if (finalUrl.endsWith('.j')) {
          finalUrl = finalUrl + 's';
          print('🔧 [WebViewJsSource] 检测到URL截断，自动修复: $finalUrl');
        }
      }

      final List<String> urls = <String>[finalUrl]; // 使用修复后的URL
      // 当为六音默认地址时，追加 jsDelivr 镜像
      // 添加多个可靠的镜像源，优先使用支持完整功能的脚本
      final fallbackUrls = [
        // xiaoqiu.js - 优先选择，支持完整功能
        'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js',
        'https://cdn.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js',
        'https://raw.githubusercontent.com/Huibq/keep-alive/main/Music_Free/xiaoqiu.js',
      ];

      // 如果当前URL不在fallback列表中，则添加所有fallback
      if (!fallbackUrls.contains(finalUrl)) {
        urls.addAll(fallbackUrls);
      } else {
        // 如果当前URL在fallback中，将其他的也加上
        urls.addAll(fallbackUrls.where((u) => u != finalUrl));
      }
      // 根据设置选择脚本源
      String? scriptText;

      // 检查用户是否选择了具体的脚本URL
      final hasUserScriptUrl =
          settings.scriptUrl.isNotEmpty && settings.scriptUrl != 'builtin';

      if (hasUserScriptUrl) {
        // 用户明确选择了脚本URL，优先使用用户选择
        print('🎯 [WebViewJsSource] 用户选择脚本: ${settings.scriptUrl}');
        scriptText = await _downloadScriptWithFallback(urls);
      } else if (settings.useBuiltinScript) {
        // 内置脚本加载已禁用（grass移除），直接使用远程脚本
        print('ℹ️ [WebViewJsSource] 内置脚本已禁用，改用远程脚本');
        scriptText = await _downloadScriptWithFallback(urls);
      } else {
        // 默认使用远程脚本
        print('🌐 [WebViewJsSource] 使用远程脚本');
        scriptText = await _downloadScriptWithFallback(urls);
      }

      if (scriptText != null && scriptText.isNotEmpty) {
        final sourceType =
            hasUserScriptUrl
                ? "用户脚本"
                : (settings.useBuiltinScript ? "内置脚本" : "远程脚本");
        print('📥 [WebViewJsSource] $sourceType 已加载，直接注入执行');

        // 保存脚本内容并提取API密钥
        _currentScriptContent = scriptText;
        _currentApiKey = _extractApiKeyFromScript();
        if (_currentApiKey != null) {
          print('✅ [WebViewJsSource] 成功提取API密钥: $_currentApiKey');
        } else {
          print('⚠️ [WebViewJsSource] 未能提取API密钥，API请求可能失败');
        }
        const String lxShim = r'''(function(){
          try{
            var g = (typeof globalThis !== 'undefined') ? globalThis : (this||{});
            // 基础 polyfill
            if (typeof g.atob !== 'function') {
              g.atob = function(input){
                var chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                input = String(input).replace(/=+$/, '');
                var str='';
                for (var bc=0, bs, buffer, idx=0; buffer = input.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? str += String.fromCharCode(255 & (bs >> (-2 * bc & 6))) : 0) {
                  buffer = chars.indexOf(buffer);
                }
                return str;
              };
            }
            if (typeof g.btoa !== 'function') {
              g.btoa = function(input){
                var chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                var str = String(input);
                var output='';
                for (var block, charCode, idx=0, map=chars; str.charAt(idx | 0) || (map='=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
                  charCode = str.charCodeAt(idx += 3/4);
                  if (charCode > 0xFF) throw new Error('btoa polyfill: invalid char');
                  block = block << 8 | charCode;
                }
                return output;
              };
            }
            if (typeof g.Buffer === 'undefined') {
              g.Buffer = {
                from: function(input, enc){
                  if (enc === 'base64') {
                    var bin = g.atob(input);
                    var len = bin.length;
                    var bytes = new Uint8Array(len);
                    for (var i=0;i<len;i++) bytes[i] = bin.charCodeAt(i) & 0xff;
                    return bytes;
                  }
                  if (typeof input === 'string') {
                    var utf8 = unescape(encodeURIComponent(input));
                    var arr = new Uint8Array(utf8.length);
                    for (var i=0;i<utf8.length;i++) arr[i] = utf8.charCodeAt(i);
                    return arr;
                  }
                  if (input && input.buffer) return new Uint8Array(input);
                  if (Array.isArray(input)) return new Uint8Array(input);
                  return new Uint8Array(0);
                }
              };
            }

            // LX 运行时最小模拟
            g.__lx_events = g.__lx_events || {};
            var evt = {
              SOURCE_LIST: 'SOURCE_LIST',
              SOURCE_SEARCH: 'SOURCE_SEARCH',
              SOURCE_SONG_URL: 'SOURCE_SONG_URL',
              SOURCE_LRC: 'SOURCE_LRC',
              SOURCE_ALBUM: 'SOURCE_ALBUM',
              SOURCE_ARTIST: 'SOURCE_ARTIST',
              REQUEST: 'REQUEST',
            };
            if(!g.lx){
              g.lx = {
                EVENT_NAMES: evt,
                APP_EVENT_NAMES: {},
                CURRENT_PLATFORM: 'desktop',
                APP_SETTING: {},
                version: '2.4.0',
                isDev: false,
                on: function(name, handler){ try{ g.__lx_events[name]=handler; }catch(_){} },
                off: function(name){ try{ delete g.__lx_events[name]; }catch(_){} },
                emit: function(name, payload){ try{ var h=g.__lx_events[name]; if (typeof h==='function') return h(payload); }catch(_){} },
                request: function(url, options){ return fetch(url, options||{}); },
                utils: {
                  buffer: {
                    from: function(input, enc){ return g.Buffer.from(input, enc); },
                    bufToString: function(buf, enc){
                      try{ if (buf && buf.buffer) { return new TextDecoder().decode(buf); } }catch(_){ }
                      return '';
                    },
                  },
                  crypto: {
                    md5: function(s){ return (s||'').length.toString(16); },
                  },
                },
                env: 'mobile',
                currentScriptInfo: { name: 'custom', description: 'custom', rawScript: '' },
              };
            }
          }catch(e){}
        })()''';
        await controller.runJavaScript(lxShim);

        // 注入安全的 storage 与 document/location polyfill，避免草源读取本地存储报 DOMException
        const String storageShim = r'''(function(){
          try{
            var g = (typeof globalThis !== 'undefined') ? globalThis : (this||{});
            function createStore(){
              var m = {};
              return {
                getItem: function(k){ try{ return Object.prototype.hasOwnProperty.call(m, k) ? String(m[k]) : null; }catch(_){ return null; } },
                setItem: function(k,v){ try{ m[String(k)] = String(v); }catch(_){ } },
                removeItem: function(k){ try{ delete m[String(k)]; }catch(_){ } },
                clear: function(){ try{ m = {}; }catch(_){ } },
                key: function(i){ try{ return Object.keys(m)[i] || null; }catch(_){ return null; } },
                get length(){ try{ return Object.keys(m).length; }catch(_){ return 0; } }
              };
            }
            try{ if(!g.localStorage) g.localStorage = createStore(); }catch(_){ }
            try{ if(!g.sessionStorage) g.sessionStorage = createStore(); }catch(_){ }
            try{ if(typeof document === 'undefined') g.document = { cookie: '' }; }catch(_){ }
            try{ if(typeof location === 'undefined') g.location = { href: 'about:blank', origin: '', protocol: 'https:' }; }catch(_){ }
          }catch(e){ }
        })()''';
        await controller.runJavaScript(storageShim);

        // 注入网络代理，替换fetch函数
        const String networkProxy = r'''(function(){
          try{
            // 保存原始fetch
            const originalFetch = window.fetch;
            
            // 网络请求回调管理
            window.__networkCallbacks = {};
            window.__networkCallback = function(result) {
              const callback = window.__networkCallbacks[result.id];
              if (callback) {
                delete window.__networkCallbacks[result.id];
                if (result.success) {
                  callback.resolve(result);
                } else {
                  callback.reject(new Error(result.error || 'Network request failed'));
                }
              }
            };
            
            // 替换fetch函数
            window.fetch = function(url, options = {}) {
              return new Promise((resolve, reject) => {
                try {
                  const requestId = 'req_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
                  
                  // 构建请求数据
                  const requestData = {
                    id: requestId,
                    url: url,
                    method: options.method || 'GET',
                    headers: options.headers || {},
                    body: options.body || null
                  };
                  
                  console.log('[NetworkProxy] 代理fetch请求:', url);
                  console.log('[NetworkProxy] 请求数据:', requestData);
                  
                   // 添加超时处理（提升到45秒，避免大型资源/慢源导致的假超时）
                  const timeoutId = setTimeout(() => {
                    console.warn('[NetworkProxy] 请求超时，ID:', requestId);
                    delete window.__networkCallbacks[requestId];
                    reject(new Error('Request timeout'));
                   }, 45000); // 45秒超时
                  
                  // 更新回调，添加超时清理
                  window.__networkCallbacks[requestId] = {
                    resolve: (result) => {
                      clearTimeout(timeoutId);
                      // 模拟Response对象
                      const response = {
                        ok: result.status >= 200 && result.status < 300,
                        status: result.status,
                        statusText: 'OK',
                        headers: new Map(Object.entries(result.headers || {})),
                        text: () => Promise.resolve(result.data),
                        json: () => {
                          try {
                            return Promise.resolve(JSON.parse(result.data));
                          } catch (e) {
                            console.warn('[NetworkProxy] JSON解析失败:', e);
                            return Promise.reject(new Error('Invalid JSON'));
                          }
                        },
                        blob: () => Promise.resolve(new Blob([result.data])),
                        arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)),
                      };
                      console.log('[NetworkProxy] 请求成功，状态:', result.status);
                      resolve(response);
                    },
                    reject: (error) => {
                      clearTimeout(timeoutId);
                      console.error('[NetworkProxy] 请求失败:', error);
                      reject(error);
                    }
                  };
                  
                  // 发送到NetworkBridge
                  if (window.NetworkBridge && NetworkBridge.postMessage) {
                    NetworkBridge.postMessage(JSON.stringify(requestData));
                  } else {
                    // 回退到原始fetch，但处理握手失败问题
                    console.warn('[NetworkProxy] NetworkBridge不可用，回退到原始fetch');
                    clearTimeout(timeoutId);
                    delete window.__networkCallbacks[requestId];
                    
                    // 特殊处理已知的问题URL
                    if (url && (url.includes('43.143.63.234') || url.includes('registry.npmjs.org') || url.includes('registry.npmmirror.com'))) {
                      console.log('[NetworkProxy] 跳过问题URL，返回模拟响应:', url);
                      resolve({
                        ok: true,
                        status: 200,
                        statusText: 'OK',
                        headers: new Map(),
                        text: () => Promise.resolve('{"version":"1.0.0","sources":[]}'),
                        json: () => Promise.resolve({version: '1.0.0', sources: []}),
                        blob: () => Promise.resolve(new Blob(['{}'])),
                        arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)),
                      });
                    } else {
                      originalFetch(url, options).then(resolve).catch((error) => {
                        console.warn('[NetworkProxy] 原始fetch失败，返回兜底响应:', error);
                        resolve({
                          ok: false,
                          status: 500,
                          statusText: 'Network Error',
                          headers: new Map(),
                          text: () => Promise.resolve('{}'),
                          json: () => Promise.resolve({}),
                          blob: () => Promise.resolve(new Blob(['{}'])),
                          arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)),
                        });
                      });
                    }
                  }
                  
                } catch (e) {
                  console.error('[NetworkProxy] fetch代理错误:', e);
                  reject(e);
                }
              });
            };
            
            console.log('[NetworkProxy] fetch函数已被代理');
            
          }catch(e){
            console.warn('NetworkProxy initialization error:', e);
          }
        })()''';
        await controller.runJavaScript(networkProxy);

        // 优先注入CommonJS环境，避免脚本中过早使用exports
        const String commonJsShim = r'''(function(){
          try{
            // 确保全局环境下就有这些变量
            if (typeof window !== 'undefined') {
              // 先定义exports和module，防止脚本立即使用
              if (typeof window.exports === 'undefined') {
                window.exports = {};
              }
              if (typeof window.module === 'undefined') {
                window.module = { exports: window.exports };
              }
            }
            if (typeof globalThis !== 'undefined') {
              if (typeof globalThis.exports === 'undefined') {
                globalThis.exports = globalThis.exports || {};
              }
              if (typeof globalThis.module === 'undefined') {
                globalThis.module = { exports: globalThis.exports };
              }
            }
            
            if (typeof require !== 'function'){
              var axios = function(opts){
                opts = opts || {};
                var method = (opts.method || 'GET').toUpperCase();
                var headers = opts.headers || {};
                var body = (opts.data!=null) ? (typeof opts.data==='string' ? opts.data : JSON.stringify(opts.data)) : undefined;
                return fetch(opts.url, { method: method, headers: headers, body: body, credentials: 'include' })
                  .then(function(r){ 
                    return r.text().then(function(t){ 
                      var d; 
                      try{ 
                        d = JSON.parse(t);
                      }catch(_){ 
                        d = t;
                      } 
                      return { data: d, status: r.status, statusText: r.statusText }; 
                    }); 
                  });
              };
              axios.get = function(url, opts){ opts=opts||{}; return axios({ url: url, method: 'GET', headers: (opts.headers||{}) }); };
              axios.post = function(url, data, opts){ opts=opts||{}; return axios({ url: url, method: 'POST', headers: (opts.headers||{}), data: data }); };
              axios.default = axios;
              
              var CryptoJs = { 
                enc: { 
                  Base64: { 
                    parse: function(s){ 
                      return { 
                        toString: function(){ 
                          try{ return atob(s);}catch(e){ return ''; } 
                        } 
                      }; 
                    } 
                  }, 
                  Utf8: {
                    parse: function(s){ return { toString: function(){ return s || ''; } }; }
                  }
                },
                AES: {
                  decrypt: function(){ return { toString: function(){ return ''; } }; }
                }
              };
              var he = { 
                decode: function(s){ 
                  try{ 
                    return s.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&#39;/g,"'").replace(/&quot;/g,'"'); 
                  }catch(e){ 
                    return s; 
                  } 
                } 
              };
              
              function require(name){ 
                if(name==='axios') return axios; 
                if(name==='crypto-js') return CryptoJs; 
                if(name==='he') return he; 
                return {}; 
              }
              
              // 再次确保全局可访问
              try{ window.require = require; }catch(_){ }
              try{ globalThis.require = require; }catch(_){ }
            }
          }catch(e){
            console.warn('CommonJS shim error:', e);
          }
        })()''';
        await controller.runJavaScript(commonJsShim);
        await controller.runJavaScript(scriptText);

        // 如果没有提取到密钥，注入运行时监听器捕获加密脚本的密钥
        if (_currentApiKey == null) {
          await _injectRuntimeKeyListener(controller);
        }

        // 将 CommonJS 导出的函数提升到全局，便于后续检测与调用
        await controller.runJavaScript(r'''(function(){
          try{
            if (typeof module !== 'undefined' && module && module.exports){
              var exp = module.exports;
              var keys = ['search','searchMusic','search_music','getMediaSource','getMusic','query'];
              for (var i=0;i<keys.length;i++){
                var k = keys[i];
                try{
                  if (!window[k] && typeof exp[k] === 'function') {
                    window[k] = exp[k];
                  }
                }catch(_){}
              }
              if (exp.default && typeof exp.default === 'object'){
                var d = exp.default;
                for (var p in d){
                  try{ if (!window[p] && typeof d[p] === 'function' && ['search','searchMusic','getMediaSource','query'].indexOf(p) >= 0) window[p]=d[p]; }catch(_){ }
                }
              }
            }
          }catch(e){}
        })()''');
        // 延迟重复探测，等待动态脚本完全就绪后再次上报候选函数（草莓源需要更长时间）
        await controller.runJavaScript(r'''(function(){
          try{
            var attempts = 0;
            var timer = setInterval(function(){
              attempts++;
              try{
                if (typeof window.__ensureHoisted==='function') window.__ensureHoisted();
              }catch(_){ }
              try{
                var found=[]; 
                var c=['search','searchImpl','search','musicSearch','searchMusic'];
                for(var i=0;i<c.length;i++){ 
                  try{ 
                    var f=eval(c[i]); 
                    if(typeof f==='function') found.push(c[i]); 
                  }catch(_){ } 
                }
                
                // 重点检查module.exports（草莓源的主要导出方式）
                if (typeof module!=='undefined' && module && module.exports) {
                  console.log('[延迟探测] module.exports检查，类型:', typeof module.exports);
                  
                  if(typeof module.exports === 'function') {
                    console.log('[延迟探测] ✓ 发现module.exports函数');
                    found.push('module.exports');
                  }
                  
                  if(typeof module.exports.search === 'function') {
                    console.log('[延迟探测] ✓ 发现module.exports.search');
                    found.push('module.exports.search');
                  }
                  
                  // 检查其他可能的方法
                  try {
                    for(var prop in module.exports) {
                      if(typeof module.exports[prop] === 'function') {
                        console.log('[延迟探测] ✓ 发现module.exports.' + prop);
                        found.push('module.exports.' + prop);
                      }
                    }
                  } catch(e) {}
                }
                
                if(found.length){
                  console.log('[延迟探测] ✅ 发现函数:', found.join(','));
                  try{ JSBridge.postMessage('adapter_found:'+found.join(',')); }catch(_){ }
                  clearInterval(timer);
                } else if(attempts % 5 === 0) {
                  console.log('[延迟探测] 尝试', attempts, '/30, 等待草莓源初始化...');
                }
              }catch(e){ 
                console.log('[延迟探测] 异常:', e);
              }
              if (attempts>=30) { // 增加到30次，总共6秒
                console.log('[延迟探测] 超时，停止探测');
                clearInterval(timer);
              }
            }, 200);
          }catch(e){
            console.log('[延迟探测] 初始化异常:', e);
          }
        })()''');
        // 触发一次探测，增强grass源检测
        await controller.runJavaScript(r'''
          (function(){ 
            try{ 
              console.log('[Grass检测] 开始全面函数扫描...');
              const found=[]; 
              const c=['search','searchImpl','search','musicSearch','searchMusic']; 
              for(const n of c){ 
                try{ 
                  const f=eval(n); 
                  if(typeof f==='function'){ 
                    console.log('[Grass检测] 发现标准函数:', n);
                    found.push(n);
                  } 
                }catch(e){} 
              } 
              
              // 检查 module.exports
              try{ 
                if (typeof module!=='undefined' && module && module.exports){ 
                  console.log('[Grass检测] 检查module.exports...');
                  if(typeof module.exports === 'function') {
                    console.log('[Grass检测] module.exports是函数，长度:', module.exports.toString().length);
                    found.push('module.exports');
                  }
                  if(typeof module.exports.search === 'function') {
                    console.log('[Grass检测] 发现module.exports.search');
                    found.push('module.exports.search');
                  }
                  // 检查module.exports的所有属性
                  for(const prop in module.exports) {
                    if(typeof module.exports[prop] === 'function') {
                      const funcStr = module.exports[prop].toString();
                      if(funcStr.length > 500) {
                        console.log('[Grass检测] module.exports属性:', prop, '长度:', funcStr.length);
                        found.push('module.exports.' + prop);
                      }
                    }
                  }
                }
              }catch(e){
                console.log('[Grass检测] module.exports检查异常:', e);
              } 
              
              // 特殊检测grass源 - 更智能的检测逻辑
              try{
                console.log('[Grass检测] 开始智能Grass源检测...');
                let grassCandidates = [];
                const blacklist = ['fetch', 'search', 'autoSearch', 'require', 'eval', 'setTimeout', 'setInterval', 'Promise', 'XMLHttpRequest', 'grassSearch', 'grassAutoSearch', '__ensureHoisted', 'normalizeGrassResult', 'normalizeGrassItem', '__networkCallback'];
                let totalFunctions = 0;
                
                for(const k in window){ 
                  try{ 
                    if(typeof window[k]==='function'){ 
                      totalFunctions++;
                      
                      if(blacklist.includes(k)) continue;
                      
                      const funcStr = window[k].toString();
                      console.log('[Grass检测] 检查函数:', k, '长度:', funcStr.length);
                      
                      // 针对野草🌾源的特殊检测
                      if(funcStr.length > 1500 && 
                         !funcStr.includes('[native code]') &&
                         !funcStr.includes('function fetch') &&
                         !funcStr.includes('JSBridge') &&
                         !funcStr.includes('NetworkBridge')
                      ){
                        // 检查是否包含音乐相关特征
                        const hasMusicFeatures = 
                          funcStr.includes('search') || 
                          funcStr.includes('music') || 
                          funcStr.includes('song') ||
                          funcStr.includes('qq') ||
                          funcStr.includes('netease') ||
                          funcStr.includes('kugou') ||
                          funcStr.includes('kuwo');
                          
                        // 检查是否包含网络请求特征
                        const hasNetworkFeatures = 
                          funcStr.includes('http') || 
                          funcStr.includes('url') || 
                          funcStr.includes('request') ||
                          funcStr.includes('fetch') ||
                          funcStr.includes('post') ||
                          funcStr.includes('get');
                          
                        // 检查是否包含数据处理特征  
                        const hasDataFeatures =
                          funcStr.includes('json') || 
                          funcStr.includes('data') || 
                          funcStr.includes('result') ||
                          funcStr.includes('response') ||
                          funcStr.includes('parse');
                          
                        // 检查是否是混淆代码（包含大量转义或编码）
                        const isObfuscated = 
                          funcStr.includes('\\x') ||
                          funcStr.includes('\\u') ||
                          funcStr.includes('0x') ||
                          /function\s*\w+\s*\(\s*\w+\s*,\s*\w+\s*\)/.test(funcStr);
                        
                        if((hasMusicFeatures && hasNetworkFeatures) || 
                           (hasDataFeatures && isObfuscated) ||
                           (hasMusicFeatures && isObfuscated)) {
                          console.log('[Grass检测] ✓ 候选Grass函数:', k, {
                            length: funcStr.length,
                            music: hasMusicFeatures,
                            network: hasNetworkFeatures, 
                            data: hasDataFeatures,
                            obfuscated: isObfuscated
                          });
                          grassCandidates.push(k);
                        }
                      }
                    }
                  }catch(e){
                    console.log('[Grass检测] 函数检查异常:', k, e);
                  } 
                }
                
                console.log('[Grass检测] 总函数数:', totalFunctions, '候选Grass函数:', grassCandidates.length);
                
                // 如果严格检测没有找到，尝试更宽松的检测
                if(grassCandidates.length === 0) {
                  console.log('[Grass检测] 严格检测无结果，尝试宽松检测...');
                  for(const k in window){ 
                    try{ 
                      if(typeof window[k]==='function' && !blacklist.includes(k)){ 
                        const funcStr = window[k].toString();
                        if(funcStr.length > 800 && 
                           !funcStr.includes('[native code]') &&
                           !funcStr.includes('JSBridge') &&
                           (funcStr.includes('search') || 
                            funcStr.includes('music') || 
                            funcStr.includes('0x') ||
                            funcStr.includes('\\x'))
                        ){
                          console.log('[Grass检测] 宽松检测候选函数:', k, '长度:', funcStr.length);
                          grassCandidates.push(k);
                        }
                      }
                    }catch(e){} 
                  }
                  console.log('[Grass检测] 宽松检测后共发现', grassCandidates.length, '个候选函数');
                }
                
                // 特别检查单字母函数名（混淆后常见模式）
                if(grassCandidates.length === 0) {
                  console.log('[Grass检测] 检查单字母/短函数名...');
                  for(const k in window) {
                    try {
                      if(typeof window[k] === 'function' && 
                         k.length <= 3 && 
                         !blacklist.includes(k) &&
                         k.match(/^[A-Za-z]$/)) {
                        const funcStr = window[k].toString();
                        if(funcStr.length > 2000) {
                          console.log('[Grass检测] 短名称大函数:', k, '长度:', funcStr.length);
                          grassCandidates.push(k);
                        }
                      }
                    } catch(e) {}
                  }
                }
                
                // 检查直接的导出函数
                const exportKeys = ['search', 'musicSearch', 'searchMusic', 'getMusic', 'query'];
                for(const key of exportKeys) {
                  if(window[key] && typeof window[key] === 'function' && !found.includes(key)) {
                    console.log('[Grass检测] 发现导出函数:', key);
                    grassCandidates.push(key);
                  }
                }
                
                if(grassCandidates.length > 0){
                  console.log('[Grass检测] ✅ 最终发现grass函数:', grassCandidates);
                  found.push(...grassCandidates);
                } else {
                  console.log('[Grass检测] ❌ 未发现任何grass函数');
                  // 输出所有可疑函数供调试
                  const suspiciousFuncs = [];
                  for(const k in window) {
                    if(typeof window[k] === 'function' && !blacklist.includes(k)) {
                      const len = window[k].toString().length;
                      if(len > 500) {
                        suspiciousFuncs.push({name: k, length: len});
                      }
                    }
                  }
                  console.log('[Grass检测] 所有可疑函数(>500字符):', suspiciousFuncs.slice(0, 10));
                }
              }catch(e){
                console.warn('[Grass检测] 检测异常:', e);
              }
              
              if(found.length){ 
                console.log('[Grass检测] ✅ 总共发现函数:', found);
                JSBridge.postMessage('adapter_found:'+found.join(',')); 
                return;
              } 
              
              // 通用函数扫描
              const g=[]; 
              for(const k in window){ 
                try{ 
                  if(typeof window[k]==='function' && k.toLowerCase().includes('search')) g.push(k);
                }catch(e){} 
              } 
              console.log('[Grass检测] 通用扫描结果:', g);
              JSBridge.postMessage('adapter_found:'+g.join(',')); 
            }catch(e){ 
              console.error('[Grass检测] 全局异常:', e);
              JSBridge.postMessage('adapter_found:'); 
            } 
          })()
        ''');
      } else {
        // 兜底：仍然尝试在页面里用 fetch 注入
        print('⚠️ [WebViewJsSource] Dart 下载失败，回退到 WebView 内 fetch 尝试');
        final escapedList = urls
            .map((u) => "'" + u.replaceAll("'", "") + "'")
            .join(',');
        final js =
            "(async()=>{const urls=[" +
            escapedList +
            "]; const safePost=(m)=>{try{ if(window.JSBridge && JSBridge.postMessage){ JSBridge.postMessage(m);} }catch(_){}}; const fetchWithTimeout=async(u,ms)=>{const ctrl=new AbortController(); const t=setTimeout(()=>ctrl.abort(),ms); try{const res=await fetch(u,{cache:'no-store',signal:ctrl.signal}); clearTimeout(t); return res}catch(e){clearTimeout(t); throw e}}; const injectLX=()=>{ try{ var g = (typeof globalThis !== 'undefined') ? globalThis : (this||{}); if(!g.lx){ g.lx = { EVENT_NAMES:{}, APP_EVENT_NAMES:{}, CURRENT_PLATFORM:'desktop', APP_SETTING:{}, version:'2.4.0', isDev:false, on:function(){}, off:function(){}, emit:function(){}, }; } }catch(e){} }; for (const u of urls){ try{ const res = await fetchWithTimeout(u, 8000); const t = await res.text(); injectLX(); eval(t); safePost('loaded:'+u); window.__js_loaded = true; break; }catch(e){ safePost('load_fail:'+u); }} safePost('adapter_probe:start'); try{ const found=[]; const cands=['search','searchImpl','search','musicSearch','searchMusic']; for(const n of cands){ try{ const f = eval(n); if(typeof f==='function'){ found.push(n);} }catch(e){} } if(found.length===0){ try{ const globals=[]; for (const k in window){ try{ if(typeof window[k]==='function' && k.toLowerCase().includes('search')) globals.push(k);}catch(e){} } safePost('adapter_found:'+globals.join(',')); }catch(e){ safePost('adapter_found:'); } } else { safePost('adapter_found:'+found.join(',')); } }catch(e){ safePost('adapter_found:'); } })()";
        await controller.runJavaScript(js);
      }
    }

    // 注入统一搜索适配器（静默模式，避免大量 console 消息导致 OOM）
    const adapter = r'''
      if (!window.__js_adapter_injected__) {
        window.__js_adapter_injected__ = true;
            // 将适配器命名为与当前来源一致，避免混淆
            if (!window.__grassAdapter__) window.__grassAdapter__ = {};
            
            // 结果标准化函数
            window.normalizeGrassResult = function(result) {
              console.log('[Normalizer] 开始标准化结果:', typeof result);
              
              if (!result) {
                console.log('[Normalizer] 结果为空');
                return [];
              }
              
              // 如果直接是数组
              if (Array.isArray(result)) {
                console.log('[Normalizer] 直接数组，长度:', result.length);
                return result.map((item, index) => {
                  try {
                    return window.normalizeGrassItem(item, index);
                  } catch(e) {
                    console.warn('[Normalizer] 项目', index, '标准化失败:', e);
                    return { title: 'Unknown', artist: 'Unknown' };
                  }
                });
              }
              
              // 检查嵌套结构
              const possibleKeys = ['data', 'list', 'songs', 'result', 'items', 'musics', 'tracks'];
              for (const key of possibleKeys) {
                if (result[key] && Array.isArray(result[key])) {
                  console.log('[Normalizer] 找到嵌套数组:', key, '长度:', result[key].length);
                  return result[key].map((item, index) => {
                    try {
                      return window.normalizeGrassItem(item, index);
                    } catch(e) {
                      console.warn('[Normalizer] 嵌套项目', index, '标准化失败:', e);
                      return { title: 'Unknown', artist: 'Unknown' };
                    }
                  });
                }
              }
              
              // 如果是单个对象，包装成数组
              if (typeof result === 'object' && result !== null) {
                console.log('[Normalizer] 单个对象，尝试转换');
                const normalized = window.normalizeGrassItem(result, 0);
                return normalized ? [normalized] : [];
              }
              
              console.log('[Normalizer] 无法识别的结果格式');
              return [];
            };
            
            // 单个项目标准化函数
            window.normalizeGrassItem = function(item, index) {
              if (!item || typeof item !== 'object') {
                console.log('[Normalizer] 项目', index, '不是对象:', typeof item);
                return { title: 'Unknown', artist: 'Unknown' };
              }
              
              console.log('[Normalizer] 处理项目', index, ':', JSON.stringify(item).substring(0, 100));
              
              const normalized = {};
              
              // 标题映射
              normalized.title = item.title || item.name || item.songName || item.song_name || item.musicname || '未知歌曲';
              
              // 艺术家映射
              normalized.artist = item.artist || item.singer || item.artistName || item.artist_name || 
                                 item.singerName || item.singer_name || item.author || '未知艺术家';
              
              // 专辑映射
              if (item.album || item.albumName || item.album_name) {
                normalized.album = item.album || item.albumName || item.album_name;
              }
              
              // 时长映射
              if (item.duration || item.time || item.length) {
                normalized.duration = item.duration || item.time || item.length;
              }
              
              // ID映射
              if (item.id || item.songId || item.song_id || item.mid || item.songmid) {
                normalized.id = item.id || item.songId || item.song_id || item.mid || item.songmid;
              }
              
              // 平台映射
              normalized.platform = item.platform || item.source || 'unknown';
              
              // 特殊字段映射（用于播放链接获取）
              if (item.songmid || item.mid) normalized.songmid = item.songmid || item.mid;
              if (item.hash) normalized.hash = item.hash;
              if (item.rid) normalized.rid = item.rid;
              if (item.fileId) normalized.fileId = item.fileId;
              
              // URL映射（如果直接包含播放链接）
              if (item.url || item.link || item.src) {
                normalized.url = item.url || item.link || item.src;
              }
              
              console.log('[Normalizer] 标准化后的项目', index, ':', JSON.stringify(normalized));
              return normalized;
            };
            
            // 确保在动态脚本完成后将 CommonJS 导出提升到全局
            window.__ensureHoisted = function(){
              try{
                if (typeof module !== 'undefined' && module && module.exports){
                  var exp = module.exports || {};
                  var list = ['search','searchMusic','search_music','getMediaSource','getMusic','query'];
                  for (var i=0;i<list.length;i++){
                    var k=list[i];
                    try{ if (!window[k] && typeof exp[k]==='function') window[k]=exp[k]; }catch(_){ }
                  }
                  if (exp.default && typeof exp.default==='object'){
                    var d=exp.default; var keys=Object.keys(d||{});
                    for (var j=0;j<keys.length;j++){
                      var p=keys[j];
                      try{ if (!window[p] && typeof d[p]==='function' && ['search','searchMusic','getMediaSource','query'].indexOf(p)>=0) window[p]=d[p]; }catch(_){ }
                    }
                  }
                }
              }catch(e){}
            };

            window.grassSearch = async function(platform, keyword, page){
          console.log('[Adapter] 草莓源搜索调用:', platform, keyword, page);
              // 先尝试一次提升
              try { window.__ensureHoisted && window.__ensureHoisted(); } catch(_) {}
              
              // 若关键函数仍不存在，则轮询等待动态脚本加载完成（最多5秒，草莓源需要更多时间）
              try {
                console.log('[Adapter] 等待草莓源动态脚本就绪...');
                console.log('[Adapter] 草莓源通常需要请求配置信息，耐心等待...');
                const needFns = ['searchMusic','search','module.exports.search'];
                let ok=false; let tries=0;
                while(tries<25){ // 增加到25次，总共5秒
                  let has=false;
                  try{
                    if (typeof searchMusic==='function' || typeof search==='function') {
                      has=true;
                      console.log('[Adapter] 发现全局函数');
                    }
                    // 重点检查module.exports
                    if (typeof module!=='undefined' && module && module.exports) {
                      console.log('[Adapter] module.exports检查:', Object.keys(module.exports || {}));
                      if (typeof module.exports === 'function') {
                        console.log('[Adapter] module.exports本身是函数');
                        has=true;
                      } else if (typeof module.exports.search === 'function') {
                        console.log('[Adapter] 发现module.exports.search');
                        has=true;
                      } else {
                        // 检查module.exports的所有方法
                        for(const prop in module.exports) {
                          if(typeof module.exports[prop] === 'function') {
                            console.log('[Adapter] module.exports方法:', prop);
                            has=true;
                          }
                        }
                      }
                    }
                  }catch(e){ 
                    console.log('[Adapter] 检查异常:', e.message);
                  }
                  if (has){ 
                    console.log('[Adapter] ✅ 草莓源函数已就绪');
                    ok=true; 
                    break; 
                  }
                  await new Promise(r=>setTimeout(r,200));
                  try { window.__ensureHoisted && window.__ensureHoisted(); } catch(_) {}
                  tries++;
                  
                  // 每5次尝试输出一次状态
                  if(tries % 5 === 0) {
                    console.log('[Adapter] 等待进度:', tries, '/25, 已等待', tries * 0.2, '秒');
                  }
                }
                if (!ok) {
                  console.log('[Adapter] ⚠️ 标准函数未就绪，但继续尝试智能检测');
                  console.log('[Adapter] 这可能是因为草莓源使用了更深层的混淆');
                  // 再等一会儿让混淆脚本完全加载和初始化
                  await new Promise(r=>setTimeout(r,1000));
                } else {
                  console.log('[Adapter] 🎉 草莓源初始化完成，开始搜索');
                }
              } catch(e) { 
                console.warn('[Adapter] 等待动态脚本异常:', e); 
              }
          // 优先尝试明确候选（重点关注module.exports）
              const candidates = [
            'module.exports', 'module.exports.search', 'search', 'musicSearch', 'searchMusic'
          ];
          for(const fnName of candidates) {
            try {
              const fn = eval(fnName);
              if(typeof fn === 'function') {
                console.log('[Adapter] 尝试函数:', fnName);
                
                // 尝试不同的参数组合适配不同的函数签名
                let result = null;
                let __selectedId = null;
                
                // 根据函数名选择不同的参数组合策略，并支持偏好策略优先
                let paramEntries = [];
                const __pref = (typeof window !== 'undefined' && window.__preferredStrategy) ? window.__preferredStrategy : '';
                if(fnName.includes('module.exports')) {
                  console.log('[Adapter] 使用module.exports专用参数组合');
                  paramEntries = [
                    { id: 'S1', params: [keyword, page||1, 'music'] },
                    { id: 'S2', params: [keyword, page||1] },
                    { id: 'S3', params: [{ text: keyword, page: page||1, type: 'music' }] },
                    { id: 'S4', params: [platform, keyword, page||1] },
                    // 其他备选（无固定策略编号）
                    { id: '', params: [keyword, page||1, 'song'] },
                    { id: '', params: ['qq', keyword, page||1] },
                    { id: '', params: ['netease', keyword, page||1] },
                    { id: '', params: [{ query: keyword, page: page||1, type: 'music' }] },
                    { id: '', params: [{ keyword: keyword, page: page||1, platform: platform }] },
                    { id: '', params: [keyword] },
                    { id: '', params: [1, keyword, page||1] },
                    { id: '', params: [0, keyword, page||1] },
                  ];
                } else {
                  // 标准函数的参数组合（S5）
                  paramEntries = [
                    { id: 'S5', params: [keyword, page||1] },
                    { id: '', params: [platform, keyword, page||1] },
                    { id: '', params: [keyword] },
                    { id: '', params: [{ query: keyword, page: page||1, platform: platform }] },
                  ];
                }
                // 偏好策略优先
                if (__pref) {
                  const idx = paramEntries.findIndex(e => e.id && e.id === __pref);
                  if (idx > 0) {
                    const p = paramEntries.splice(idx, 1)[0];
                    paramEntries.unshift(p);
                    console.log('[Adapter] 使用偏好策略优先:', __pref);
                  }
                }
                
                for(let i = 0; i < paramEntries.length; i++) {
                  const entry = paramEntries[i];
                  const params = entry.params;
                  try {
                    console.log('[Adapter] 尝试参数组合', (entry.id||('#'+(i+1))), ':', JSON.stringify(params));
                    result = await fn(...params);
                    console.log('[Adapter] 参数组合', (entry.id||('#'+(i+1))), '成功，结果:', result);
                    
                    // 检查结果是否有效
                    if(result && (Array.isArray(result) || (result.data && Array.isArray(result.data)))) {
                      console.log('[Adapter] 找到有效结果，使用参数组合', (entry.id||('#'+(i+1))));
                      if (entry.id) { try{ JSBridge.postMessage('strategy_selected:' + entry.id); }catch(_){} }
                      __selectedId = entry.id || __selectedId;
                      break;
                    }
                  } catch(e) {
                    console.log('[Adapter] 参数组合', (entry.id||('#'+(i+1))), '失败:', e.toString());
                    continue;
                  }
                }
                
                console.log('[Adapter] 函数结果:', fnName, result);
                
                // 处理Promise返回值
                if (result && typeof result.then === 'function') {
                  console.log('[Adapter] 检测到Promise，等待结果...');
                  try {
                    const promiseResult = await result;
                    console.log('[Adapter] Promise解析结果:', promiseResult);
                    result = promiseResult;
                    if(result && (Array.isArray(result) || (result.data && Array.isArray(result.data)))) {
                      if (!__selectedId) {
                        // 若之前未确认策略，但Promise解析后有效，则按S5或未知处理
                        if(!fnName.includes('module.exports')) { __selectedId = 'S5'; }
                      }
                      if (__selectedId) { try{ JSBridge.postMessage('strategy_selected:' + __selectedId); }catch(_){} }
                    }
                  } catch (promiseError) {
                    console.warn('[Adapter] Promise失败:', promiseError);
                    continue;
                  }
                }
                
                // 标准化返回格式
                if (result) {
                  if (Array.isArray(result)) {
                    console.log('[Adapter] 返回数组，长度:', result.length);
                    if (__selectedId) { try{ JSBridge.postMessage('strategy_selected:' + __selectedId); }catch(_){} }
                    return result;
                  }
                  if (result.data && Array.isArray(result.data)) {
                    console.log('[Adapter] 返回result.data，长度:', result.data.length);
                    if (__selectedId) { try{ JSBridge.postMessage('strategy_selected:' + __selectedId); }catch(_){} }
                    return result.data;
                  }
                  if (result.list && Array.isArray(result.list)) {
                    console.log('[Adapter] 返回result.list，长度:', result.list.length);
                    if (__selectedId) { try{ JSBridge.postMessage('strategy_selected:' + __selectedId); }catch(_){} }
                    return result.list;
                  }
                  // 如果是对象但不是数组，尝试转换
                  if (typeof result === 'object' && result !== null) {
                    const keys = Object.keys(result);
                    console.log('[Adapter] 对象结果，键值:', keys);
                    if (keys.length > 0) {
                      for (const key of ['songs', 'data', 'list', 'result', 'items']) {
                        if (result[key] && Array.isArray(result[key])) {
                          console.log('[Adapter] 找到数组字段:', key, '长度:', result[key].length);
                          return result[key];
                        }
                      }
                    }
                  }
                }
              }
            } catch(e) {
              console.warn('[Adapter] 函数调用失败:', fnName, e);
            }
          }
          
          // CommonJS: module.exports.search(query, page, type) 
          try {
            if (typeof module !== 'undefined' && module && module.exports && typeof module.exports.search === 'function') {
              console.log('[Adapter] 尝试 module.exports.search');
              const res = await module.exports.search(keyword, page||1, 'music');
              console.log('[Adapter] module.exports.search 结果:', res);
              
              if (res) {
                if (Array.isArray(res)) return res;
                if (res.data && Array.isArray(res.data)) return res.data;
                if (res.list && Array.isArray(res.list)) return res.list;
              }
            }
          } catch(e) {
            console.warn('[Adapter] module.exports.search 失败:', e);
          }
          
          // MusicFree format: 特殊处理xiaoqiu等MusicFree格式脚本
          try {
            if (typeof module !== 'undefined' && module && module.exports) {
              // 检查是否是MusicFree格式
              const exp = module.exports;
              if (exp.platform && (exp.search || exp.searchMusic)) {
                console.log('[Adapter] 检测到MusicFree格式，尝试搜索');
                const searchFn = exp.search || exp.searchMusic;
                if (typeof searchFn === 'function') {
                  // MusicFree格式通常需要特定的查询对象
                  const query = { 
                    keyword: keyword, 
                    page: page || 1,
                    type: 'music' // 添加类型参数
                  };
                  
                  // 调用搜索函数
                  const res = await searchFn(query);
                  console.log('[Adapter] MusicFree搜索结果:', res);
                  
                  // 处理不同的返回格式
                  if (res) {
                    // 直接是数组
                    if (Array.isArray(res) && res.length > 0) {
                      return res;
                    }
                    
                    // 包装在对象中
                    if (typeof res === 'object') {
                      const keys = ['data', 'list', 'songs', 'result', 'items'];
                      for (const key of keys) {
                        if (res[key] && Array.isArray(res[key]) && res[key].length > 0) {
                          console.log('[Adapter] 找到MusicFree结果数组:', key, res[key].length);
                          return res[key];
                        }
                      }
                      
                      // 检查是否有嵌套结构
                      if (res.code === 0 || res.success) {
                        for (const key of keys) {
                          if (res[key] && Array.isArray(res[key]) && res[key].length > 0) {
                            return res[key];
                          }
                        }
                      }
                    }
                    
                    // 如果是Promise，等待结果
                    if (res && typeof res.then === 'function') {
                      console.log('[Adapter] MusicFree返回Promise，等待结果...');
                      const promiseRes = await res;
                      if (promiseRes && Array.isArray(promiseRes)) {
                        return promiseRes;
                      }
                    }
                  }
                }
              }
            }
          } catch(e) {
            console.warn('[Adapter] MusicFree格式搜索失败:', e);
          }
          
          // 特殊处理 Grass 源：更智能的参数检测和调用
          try {
            console.log('[Adapter] 开始Grass源智能检测和调用...');
            const grassFunctions = [];
            const blacklist = ['fetch', 'search', 'autoSearch', 'require', 'eval', 'setTimeout', 'setInterval', 'Promise', 'XMLHttpRequest', 'grassSearch', 'grassAutoSearch', '__ensureHoisted', 'normalizeGrassResult', 'normalizeGrassItem', '__networkCallback'];
            
            // 第一轮：搜索可能的草莓源函数（严格模式）
            console.log('[Adapter] 第一轮：严格模式检测...');
            for(const k in window) {
              try {
                if(typeof window[k] === 'function' && !blacklist.includes(k)) {
                  const funcStr = window[k].toString();
                  
                  // 针对野草🌾源的特征检测（高度混淆的代码）
                  if(funcStr.length > 1500 && 
                     !funcStr.includes('[native code]') &&
                     !funcStr.includes('JSBridge') &&
                     !funcStr.includes('NetworkBridge')
                  ) {
                    // 检查混淆特征
                    const isObfuscated = 
                      funcStr.includes('\\x') ||
                      funcStr.includes('\\u') ||
                      funcStr.includes('0x') ||
                      /function\s*[A-Z]\s*\([^)]*\)/.test(funcStr);
                      
                    // 检查音乐功能特征
                    const hasMusicFeatures = 
                      funcStr.includes('search') || 
                      funcStr.includes('music') || 
                      funcStr.includes('song') ||
                      funcStr.includes('qq') ||
                      funcStr.includes('netease');
                      
                    // 检查网络特征
                    const hasNetworkFeatures = 
                      funcStr.includes('http') || 
                      funcStr.includes('url') || 
                      funcStr.includes('request') ||
                      funcStr.includes('fetch');
                      
                    if(isObfuscated || (hasMusicFeatures && hasNetworkFeatures)) {
                      console.log('[Adapter] ✓ 严格检测到Grass候选函数:', k, {
                        length: funcStr.length,
                        obfuscated: isObfuscated,
                        music: hasMusicFeatures,
                        network: hasNetworkFeatures
                      });
                      grassFunctions.push(k);
                    }
                  }
                }
              } catch(e) {
                console.log('[Adapter] 严格检测异常:', k, e);
              }
            }
            
            console.log('[Adapter] 严格模式发现', grassFunctions.length, '个候选函数');
            
            // 第二轮：如果严格模式没找到，使用宽松检测
            if(grassFunctions.length === 0) {
              console.log('[Adapter] 第二轮：宽松模式检测...');
              for(const k in window) {
                try {
                  if(typeof window[k] === 'function' && !blacklist.includes(k)) {
                    const funcStr = window[k].toString();
                    // 宽松条件：长度>800且包含关键模式
                    if(funcStr.length > 800 && 
                       !funcStr.includes('[native code]') &&
                       !funcStr.includes('JSBridge') &&
                       (funcStr.includes('search') || 
                        funcStr.includes('music') || 
                        funcStr.includes('0x') ||
                        funcStr.includes('\\x') ||
                        funcStr.includes('request'))
                    ) {
                      console.log('[Adapter] 宽松检测候选函数:', k, '长度:', funcStr.length);
                      grassFunctions.push(k);
                    }
                  }
                } catch(e) {}
              }
              console.log('[Adapter] 宽松模式共发现', grassFunctions.length, '个候选函数');
            }
            
            // 第三轮：检查短函数名（混淆后常见的单字母函数名）
            if(grassFunctions.length === 0) {
              console.log('[Adapter] 第三轮：短函数名检测...');
              for(const k in window) {
                try {
                  if(typeof window[k] === 'function' && 
                     !blacklist.includes(k) &&
                     k.length <= 3 && 
                     k.match(/^[A-Za-z]$/)) {
                    const funcStr = window[k].toString();
                    if(funcStr.length > 2000) {
                      console.log('[Adapter] 短名称大函数:', k, '长度:', funcStr.length);
                      grassFunctions.push(k);
                    }
                  }
                } catch(e) {}
              }
            }
            
            // 第四轮：重点检查module.exports（草莓源的主要导出方式）
            console.log('[Adapter] 第四轮：module.exports深度检测...');
            try {
              if(typeof module !== 'undefined' && module && module.exports) {
                console.log('[Adapter] module存在，类型:', typeof module);
                console.log('[Adapter] module.exports存在，类型:', typeof module.exports);
                
                if(typeof module.exports === 'function') {
                  const funcStr = module.exports.toString();
                  console.log('[Adapter] ✓ module.exports是函数，长度:', funcStr.length);
                  
                  // 对于草莓源，即使函数较短也可能是主函数
                  if(funcStr.length > 100) {
                    console.log('[Adapter] ✓ module.exports作为候选函数');
                    grassFunctions.push('module.exports');
                  }
                } 
                
                if(typeof module.exports === 'object' && module.exports !== null) {
                  console.log('[Adapter] module.exports是对象，检查属性...');
                  const keys = Object.keys(module.exports);
                  console.log('[Adapter] module.exports属性:', keys);
                  
                  for(const prop of keys) {
                    try {
                      if(typeof module.exports[prop] === 'function') {
                        const funcStr = module.exports[prop].toString();
                        console.log('[Adapter] 方法', prop, '长度:', funcStr.length);
                        
                        // 草莓源的方法可能比较短，降低阈值
                        if(funcStr.length > 100) {
                          console.log('[Adapter] ✓ module.exports.' + prop + '作为候选函数');
                          grassFunctions.push('module.exports.' + prop);
                        }
                      }
                    } catch(e) {
                      console.log('[Adapter] 检查属性', prop, '异常:', e.message);
                    }
                  }
                }
                
                // 尝试检查特殊的键名模式（混淆后可能的名称）
                if(module.exports) {
                  const specialKeys = ['default', 'search', 'query', 'find', 'get'];
                  for(const key of specialKeys) {
                    if(module.exports[key] && typeof module.exports[key] === 'function') {
                      console.log('[Adapter] ✓ 发现特殊键:', key);
                      grassFunctions.push('module.exports.' + key);
                    }
                  }
                }
              } else {
                console.log('[Adapter] module.exports不存在或为空');
              }
            } catch(e) {
              console.log('[Adapter] module.exports检测异常:', e.message);
            }
            
            // 最后检查：导出的标准函数
            const exportKeys = ['search', 'musicSearch', 'searchMusic', 'getMusic', 'query'];
            for(const key of exportKeys) {
              if(window[key] && typeof window[key] === 'function' && !grassFunctions.includes(key)) {
                console.log('[Adapter] 发现标准导出函数:', key);
                grassFunctions.push(key);
              }
            }
            
            console.log('[Adapter] 总共发现', grassFunctions.length, '个候选Grass函数:', grassFunctions);
            
            // 尝试调用这些函数
            for(const funcName of grassFunctions) {
              try {
                console.log('[Adapter] 🔍 开始分析Grass函数:', funcName);
                
                // 获取函数对象（支持嵌套路径）
                let grassFunc;
                if(funcName.includes('.')) {
                  console.log('[Adapter] 解析嵌套函数路径:', funcName);
                  const parts = funcName.split('.');
                  grassFunc = window;
                  for(const part of parts) {
                    grassFunc = grassFunc ? grassFunc[part] : null;
                    if(!grassFunc) {
                      console.log('[Adapter] 路径中断于:', part);
                      break;
                    }
                  }
                } else {
                  grassFunc = window[funcName];
                }
                
                if(typeof grassFunc !== 'function') {
                  console.log('[Adapter] ❌ 不是函数，跳过:', funcName, typeof grassFunc);
                  continue;
                }
                
                const funcStr = grassFunc.toString();
                console.log('[Adapter] 函数长度:', funcStr.length, '字符');
                
                // 分析函数参数个数和特征
                let paramCount = 0;
                let hasComplexParams = false;
                
                try {
                  // 多种参数解析方式
                  const patterns = [
                    /function[^(]*\(([^)]*)\)/,
                    /\(([^)]*)\)\s*=>/,
                    /\(([^)]*)\)\s*\{/,
                    /^[^(]*\(([^)]*)\)/
                  ];
                  
                  let paramMatch = null;
                  for(const pattern of patterns) {
                    paramMatch = funcStr.match(pattern);
                    if(paramMatch) break;
                  }
                  
                  if(paramMatch && paramMatch[1]) {
                    const paramStr = paramMatch[1].trim();
                    if(paramStr) {
                      const params = paramStr.split(',')
                        .map(p => p.trim())
                        .filter(p => p && !p.startsWith('/*') && !p.startsWith('//'));
                      paramCount = params.length;
                      hasComplexParams = params.some(p => p.includes('{') || p.includes('='));
                      console.log('[Adapter] 解析到参数:', params);
                    }
                  }
                  
                  // 如果解析失败，尝试.length
                  if(paramCount === 0) {
                    try {
                      paramCount = grassFunc.length || 0;
                      console.log('[Adapter] 通过.length获取参数个数:', paramCount);
                    } catch(e) {
                      console.log('[Adapter] .length获取失败，默认为0');
                    }
                  }
                } catch(e) {
                  console.log('[Adapter] 参数解析异常:', e);
                  paramCount = 0;
                }
                
                console.log('[Adapter] 📊 函数分析结果:', {
                  name: funcName,
                  paramCount: paramCount,
                  hasComplexParams: hasComplexParams,
                  length: funcStr.length
                });
                
                // 智能生成调用参数组合
                let grassParams = [];
                
                // 对于野草🌾这类高度混淆的源，尝试多种调用模式
                if(paramCount === 0) {
                  console.log('[Adapter] 无参函数，可能需要全局变量');
                  // 先设置可能需要的全局变量
                  try {
                    window.__grass_query = keyword;
                    window.__grass_page = page || 1;
                    window.__grass_platform = platform;
                  } catch(e) {}
                  grassParams = [[]];
                  
                } else if(paramCount === 1) {
                  console.log('[Adapter] 单参函数，尝试多种数据格式');
                  grassParams = [
                    // 直接传关键词
                    [keyword],
                    // 传数字（可能是某种索引）
                    [1], [0], [page || 1],
                    // 传对象配置
                    [{query: keyword, page: page||1, platform: platform}],
                    [{keyword: keyword, page: page||1}],
                    [{q: keyword, p: page||1}],
                    [{text: keyword}],
                    // 传平台标识
                    [platform], ['qq'], ['tx'], ['netease'], ['wy']
                  ];
                  
                } else if(paramCount === 2) {
                  console.log('[Adapter] 双参函数，尝试常见组合');
                  grassParams = [
                    // 关键词+页码
                    [keyword, page||1],
                    // 平台+关键词
                    [platform, keyword],
                    ['qq', keyword], ['tx', keyword], ['netease', keyword],
                    // 关键词+平台
                    [keyword, platform],
                    [keyword, 'qq'], [keyword, 'tx'],
                    // 两个数字参数（混淆后可能的模式）
                    [1, 1], [0, 1], [page||1, 1],
                    // 对象+字符串
                    [{query: keyword, page: page||1}, platform],
                    [{keyword: keyword}, platform]
                  ];
                  
                } else if(paramCount === 3) {
                  console.log('[Adapter] 三参函数，尝试标准和变体组合');
                  grassParams = [
                    // 标准格式
                    [platform, keyword, page||1],
                    [keyword, page||1, platform],
                    // QQ音乐格式
                    ['qq', keyword, page||1],
                    ['tx', keyword, page||1],
                    // 网易云格式  
                    ['netease', keyword, page||1],
                    ['wy', keyword, page||1],
                    // 其他可能格式
                    [keyword, platform, page||1],
                    [keyword, page||1, 'music'],
                    [1, keyword, page||1],
                    [0, keyword, page||1]
                  ];
                  
                } else {
                  console.log('[Adapter] 多参函数，尝试扩展格式');
                  grassParams = [
                    // 标准多参数格式
                    [platform, keyword, page||1, 'music'],
                    [platform, keyword, page||1, 'song'],
                    ['qq', keyword, page||1, 'music'],
                    ['netease', keyword, page||1, 'music'],
                    // 可能的配置对象格式
                    [{platform: platform, query: keyword, page: page||1, type: 'music'}],
                    [{source: platform, keyword: keyword, page: page||1}]
                  ];
                }
                
                console.log('[Adapter] 🚀 开始尝试', grassParams.length, '种参数组合');
                
                // 逐个尝试参数组合
                for(let i = 0; i < grassParams.length; i++) {
                  try {
                    const params = grassParams[i];
                    console.log(`[Adapter] 🔄 尝试组合 ${i+1}/${grassParams.length}:`, 
                               JSON.stringify(params).substring(0, 100) + '...');
                    
                    // 设置调用超时
                    let grassResult;
                    const callPromise = new Promise(async (resolve, reject) => {
                      try {
                        let result;
                        // 尝试直接调用
                        try {
                          result = grassFunc(...params);
                        } catch(directError) {
                          console.log('[Adapter] 直接调用失败，尝试call绑定:', directError.message);
                          result = grassFunc.call(window, ...params);
                        }
                        resolve(result);
                      } catch(error) {
                        reject(error);
                      }
                    });
                    
                    // 5秒超时
                    grassResult = await Promise.race([
                      callPromise,
                      new Promise((_, reject) => 
                        setTimeout(() => reject(new Error('Call timeout')), 5000)
                      )
                    ]);
                    
                    // 处理Promise结果
                    if(grassResult && typeof grassResult.then === 'function') {
                      console.log('[Adapter] 🔄 函数返回Promise，等待异步结果...');
                      try {
                        grassResult = await Promise.race([
                          grassResult,
                          new Promise((_, reject) => 
                            setTimeout(() => reject(new Error('Promise timeout')), 8000)
                          )
                        ]);
                      } catch(promiseError) {
                        console.log('[Adapter] ⏰ Promise超时:', promiseError.message);
                        continue;
                      }
                    }
                    
                    console.log('[Adapter] 📦 函数返回结果类型:', typeof grassResult);
                    console.log('[Adapter] 📦 结果预览:', 
                               JSON.stringify(grassResult).substring(0, 200) + '...');
                    
                    // 验证和标准化结果
                    const validResult = window.normalizeGrassResult(grassResult);
                    
                    if(validResult && validResult.length > 0) {
                      console.log('[Adapter] ✅ 成功获取', validResult.length, '个搜索结果！');
                      console.log('[Adapter] 🎵 前3个结果预览:');
                      validResult.slice(0, 3).forEach((item, idx) => {
                        console.log(`  ${idx+1}. ${item.title || 'Unknown'} - ${item.artist || 'Unknown'}`);
                      });
                      return validResult;
                    } else {
                      console.log('[Adapter] ⚠️ 结果为空或格式不正确');
                    }
                    
                  } catch(e) {
                    console.log(`[Adapter] ❌ 组合${i+1}失败:`, e.message);
                  }
                }
                
                console.log('[Adapter] 😞', funcName, '的所有参数组合都失败了');
                
              } catch(e) {
                console.error('[Adapter] ❌ Grass函数', funcName, '完全失败:', e);
              }
            }
          } catch(e) {
            console.warn('[Adapter] Grass源检测异常:', e);
          }
          
          // 最后尝试：直接调用可能的草莓源模式
          try {
            console.log('[Adapter] 尝试直接草莓源模式...');
            
            // 草莓源可能的调用模式
            const directPatterns = [
              // 直接调用全局函数
              `if(typeof searchMusic === 'function') return await searchMusic('${keyword}', ${page||1});`,
              `if(typeof search === 'function') return await search('${platform}', '${keyword}', ${page||1});`,
              `if(typeof query === 'function') return await query({keyword: '${keyword}', page: ${page||1}, platform: '${platform}'});`,
              
              // 检查window下的方法
              `if(window.searchMusic) return await window.searchMusic('${keyword}', ${page||1});`,
              `if(window.search) return await window.search('${platform}', '${keyword}', ${page||1});`,
              
              // 检查可能的模块导出
              `if(typeof module !== 'undefined' && module.exports && module.exports.search) return await module.exports.search('${keyword}', ${page||1});`,
              
              // 尝试eval某些模式
              `try { return await eval('searchMusic')('${keyword}', ${page||1}); } catch(e) {}`,
              `try { return await eval('search')('${platform}', '${keyword}', ${page||1}); } catch(e) {}`
            ];
            
            for(let i = 0; i < directPatterns.length; i++) {
              try {
                console.log('[Adapter] 尝试直接模式', i+1);
                const result = await eval('(async () => { ' + directPatterns[i] + ' return null; })()');
                
                if(result && Array.isArray(result) && result.length > 0) {
                  console.log('[Adapter] 直接模式成功，返回:', result.length, '个结果');
                  return result;
                }
              } catch(e) {
                console.log('[Adapter] 直接模式', i+1, '失败:', e.toString());
              }
            }
          } catch(e) {
            console.warn('[Adapter] 直接模式异常:', e);
          }
          
          console.log('[Adapter] 所有方法都失败，返回空数组');
          return [];
        };
        window.grassAutoSearch = async function(keyword, page){
          const plats=['qq','netease','kuwo','kugou'];
          for(const p of plats){ 
            try{ 
              const r=await window.grassSearch(p, keyword, page||1); 
              if(r && Array.isArray(r) && r.length > 0) return r; 
            }catch(e){
              console.warn('[Adapter] 平台搜索失败:', p, e);
            } 
          }
          return [];
        };
      }
      ''';
    await controller.runJavaScript(adapter);
    await controller.runJavaScript(
      "try{JSBridge.postMessage('adapter_injected')}catch(e){}",
    );

    print('✅ [WebViewJsSource] WebView音源初始化完成！');
    print('⏰ [WebViewJsSource] 等待草莓源配置加载完成...');

    // 给草莓源额外2秒时间完成网络请求和初始化
    await Future.delayed(const Duration(seconds: 2));

    print('🎯 [WebViewJsSource] 草莓源准备就绪，可以开始搜索');
    _inited = true;
    if (!_ready.isCompleted) _ready.complete();
  }

  String _computeScriptKey() {
    final url = _loadedScriptUrlFromJs ?? _currentSettings?.scriptUrl ?? '';
    return url;
  }

  Future<void> _loadStrategyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString('webview_script_strategy_cache_v1');
      if (text != null && text.isNotEmpty) {
        final data = jsonDecode(text);
        if (data is Map<String, dynamic>) {
          _strategyCache = data;
        }
      }
      print('🧠 [Strategy] 已加载策略缓存，条目数: ${_strategyCache.length}');
    } catch (e) {
      print('⚠️ [Strategy] 加载策略缓存失败: $e');
      _strategyCache = <String, dynamic>{};
    }
  }

  Future<void> _saveStrategyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'webview_script_strategy_cache_v1',
        jsonEncode(_strategyCache),
      );
    } catch (e) {
      print('⚠️ [Strategy] 保存策略缓存失败: $e');
    }
  }

  /// 轻量探测：在 WebView 中重新扫描可用搜索函数
  Future<Map<String, dynamic>> detectAdapterFunctions() async {
    await _ready.future;
    try {
      _pendingProbe = Completer<List<String>>();
      const String probeJs = r'''(function(){
        const safePost=(m)=>{try{ if(window.JSBridge && JSBridge.postMessage){ JSBridge.postMessage(m);} }catch(_){}};
        try{
          const found=[];
          const cands=['search','searchImpl','search','musicSearch','searchMusic'];
          for(const n of cands){ try{ const f = eval(n); if(typeof f==='function'){ found.push(n);} }catch(e){} }
          if(found.length===0){
            try{
              const globals=[];
              for(const k in window){ try{ if(typeof window[k]==='function' && k.toLowerCase().includes('search')) globals.push(k);}catch(e){} }
              safePost('adapter_found:'+globals.join(','));
            }catch(e){ safePost('adapter_found:'); }
          } else {
            safePost('adapter_found:'+found.join(','));
          }
        }catch(e){ safePost('adapter_found:'); }
      })()''';
      await controller.runJavaScript(probeJs);
      final List<String> names = await _pendingProbe!.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => <String>[],
      );
      return {'ok': names.isNotEmpty, 'functions': names};
    } catch (_) {
      return {'ok': false, 'functions': <String>[]};
    } finally {
      _pendingProbe = null;
    }
  }

  Future<List<Map<String, dynamic>>> search(
    String keyword, {
    String platform = 'auto',
    int page = 1,
  }) async {
    print('🔍 [WebViewJsSource] =============== 开始草莓源搜索 ===============');
    print('🔍 [WebViewJsSource] 搜索关键词: "$keyword"');
    print('🔍 [WebViewJsSource] 目标平台: $platform');
    print('🔍 [WebViewJsSource] 页面: $page');
    print('🔍 [WebViewJsSource] 适配器状态: ${_hasValidAdapter ? "已确认" : "未确认"}');
    print('🔍 [WebViewJsSource] 已发现函数: $_lastFoundFunctions');

    await _ready.future;

    final escaped = keyword.replaceAll("'", " ");
    print('🔍 [WebViewJsSource] 转义后关键词: "$escaped"');

    // 在JS环境中设置当前脚本Key与偏好策略（若有）
    try {
      final String key = _computeScriptKey();
      final dynamic entry = key.isNotEmpty ? _strategyCache[key] : null;
      final String pref =
          (entry is Map && entry['strategyId'] is String)
              ? (entry['strategyId'] as String)
              : '';
      final String jsPref =
          "(function(){try{window.__currentScriptKey='" +
          key.replaceAll("'", "") +
          "'; window.__preferredStrategy='" +
          pref.replaceAll("'", "") +
          "'}catch(e){}})()";
      await controller.runJavaScript(jsPref);
      if (pref.isNotEmpty) {
        print('🧠 [Strategy] 使用缓存策略: $pref (key=$key)');
      }
    } catch (e) {
      print('⚠️ [Strategy] 注入偏好策略失败: $e');
    }

    // 无论探测结果如何，优先尝试使用已注入的 grass 适配器
    if (!_hasValidAdapter) {
      print('⚠️ [WebViewJsSource] 适配器函数状态未确认，但继续尝试执行');
      print('⚠️ [WebViewJsSource] 这可能是因为草莓源使用了高度混淆的函数名');
    } else {
      print('✅ [WebViewJsSource] 适配器状态正常，开始搜索');
    }
    // moved earlier
    // 调用前先尝试确保导出函数被提升
    await controller.runJavaScript(
      "try{window.__ensureHoisted && window.__ensureHoisted()}catch(e){}",
    );
    final fn =
        platform == 'auto'
            ? "window.grassAutoSearch('" +
                escaped +
                "'," +
                page.toString() +
                ")"
            : "window.grassSearch('" +
                platform +
                "','" +
                escaped +
                "'," +
                page.toString() +
                ")";
    // 使用事件机制代替同步返回，解决异步 Promise 问题
    // 若存在尚未完成的搜索，直接取消并丢弃其结果，避免串扰
    if (_pendingSearchCompleter != null &&
        !_pendingSearchCompleter!.isCompleted) {
      print('⚠️ [WebViewJsSource] 取消上一次未完成的搜索（被新请求打断）');
      _pendingSearchCompleter!.complete(<Map<String, dynamic>>[]);
    }
    // 为当前搜索生成唯一ID
    _activeSearchId = DateTime.now().microsecondsSinceEpoch.toString();
    final String sid = _activeSearchId ?? '';
    final js = """
      (function(){
        try{
          console.log('[WebView] 开始异步搜索，使用事件回调');
          function sendResult(data) {
            try {
              window.JSBridge.postMessage('search_result:' + '__SID__' + ':' + JSON.stringify(data));
            } catch(e) {
              console.error('[WebView] 发送结果失败:', e);
            }
          }
          
          async function doSearch() {
            try {
              console.log('[WebView] 开始执行搜索函数');
              const r = await ($fn);
              console.log('[WebView] 搜索函数返回:', r);
              
              const norm=(x)=>{try{if(Array.isArray(x)){console.log('[WebView] 返回数组，长度:', x.length);return x;} if(x&&Array.isArray(x.data)){console.log('[WebView] 返回x.data，长度:', x.data.length);return x.data;} if(x&&Array.isArray(x.list)){console.log('[WebView] 返回x.list，长度:', x.list.length);return x.list;} if(x&&Array.isArray(x.songs)){console.log('[WebView] 返回x.songs，长度:', x.songs.length);return x.songs;} if(typeof x === 'object' && x !== null){const keys = Object.keys(x); console.log('[WebView] 对象键值:', keys); for(const key of ['data','list','songs','result','items']){if(x[key] && Array.isArray(x[key])){console.log('[WebView] 找到数组字段:', key, '长度:', x[key].length);return x[key];}}}}catch(e){console.warn('[WebView] norm错误:', e);} return [];};
              
              const result = norm(r);
              console.log('[WebView] 最终结果数量:', result.length);
              
              const safeResult = result.map((item,index)=>{try{console.log('[WebView] 原始项目',index,':', JSON.stringify(item)); const safe={};if(item.title||item.name)safe.title=item.title||item.name;if(item.artist||item.singer)safe.artist=item.artist||item.singer;if(item.album)safe.album=item.album;if(item.duration)safe.duration=item.duration;if(item.url||item.link)safe.url=item.url||item.link;if(item.id)safe.id=item.id;if(item.platform)safe.platform=item.platform; else safe.platform='$platform';if(item.songmid)safe.songmid=item.songmid;if(item.hash)safe.hash=item.hash;console.log('[WebView] 映射后项目',index,':', JSON.stringify(safe));return safe;}catch(e){console.warn('[WebView] 项目',index,'序列化失败:', e);return {title:'Unknown',artist:'Unknown'};}});
              
              console.log('[WebView] 安全结果数量:', safeResult.length);
              window.__js_last_json = safeResult;
              sendResult(safeResult);
            } catch(e) {
              console.error('[WebView] 搜索异常:', e);
              window.__js_last_json = [];
              sendResult([]);
            }
          }
          
          doSearch();
          return 'async_started';
        } catch(e) {
          console.error('[WebView] 启动搜索失败:', e);
          return '[]';
        }
      })()
    """.replaceAll('\$fn', fn).replaceAll('__SID__', sid);
    print('🔄 [WebViewJsSource] 启动异步搜索...');

    // 准备接收搜索结果的 Completer
    _pendingSearchCompleter = Completer<List<Map<String, dynamic>>>();

    // 启动搜索
    await controller.runJavaScript(js);
    print('🔄 [WebViewJsSource] 搜索已启动，等待结果...');

    // 等待搜索结果事件（带超时）
    print('⏰ [WebViewJsSource] 等待搜索结果，超时时间: 15秒');
    try {
      final result = await (_pendingSearchCompleter?.future ??
              Future.value(<Map<String, dynamic>>[]))
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              print('⏰ [WebViewJsSource] 搜索超时！尝试读取备份变量');
              print('⏰ [WebViewJsSource] 这可能表示草莓源函数调用失败或返回异常');
              // 超时时清理 Completer
              _pendingSearchCompleter = null;
              return <Map<String, dynamic>>[];
            },
          );

      if (result.isNotEmpty) {
        print('✅ [WebViewJsSource] 🎉 通过事件回调成功获得 ${result.length} 个搜索结果');
        print('✅ [WebViewJsSource] 结果预览:');
        for (int i = 0; i < math.min(3, result.length); i++) {
          final item = result[i];
          print(
            '  ${i + 1}. ${item['title'] ?? 'Unknown'} - ${item['artist'] ?? 'Unknown'}',
          );
        }
        return result;
      } else {
        print('⚠️ [WebViewJsSource] 事件回调返回空结果');
      }
    } catch (e) {
      print('❌ [WebViewJsSource] 等待搜索结果异常: $e');
      print('❌ [WebViewJsSource] 异常类型: ${e.runtimeType}');
      _pendingSearchCompleter = null;
    }

    // 兜底：从备份变量读取
    print('🔄 [WebViewJsSource] 从备份变量读取结果...');
    try {
      final backup = await controller.runJavaScriptReturningResult(
        "(function(){try{console.log('[BackupRead] 备份变量类型:', typeof window.__js_last_json); console.log('[BackupRead] 备份变量长度:', window.__js_last_json ? window.__js_last_json.length : 'null'); return JSON.stringify(window.__js_last_json||[]);}catch(e){console.error('[BackupRead] 错误:', e); return '[]'}})()",
      );

      if (backup is String && backup.isNotEmpty && backup != '[]') {
        final parsed = jsonDecode(backup);
        if (parsed is List) {
          final out =
              parsed
                  .where((e) => e is Map)
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList();
          print('✅ [WebViewJsSource] 从备份变量成功解析 ${out.length} 项');
          return out;
        }
      }
    } catch (e) {
      print('⚠️ [WebViewJsSource] 备份读取失败: $e');
    }

    // 最后兜底：尝试 LX 事件总线协议
    try {
      print('🔄 [WebViewJsSource] 适配器无结果，回退到 LX 事件协议');
      final String p = platform == 'auto' ? 'qq' : platform;
      final String jsEvt =
          "(async()=>{try{ if(window.lx && lx.EVENT_NAMES && typeof lx.emit==='function'){ const evt = lx.EVENT_NAMES.SOURCE_SEARCH || 'SOURCE_SEARCH'; const payload={ source: '" +
          p +
          "', text: '" +
          escaped +
          "', page: " +
          page.toString() +
          " }; const r = await lx.emit(evt, payload); return JSON.stringify(r||[]);} return '[]'; }catch(e){ return '[]'; } })()";
      final resEvt = await controller.runJavaScriptReturningResult(jsEvt);
      final textEvt = resEvt is String ? resEvt : resEvt.toString();
      final data = jsonDecode(textEvt);
      if (data is List) {
        final out =
            data
                .where((e) => e is Map)
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList();
        if (out.isNotEmpty) {
          print('✅ [WebViewJsSource] LX 事件协议返回 ${out.length} 项');
          return out;
        }
      }
    } catch (e) {
      print('⚠️ [WebViewJsSource] LX 协议兜底失败: $e');
    }

    print('📤 [WebViewJsSource] 最终返回空结果');
    return const [];
  }

  Future<String?> resolveMusicUrl({
    required String platform,
    required String songId,
    String quality = '320k',
  }) async {
    await _ready.future;

    // 平台映射 (LX Music格式)
    String lxPlatform = platform;
    switch (platform.toLowerCase()) {
      case 'qq':
      case 'tencent':
        lxPlatform = 'tx';
        break;
      case 'netease':
      case '163':
        lxPlatform = 'wy';
        break;
      case 'kuwo':
        lxPlatform = 'kw';
        break;
      case 'kugou':
        lxPlatform = 'kg';
        break;
      case 'migu':
        lxPlatform = 'mg';
        break;
      case 'auto':
      default:
        // auto或未知平台默认使用腾讯QQ音乐
        lxPlatform = 'tx';
        print('🔄 [WebViewJsSource] 平台 "$platform" 映射到默认平台 "tx"');
        break;
    }

    print('🔗 [WebViewJsSource] 开始解析播放链接');
    print('🔗 原始平台: $platform -> LX平台: $lxPlatform');
    print('🔗 歌曲ID: $songId, 质量: $quality');

    final String js = """
      (async()=>{
        try{
          console.log('[URL解析] 开始解析，songId: $songId, platform: $lxPlatform, quality: $quality');
          
          // 优先尝试 Music Free 格式 (xiaoqiu.js)
          if(typeof getMediaSource === 'function'){
            console.log('[URL解析] 检测到 Music Free 格式，使用 getMediaSource');
            
            const musicItem = {
              id: '$songId',
              songmid: '$songId'
            };
            
                            // xiaoqiu.js 的质量参数映射
                const qualityMap = {
                  '128k': 'low',
                  '320k': 'standard',
                  'flac': 'high',
                  'default': 'standard'
                };
                const mappedQuality = qualityMap['$quality'] || qualityMap['default'];
                
                console.log('[URL解析] 调用 getMediaSource，参数:', JSON.stringify(musicItem), '质量:', '$quality', '->', mappedQuality);
                const result = await getMediaSource(musicItem, mappedQuality);
                console.log('[URL解析] getMediaSource 返回结果:', result);
                
                // 检查返回结果是否包含警告信息和版权问题
                if(result && result.msg && result.msg.includes('无法获取播放链接')) {
                  console.warn('[URL解析] ⚠️ QQ音乐获取失败:', result.msg);
                  
                  if(result.url && result.url.includes('kuwo.cn')) {
                    console.warn('[URL解析] ⚠️ 检测到版权问题：API回退到酷我音乐，但该音源可能没有版权');
                    console.log('[URL解析] 为避免播放失败，拒绝使用有版权问题的链接');
                    
                    // 直接发送空结果，提示用户版权问题
                    window.JSBridge.postMessage('url_result:COPYRIGHT_ERROR');
                    return;
                  }
                }
            
            if(result) {
              let finalUrl = '';
              if(typeof result === 'string') {
                finalUrl = result;
              } else if(result.url && typeof result.url === 'string') {
                finalUrl = result.url;
              } else if(result.link && typeof result.link === 'string') {
                finalUrl = result.link;
              }
              
              if(finalUrl && finalUrl.length > 0) {
                console.log('[URL解析] Music Free 格式成功，返回URL:', finalUrl);
                window.JSBridge.postMessage('url_result:' + finalUrl);
                return;
              } else {
                console.log('[URL解析] Music Free 返回了无效结果:', JSON.stringify(result));
              }
            }
          }
          
          // 回退到 LX Music 格式  
          if(window.lx && lx.EVENT_NAMES && typeof lx.emit==='function'){ 
            console.log('[URL解析] 回退到 LX Music 格式');
            const payload = { 
              action: 'musicUrl', 
              source: '$lxPlatform', 
              info: { 
                type: '$quality', 
                musicInfo: { 
                  songmid: '$songId', 
                  hash: '$songId' 
                } 
              } 
            };
            console.log('[URL解析] LX请求参数:', JSON.stringify(payload));
            
            const url = await lx.emit(lx.EVENT_NAMES.request, payload);
            console.log('[URL解析] LX返回结果:', url);
            
            if(typeof url==='string' && url.length > 0) {
              console.log('[URL解析] LX成功获取字符串URL:', url);
              window.JSBridge.postMessage('url_result:' + url);
              return;
            }
            if(url && url.url && url.url.length > 0) {
              console.log('[URL解析] LX成功获取对象URL:', url.url);
              window.JSBridge.postMessage('url_result:' + url.url);
              return;
            }
          }
          
          // 特殊处理 Grass 源：尝试调用混淆后的URL解析函数
          try {
            console.log('[URL解析] 尝试Grass源混淆函数解析...');
            const grassFunctions = [];
            
            // 搜索可能的草莓源URL解析函数
            for(const k in window) {
              try {
                if(typeof window[k] === 'function') {
                  const funcStr = window[k].toString();
                  // 检查函数体特征 - 寻找可能的URL解析函数
                  if(funcStr.length > 500 && (
                    funcStr.includes('url') || 
                    funcStr.includes('link') || 
                    funcStr.includes('http') ||
                    funcStr.includes('music') ||
                    funcStr.includes('stream') ||
                    funcStr.includes('play')
                  )) {
                    grassFunctions.push(k);
                  }
                }
              } catch(e) {}
            }
            
            console.log('[URL解析] 发现', grassFunctions.length, '个候选Grass URL解析函数');
            
            // 尝试调用这些函数进行URL解析
            for(const funcName of grassFunctions) {
              try {
                console.log('[URL解析] 尝试Grass URL函数:', funcName);
                const grassFunc = window[funcName];
                
                // 尝试不同的参数组合
                const urlParams = [
                  [lxPlatform, songId, quality],
                  [songId, quality],
                  [songId],
                  [{platform: lxPlatform, id: songId, quality: quality}],
                  [{id: songId, songmid: songId, platform: lxPlatform}],
                ];
                
                for(let i = 0; i < urlParams.length; i++) {
                  try {
                    console.log('[URL解析] 尝试Grass参数组合', i+1, ':', JSON.stringify(urlParams[i]));
                    let urlResult = grassFunc(...urlParams[i]);
                    
                    // 处理Promise
                    if(urlResult && typeof urlResult.then === 'function') {
                      console.log('[URL解析] Grass函数返回Promise，等待结果...');
                      urlResult = await urlResult;
                    }
                    
                    console.log('[URL解析] Grass URL结果:', urlResult);
                    
                    // 检查结果
                    if(urlResult) {
                      let finalUrl = null;
                      
                      if(typeof urlResult === 'string' && urlResult.startsWith('http')) {
                        finalUrl = urlResult;
                      } else if(urlResult.url && typeof urlResult.url === 'string') {
                        finalUrl = urlResult.url;
                      } else if(urlResult.link && typeof urlResult.link === 'string') {
                        finalUrl = urlResult.link;
                      } else if(urlResult.src && typeof urlResult.src === 'string') {
                        finalUrl = urlResult.src;
                      }
                      
                      if(finalUrl && finalUrl.length > 0) {
                        console.log('[URL解析] Grass源成功解析URL:', finalUrl);
                        window.JSBridge.postMessage('url_result:' + finalUrl);
                        return;
                      }
                    }
                  } catch(e) {
                    console.log('[URL解析] Grass参数组合', i+1, '失败:', e.toString());
                    continue;
                  }
                }
              } catch(e) {
                console.warn('[URL解析] Grass函数', funcName, '调用失败:', e);
                continue;
              }
            }
          } catch(e) {
            console.warn('[URL解析] Grass源URL解析异常:', e);
          }
          
          console.error('[URL解析] 所有方法都失败了');
          console.log('[URL解析] getMediaSource存在:', typeof getMediaSource);
          console.log('[URL解析] window.lx存在:', !!window.lx);
          if(window.lx) {
            console.log('[URL解析] lx.EVENT_NAMES存在:', !!lx.EVENT_NAMES);  
            console.log('[URL解析] lx.emit类型:', typeof lx.emit);
          }
          window.JSBridge.postMessage('url_result:');
          return;
        } catch(e) {
          console.error('[URL解析] 异常:', e);
          window.JSBridge.postMessage('url_result:');
          return;
        }
      })()
    """;

    // 设置等待URL解析结果的 Completer
    _pendingUrlCompleter = Completer<String>();

    // 启动异步URL解析
    await controller.runJavaScript(js);

    // 等待结果，设置更长超时以适配慢源
    try {
      final result = await _pendingUrlCompleter!.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          print('⏰ [WebViewJsSource] URL解析超时');
          return '';
        },
      );

      _pendingUrlCompleter = null;

      if (result.isEmpty || result == 'null' || result == 'undefined') {
        print('❌ [WebViewJsSource] URL解析失败');
        return null;
      }

      print('✅ [WebViewJsSource] URL解析成功: $result');
      return result;
    } catch (e) {
      print('❌ [WebViewJsSource] URL解析异常: $e');
      _pendingUrlCompleter = null;
      return null;
    }
  }
}
