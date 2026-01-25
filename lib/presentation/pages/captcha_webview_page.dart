import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView 验证码页面
/// 在 WebView 中显示小米验证码页面，用户完成验证后自动关闭
class CaptchaWebViewPage extends StatefulWidget {
  final String captchaUrl;
  final void Function(Map<String, String>? cookies) onVerificationComplete;

  const CaptchaWebViewPage({
    super.key,
    required this.captchaUrl,
    required this.onVerificationComplete,
  });

  @override
  State<CaptchaWebViewPage> createState() => _CaptchaWebViewPageState();
}

class _CaptchaWebViewPageState extends State<CaptchaWebViewPage> {
  late WebViewController _webViewController;
  bool _isLoading = true;
  bool _verificationHandled = false; // 防止重复处理

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('🌐 [WebView] 页面开始加载: $url');
            setState(() {
              _isLoading = true;
            });
          },
          // 🎯 关键修复：在导航请求阶段拦截 STS 回调
          // 不要等页面加载完成，因为 STS 页面可能返回 HTTP 错误
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('🔗 [WebView] 导航请求: ${request.url}');

            // 防止重复处理
            if (_verificationHandled) {
              return NavigationDecision.prevent;
            }

            // 🎯 检测 STS 回调 URL
            if (request.url.contains('api2.mina.mi.com/sts')) {
              debugPrint('✅ [WebView] 检测到 STS 回调，验证已完成！');
              _verificationHandled = true;

              // 🎯 立即标记验证完成，不等待页面加载
              // STS 页面可能返回 HTTP 错误，但验证实际上已经完成
              _handleVerificationComplete();

              // 阻止导航到 STS 页面（避免 HTTP 错误）
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) async {
            debugPrint('🌐 [WebView] 页面加载完成: $url');
            setState(() {
              _isLoading = false;
            });

            // 防止重复处理（备用检测，如果 onNavigationRequest 没有拦截到）
            if (_verificationHandled) {
              return;
            }

            // 🎯 备用检测：如果页面 URL 包含 STS，说明验证成功
            if (url.contains('api2.mina.mi.com/sts')) {
              debugPrint('✅ [WebView] 检测到验证完成 (STS 回调 - 备用检测)');
              _verificationHandled = true;

              // 🎯 直接读取页面内容，这是一个 JSON 响应，包含 serviceToken
              await _extractServiceTokenFromPage();
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ [WebView] 加载错误: ${error.description}');
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.captchaUrl));
  }

  /// 🎯 处理验证完成（在 onNavigationRequest 中调用）
  /// 当检测到导航到 STS URL 时，立即标记验证完成
  void _handleVerificationComplete() {
    debugPrint('🎯 [WebView] 处理验证完成...');

    // 标记验证完成
    final cookies = <String, String>{
      '_stsVerified': 'true',
    };

    debugPrint('🍪 [WebView] 验证完成，返回标记: _stsVerified=true');

    // 延迟一下确保状态更新
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        widget.onVerificationComplete(cookies);
        Navigator.of(context).pop();
      }
    });
  }

  /// 🎯 从 STS 页面提取 serviceToken
  /// STS 页面返回的是 JSON 格式，包含 serviceToken 等认证信息
  Future<void> _extractServiceTokenFromPage() async {
    try {
      // 读取页面内容（JSON 格式）
      final pageContent = await _webViewController.runJavaScriptReturningResult(
        'document.body.innerText'
      );

      debugPrint('📄 [WebView] STS 页面内容: $pageContent');

      // 解析 JSON
      String jsonStr = pageContent.toString();
      // 移除引号包裹
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
      }
      // 处理转义字符
      jsonStr = jsonStr.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');

      debugPrint('📄 [WebView] 清理后的 JSON: $jsonStr');

      final Map<String, dynamic> stsResponse = json.decode(jsonStr);

      debugPrint('📄 [WebView] STS 响应解析成功: ${stsResponse.keys}');

      // 🎯 提取关键认证信息
      final cookies = <String, String>{};

      // serviceToken 可能在不同字段中
      if (stsResponse.containsKey('serviceToken')) {
        cookies['serviceToken'] = stsResponse['serviceToken'].toString();
        debugPrint('✅ [WebView] 提取到 serviceToken');
      }

      if (stsResponse.containsKey('userId')) {
        cookies['userId'] = stsResponse['userId'].toString();
        debugPrint('✅ [WebView] 提取到 userId: ${cookies['userId']}');
      }

      if (stsResponse.containsKey('ssecurity')) {
        cookies['ssecurity'] = stsResponse['ssecurity'].toString();
        debugPrint('✅ [WebView] 提取到 ssecurity');
      }

      if (stsResponse.containsKey('passToken')) {
        cookies['passToken'] = stsResponse['passToken'].toString();
        debugPrint('✅ [WebView] 提取到 passToken');
      }

      if (stsResponse.containsKey('nonce')) {
        cookies['nonce'] = stsResponse['nonce'].toString();
        debugPrint('✅ [WebView] 提取到 nonce');
      }

      // 标记验证完成
      cookies['_stsVerified'] = 'true';

      debugPrint('🍪 [WebView] 最终提取的认证信息: ${cookies.keys}');

      // 延迟一下确保用户能看到成功状态
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        widget.onVerificationComplete(cookies);
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('⚠️ [WebView] 解析 STS 响应失败: $e');
      debugPrint('⚠️ [WebView] 尝试从 Cookie 中获取认证信息...');

      // 回退方案：从 Cookie 中获取
      var cookies = await _extractCookies();

      // 🎯 关键：即使 Cookie 提取失败，也要标记验证已完成
      // 因为已经导航到 STS 页面，说明验证已通过，服务器已记录
      cookies ??= <String, String>{};
      cookies['_stsVerified'] = 'true';

      debugPrint('🔧 [WebView] 标记验证已完成，即使 Cookie 为空');

      if (mounted) {
        widget.onVerificationComplete(cookies);
        Navigator.of(context).pop();
      }
    }
  }

  /// 🎯 从 WebView 中提取 Cookie（备用方案）
  Future<Map<String, String>?> _extractCookies() async {
    try {
      // 使用 JavaScript 获取 Cookie（必须在同域页面上）
      final cookieString = await _webViewController.runJavaScriptReturningResult(
        'document.cookie'
      );

      debugPrint('🍪 [WebView] 原始 Cookie 字符串: $cookieString');

      // 解析 Cookie 字符串
      final cookies = <String, String>{};
      final cleanCookieString = cookieString.toString().replaceAll('"', '');

      if (cleanCookieString.isNotEmpty && cleanCookieString != 'null') {
        final pairs = cleanCookieString.split('; ');
        for (final pair in pairs) {
          final index = pair.indexOf('=');
          if (index > 0) {
            final key = pair.substring(0, index);
            final value = pair.substring(index + 1);
            cookies[key] = value;
            debugPrint('🍪 [WebView] Cookie: $key=${value.length > 20 ? "${value.substring(0, 20)}..." : value}');
          }
        }
      }

      return cookies.isNotEmpty ? cookies : null;
    } catch (e) {
      debugPrint('❌ [WebView] 提取 Cookie 失败: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小米账号验证'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
