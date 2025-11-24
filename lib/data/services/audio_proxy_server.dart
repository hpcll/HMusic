import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// 音频代理服务器
/// 用于代理音乐CDN的音频流，解决小爱音箱无法直接访问某些CDN的问题
class AudioProxyServer {
  HttpServer? _server;
  final Dio _dio = Dio();
  int _port = 8090;
  String? _localIp;

  // 🎯 健康检查定时器
  Timer? _healthCheckTimer;

  // 🎯 请求统计
  int _totalRequests = 0;
  int _successRequests = 0;
  int _failedRequests = 0;

  // 服务器是否正在运行
  bool get isRunning => _server != null;

  // 获取代理服务器地址
  String get serverUrl => 'http://$_localIp:$_port';

  // 获取统计信息
  Map<String, int> get stats => {
    'total': _totalRequests,
    'success': _successRequests,
    'failed': _failedRequests,
  };

  /// 启动代理服务器
  Future<bool> start({int port = 8090}) async {
    if (_server != null) {
      debugPrint('⚠️ [ProxyServer] 服务器已在运行');
      return true;
    }

    try {
      _port = port;

      // 🔍 获取本地IP地址
      _localIp = await _getLocalIp();
      if (_localIp == null) {
        debugPrint('❌ [ProxyServer] 无法获取本地IP地址');
        return false;
      }

      debugPrint('🌐 [ProxyServer] 本地IP: $_localIp');

      // 🚀 启动HTTP服务器
      final handler = const shelf.Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(shelf.logRequests())
          .addHandler(_router);

      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        _port,
      );

      debugPrint('✅ [ProxyServer] 代理服务器已启动: $serverUrl');

      // 🎯 启动健康检查
      _startHealthCheck();

      return true;
    } catch (e) {
      debugPrint('❌ [ProxyServer] 启动失败: $e');
      _server = null;
      return false;
    }
  }

  /// 🎯 启动健康检查（每30秒检查一次）
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _performHealthCheck();
    });
    debugPrint('⏰ [ProxyServer] 健康检查已启动');
  }

  /// 🎯 执行健康检查
  void _performHealthCheck() {
    if (_server == null) {
      debugPrint('⚠️ [ProxyServer] 健康检查失败：服务器未运行');
      _healthCheckTimer?.cancel();
      return;
    }

    debugPrint('💚 [ProxyServer] 健康检查通过 - 统计: ${_totalRequests}次请求, ${_successRequests}次成功, ${_failedRequests}次失败');
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (_server != null) {
      // 🎯 停止健康检查
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;

      await _server!.close();
      _server = null;

      debugPrint('👋 [ProxyServer] 代理服务器已停止');
      debugPrint('📊 [ProxyServer] 最终统计: ${_totalRequests}次请求, ${_successRequests}次成功, ${_failedRequests}次失败');
    }
  }

  /// 路由处理
  Future<shelf.Response> _router(shelf.Request request) async {
    final path = request.url.path;

    if (path == 'proxy') {
      return await _handleProxy(request);
    } else if (path == 'health') {
      return shelf.Response.ok('OK');
    }

    return shelf.Response.notFound('Not Found');
  }

  /// 处理代理请求
  Future<shelf.Response> _handleProxy(shelf.Request request) async {
    _totalRequests++; // 🎯 统计总请求数

    try {
      // 获取 base64 编码的 URL
      final urlB64 = request.url.queryParameters['urlb64'];
      if (urlB64 == null || urlB64.isEmpty) {
        _failedRequests++; // 🎯 统计失败请求
        return shelf.Response.badRequest(body: 'Missing urlb64 parameter');
      }

      // 解码 URL
      final urlBytes = base64.decode(urlB64);
      final originalUrl = utf8.decode(urlBytes);
      debugPrint('🔗 [ProxyServer] 代理请求 #$_totalRequests: $originalUrl');

      // 🎯 发起HTTP请求获取音频流
      final response = await _dio.get(
        originalUrl,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          headers: {
            'User-Agent': 'Wget/1.21.3',
            'Accept': '*/*',
            'Accept-Encoding': 'identity',
            'Connection': 'Keep-Alive',
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200) {
        _failedRequests++; // 🎯 统计失败请求
        debugPrint('❌ [ProxyServer] 上游响应错误: ${response.statusCode}');
        return shelf.Response(response.statusCode ?? 500);
      }

      // 🎵 获取响应头
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        // 只转发必要的响应头
        if (name.toLowerCase() == 'content-type' ||
            name.toLowerCase() == 'content-length' ||
            name.toLowerCase() == 'accept-ranges') {
          headers[name] = values.join(', ');
        }
      });

      // 📡 流式转发音频数据
      final stream = response.data.stream;
      _successRequests++; // 🎯 统计成功请求
      debugPrint('✅ [ProxyServer] 开始流式转发音频数据 (成功率: ${(_successRequests / _totalRequests * 100).toStringAsFixed(1)}%)');

      return shelf.Response.ok(
        stream,
        headers: headers,
      );
    } catch (e) {
      _failedRequests++; // 🎯 统计失败请求
      debugPrint('❌ [ProxyServer] 代理请求失败: $e');
      return shelf.Response.internalServerError(body: 'Proxy error: $e');
    }
  }

  /// CORS 中间件
  shelf.Middleware _corsMiddleware() {
    return (innerHandler) {
      return (request) async {
        final response = await innerHandler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': '*',
        });
      };
    };
  }

  /// 获取本地IP地址
  Future<String?> _getLocalIp() async {
    try {
      // 🔍 获取所有网络接口
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // 优先选择 WiFi/以太网接口
      for (var interface in interfaces) {
        // 跳过虚拟网络接口
        if (interface.name.contains('docker') ||
            interface.name.contains('veth') ||
            interface.name.contains('br-')) {
          continue;
        }

        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            // 优先选择局域网IP
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.')) {
              debugPrint('📱 [ProxyServer] 选择网络接口: ${interface.name} ($ip)');
              return ip;
            }
          }
        }
      }

      // 如果没有找到局域网IP，返回第一个可用的
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }

      return null;
    } catch (e) {
      debugPrint('❌ [ProxyServer] 获取IP地址失败: $e');
      return null;
    }
  }

  /// 生成代理URL
  String getProxyUrl(String originalUrl) {
    final urlB64 = base64.encode(utf8.encode(originalUrl));
    return '$serverUrl/proxy?urlb64=$urlB64';
  }
}
