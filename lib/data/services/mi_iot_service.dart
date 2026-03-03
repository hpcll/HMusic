import 'dart:async';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'mi_hardware_detector.dart';
import 'mi_audio_id_generator.dart';
import 'mi_play_mode.dart';
import 'audio_proxy_server.dart';
import 'music_cdn_url_policy.dart';
import '../../core/utils/network_detector.dart';

/// 小米IoT直连服务
/// 不依赖xiaomusic服务端，直接调用小米云端API控制小爱音箱
class MiIoTService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  String? _serviceToken;
  String? _userId;
  String? _ssecurity;
  String? _deviceId;
  String? _passToken;

  // 设备列表缓存
  List<MiDevice> _devices = [];

  // 🎯 代理服务器（用于转发音频流）
  AudioProxyServer? _proxyServer;

  // 🎯 公共音频代理URL（Cloudflare Workers）
  String? _publicProxyUrl;

  // 🎯 实验开关：QQ 音乐链接是否直连音箱（跳过本地/公共代理）
  static const bool _enableQqDirectPlayExperiment = false;

  // 登录状态
  bool get isLoggedIn => _serviceToken != null && _userId != null;

  // 🎯 持久化的 deviceId key
  static const String _keyDeviceId = 'mi_iot_device_id';

  // 🎯 防止竞态条件：确保 deviceId 只加载一次
  Completer<void>? _deviceIdLoadCompleter;
  bool _deviceIdLoaded = false;

  MiIoTService() {
    _startLoadingDeviceId();
  }

  /// 🎯 启动 deviceId 加载（构造函数中调用）
  void _startLoadingDeviceId() {
    if (_deviceIdLoadCompleter != null) return;
    _deviceIdLoadCompleter = Completer<void>();
    _loadPersistedDeviceIdInternal().then((_) {
      _deviceIdLoaded = true;
      _deviceIdLoadCompleter!.complete();
    }).catchError((e) {
      _deviceIdLoaded = true;
      _deviceIdLoadCompleter!.complete();
    });
  }

  /// 🎯 等待 deviceId 加载完成（供外部和内部方法调用）
  Future<void> ensureDeviceIdLoaded() async {
    if (_deviceIdLoaded && _deviceId != null) return;
    if (_deviceIdLoadCompleter == null) {
      _startLoadingDeviceId();
    }
    await _deviceIdLoadCompleter!.future;
  }

  /// 🎯 内部方法：从 SharedPreferences 加载持久化的 deviceId
  Future<void> _loadPersistedDeviceIdInternal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDeviceId = prefs.getString(_keyDeviceId);

      if (savedDeviceId != null && savedDeviceId.isNotEmpty) {
        _deviceId = savedDeviceId;
        print('🔧 [MiIoT] 加载持久化的 deviceId: $_deviceId');
      } else {
        // 如果没有保存的 deviceId，生成新的并保存
        _deviceId = _generateDeviceId();
        await prefs.setString(_keyDeviceId, _deviceId!);
        print('✅ [MiIoT] 生成并保存新的 deviceId: $_deviceId');
      }
    } catch (e) {
      print('⚠️ [MiIoT] 加载持久化 deviceId 失败: $e，生成新的');
      _deviceId = _generateDeviceId();
    }
  }

  /// 🎯 （已废弃）从 SharedPreferences 加载持久化的 deviceId
  /// 现在请使用 ensureDeviceIdLoaded()
  Future<void> _loadPersistedDeviceId() async {
    await ensureDeviceIdLoaded();
  }

  /// 🎯 设置公共音频代理URL（Cloudflare Workers）
  /// 格式: https://your-worker.workers.dev
  void setPublicProxyUrl(String? proxyUrl) {
    _publicProxyUrl = proxyUrl?.trim();
    if (_publicProxyUrl != null && _publicProxyUrl!.isNotEmpty) {
      // 移除末尾斜杠
      if (_publicProxyUrl!.endsWith('/')) {
        _publicProxyUrl = _publicProxyUrl!.substring(0, _publicProxyUrl!.length - 1);
      }
      print('✅ [MiIoT] 已设置公共代理: $_publicProxyUrl');
    } else {
      _publicProxyUrl = null;
      print('⚠️ [MiIoT] 公共代理已清除');
    }
  }

  /// 🎯 获取公共代理URL（供外部读取）
  String? get publicProxyUrl => _publicProxyUrl;

  /// 🎯 设置代理服务器（用于音频流转发）
  /// 必须在播放音乐前设置，否则将尝试直接播放（可能失败）
  void setProxyServer(AudioProxyServer? proxyServer) {
    _proxyServer = proxyServer;
    if (proxyServer != null) {
      print('✅ [MiIoT] 已设置代理服务器: ${proxyServer.serverUrl}');
    } else {
      print('⚠️ [MiIoT] 代理服务器已清除，将使用直接播放（可能不稳定）');
    }
  }

  /// 生成随机设备ID
  String _generateDeviceId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// 登录小米账号
  /// 返回是否登录成功
  /// 🎯 登录返回结果
  Map<String, dynamic>? _lastLoginResponse;

  /// 🎯 获取上次登录响应（用于验证码场景）
  Map<String, dynamic>? get lastLoginResponse => _lastLoginResponse;

  String _maskValue(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.length <= 6) return '***';
    return '${value.substring(0, 3)}***${value.substring(value.length - 3)}';
  }

  Map<String, String> _maskCookieMap(Map<String, String> cookies) {
    final masked = <String, String>{};
    cookies.forEach((k, v) {
      if (k == 'passToken' || k == 'serviceToken' || k == 'ssecurity') {
        masked[k] = _maskValue(v);
      } else {
        masked[k] = v;
      }
    });
    return masked;
  }

  Future<bool> login(String account, String password, {String? captchaCode}) async {
    try {
      print('🔐 [MiIoT] 开始登录小米账号: $account');
      if (captchaCode != null) {
        print('🔐 [MiIoT] 使用验证码登录: $captchaCode');
      }

      // 🎯 确保 deviceId 已加载（使用 Completer 防止竞态条件）
      await ensureDeviceIdLoaded();

      print('🔧 [MiIoT] 使用 deviceId: $_deviceId');

      // 设置请求头和Cookie
      final headers = {
        'User-Agent': 'APP/com.xiaomi.mihome APPV/6.0.103 iosPassportSDK/3.9.0 iOS/14.4 miHSTS',
      };

      // 1. 获取登录sign
      print('📡 [MiIoT] 请求URL: https://account.xiaomi.com/pass/serviceLogin');

      final signResponse = await _dio.get(
        'https://account.xiaomi.com/pass/serviceLogin',
        queryParameters: {
          'sid': 'micoapi',
          '_json': 'true',
        },
        options: Options(
          headers: {
            ...headers,
            'Cookie': 'sdkVersion=3.9; deviceId=$_deviceId',
          },
          responseType: ResponseType.plain, // 强制返回字符串，不自动解析JSON
        ),
      );

      print('📡 [MiIoT] 响应状态: ${signResponse.statusCode}');
      print('📡 [MiIoT] 响应类型: ${signResponse.data.runtimeType}');

      // 🎯 打印完整的响应内容（用于诊断）
      final rawSignData = signResponse.data.toString();
      print('📡 [MiIoT] ===== 完整的Sign响应 =====');
      print(rawSignData);
      print('📡 [MiIoT] ===== Sign响应结束 =====');

      final signData = _parseJsonResponse(signResponse.data);
      if (signData == null) {
        print('❌ [MiIoT] 获取sign失败');
        return false;
      }

      print('📝 [MiIoT] 获取sign成功: ${signData.keys.toList()}');

      final sign = signData['_sign'] as String?;
      final qs = signData['qs'] as String?;
      final sid = signData['sid'] as String?;
      final callback = signData['callback'] as String?;

      if (sign == null) {
        print('❌ [MiIoT] sign为空');
        return false;
      }

      print('📝 [MiIoT] sign: $sign');

      // 🎯 保存 Sign 阶段的 location（用于验证码场景）
      final signLocation = signData['location'] as String?;
      print('📝 [MiIoT] Sign 阶段的 location: $signLocation');

      // 2. 计算密码MD5 (大写)
      final passwordHash = md5.convert(utf8.encode(password)).toString().toUpperCase();

      // 3. 登录请求
      final loginData = {
        '_json': 'true',
        'qs': qs ?? '',
        'sid': sid ?? 'micoapi',
        '_sign': sign,
        'callback': callback ?? '',
        'user': account,
        'hash': passwordHash,
      };

      // 🎯 如果提供了验证码，添加到请求参数中
      if (captchaCode != null && captchaCode.isNotEmpty) {
        loginData['captCode'] = captchaCode;
        print('📝 [MiIoT] 添加验证码参数: captCode=$captchaCode');
      }

      // 🎯 打印完整的请求参数
      print('📝 [MiIoT] ===== 登录请求参数 =====');
      print('📝 [MiIoT] URL: https://account.xiaomi.com/pass/serviceLoginAuth2');
      print('📝 [MiIoT] 请求头:');
      print('  User-Agent: ${headers['User-Agent']}');
      print('  Cookie: sdkVersion=3.9; deviceId=$_deviceId');
      print('📝 [MiIoT] 请求体 (Form Data):');
      loginData.forEach((key, value) {
        if (value.toString().length > 100) {
          print('  $key: ${value.toString().substring(0, 100)}...');
        } else {
          print('  $key: $value');
        }
      });
      print('📝 [MiIoT] ===== 登录请求结束 =====');

      final loginResponse = await _dio.post(
        'https://account.xiaomi.com/pass/serviceLoginAuth2',
        data: loginData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            ...headers,
            'Cookie': 'sdkVersion=3.9; deviceId=$_deviceId',
          },
          responseType: ResponseType.plain, // 防止自动解析JSON
        ),
      );

      // 🎯 打印完整的登录响应内容（用于诊断）
      final rawLoginData = loginResponse.data.toString();
      print('📡 [MiIoT] ===== 完整的登录响应 =====');
      print(rawLoginData);
      print('📡 [MiIoT] ===== 登录响应结束 =====');

      // 🎯 打印响应头（可能包含重要信息）
      print('📡 [MiIoT] 登录响应头:');
      loginResponse.headers.forEach((key, values) {
        print('  $key: $values');
      });

      final loginResponseData = _parseJsonResponse(loginResponse.data);
      if (loginResponseData == null) {
        print('❌ [MiIoT] 登录响应解析失败');
        return false;
      }

      print('📝 [MiIoT] 登录响应: code=${loginResponseData['code']}, desc=${loginResponseData['desc']}');

      // 🎯 打印所有响应字段（用于诊断）
      print('📝 [MiIoT] 登录响应中的所有字段:');
      loginResponseData.forEach((key, value) {
        if (value is String && value.length > 100) {
          print('  $key: ${value.substring(0, 100)}...');
        } else {
          print('  $key: $value');
        }
      });

      // 🎯 关键字段检查
      print('📝 [MiIoT] 关键字段检查:');
      print('  location: ${loginResponseData['location'] ?? "❌ 缺失"}');
      print('  ssecurity: ${loginResponseData['ssecurity'] ?? "❌ 缺失"}');
      print('  nonce: ${loginResponseData['nonce'] ?? "❌ 缺失"}');
      print('  userId: ${loginResponseData['userId'] ?? "❌ 缺失"}');
      final passToken = loginResponseData['passToken']?.toString();
      print('  passToken: ${passToken == null ? "❌ 缺失" : _maskValue(passToken)}');
      print('  notificationUrl: ${loginResponseData['notificationUrl'] ?? "❌ 缺失"}');
      print('  securityStatus: ${loginResponseData['securityStatus'] ?? "❌ 缺失"}');

      // 🎯 保存登录响应（用于UI层提取验证码URL）
      _lastLoginResponse = loginResponseData;

      // 检查登录结果
      if (loginResponseData['code'] != 0) {
        final errorCode = loginResponseData['code'];
        final errorDesc = loginResponseData['desc'] ?? loginResponseData['description'];

        // 🎯 特殊处理验证码错误（错误码70016）
        if (errorCode == 70016) {
          var captchaUrl = loginResponseData['captchaUrl'] as String?;

          // 🎯 如果登录认证返回的 captchaUrl 为空，使用 Sign 阶段的 location
          if ((captchaUrl == null || captchaUrl.isEmpty) && signLocation != null && signLocation.isNotEmpty) {
            captchaUrl = signLocation;
            print('⚠️ [MiIoT] 登录认证未返回 captchaUrl，使用 Sign 阶段的 location');
          }

          print('⚠️ [MiIoT] 需要验证码登录');
          print('⚠️ [MiIoT] 验证码URL: $captchaUrl');

          // 🎯 将验证码URL保存到响应中，供 UI 层使用
          loginResponseData['captchaUrl'] = captchaUrl;

          // 返回 false，但保留 _lastLoginResponse 供UI层使用
          return false;
        }

        print('❌ [MiIoT] 登录失败: $errorDesc (code: $errorCode)');
        return false;
      }

      // 保存基础信息
      _userId = loginResponseData['userId']?.toString();
      _passToken = loginResponseData['passToken'] as String?;
      _ssecurity = loginResponseData['ssecurity'] as String?;

      // 4. 获取serviceToken
      final location = loginResponseData['location'] as String?;
      final nonce = loginResponseData['nonce'];

      if (location == null || location.isEmpty || _ssecurity == null) {
        // 🎯 检查是否有 notificationUrl（需要二次身份验证）
        final notificationUrl = loginResponseData['notificationUrl'] as String?;
        final securityStatus = loginResponseData['securityStatus'];

        if (notificationUrl != null && notificationUrl.isNotEmpty) {
          // 构建完整的验证 URL
          final fullVerificationUrl = notificationUrl.startsWith('http')
              ? notificationUrl
              : 'https://account.xiaomi.com$notificationUrl';

          print('⚠️ [MiIoT] 需要二次身份验证 (securityStatus: $securityStatus)');
          print('⚠️ [MiIoT] 验证URL: $fullVerificationUrl');

          // 🎯 将验证URL保存到响应中，供 UI 层使用
          // 使用特殊的 code 70016 来标识需要验证
          _lastLoginResponse = {
            ...loginResponseData,
            'code': 70016,
            'captchaUrl': fullVerificationUrl,
            'desc': '需要二次身份验证',
          };

          return false;
        }

        print('❌ [MiIoT] location或ssecurity为空');
        return false;
      }

      // 计算clientSign
      final nsec = 'nonce=$nonce&$_ssecurity';
      final clientSignBytes = sha1.convert(utf8.encode(nsec)).bytes;
      final clientSign = base64Encode(clientSignBytes);

      // 获取serviceToken
      final tokenUrl = '$location&clientSign=${Uri.encodeComponent(clientSign)}';
      final tokenResponse = await _dio.get(
        tokenUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status! < 400 || status == 302,
          headers: headers,
        ),
      );

      // 从Cookie中提取serviceToken
      final cookies = tokenResponse.headers['set-cookie'];
      if (cookies != null) {
        for (var cookie in cookies) {
          if (cookie.contains('serviceToken=')) {
            _serviceToken = _extractCookieValue(cookie, 'serviceToken');
          }
        }
      }

      if (_serviceToken == null) {
        print('❌ [MiIoT] 无法获取serviceToken');
        return false;
      }

      print('✅ [MiIoT] 登录成功! userId: $_userId');
      return true;
    } catch (e, stackTrace) {
      print('❌ [MiIoT] 登录异常: $e');
      print('堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      return false;
    }
  }

  /// 🎯 使用 WebView 提取的 Cookie 登录
  /// 当用户在 WebView 中完成验证后，使用提取的 Cookie 直接获取 serviceToken
  Future<bool> loginWithCookies(String account, String password, {Map<String, String>? cookies}) async {
    try {
      print('🔐 [MiIoT] 使用 Cookie 登录小米账号: $account');

      // 🎯 确保 deviceId 已加载（使用 Completer 防止竞态条件）
      await ensureDeviceIdLoaded();
      print('🔧 [MiIoT] Cookie 登录使用 deviceId: $_deviceId');

      if (cookies == null || cookies.isEmpty) {
        print('⚠️ [MiIoT] Cookie 为空，尝试普通登录');
        return login(account, password);
      }

      final safeCookies = _maskCookieMap(cookies);
      print('🍪 [MiIoT] 收到的 Cookie: $safeCookies');

      // 🎯 检查是否有 serviceToken（最直接的情况）
      if (cookies.containsKey('serviceToken') && cookies['serviceToken']!.isNotEmpty) {
        _serviceToken = cookies['serviceToken'];
        _userId = cookies['userId'];
        _ssecurity = cookies['ssecurity'];
        print('✅ [MiIoT] 从 Cookie 中获取到 serviceToken');
        print('✅ [MiIoT] Cookie 登录成功! userId: $_userId');
        return true;
      }

      // 🎯 如果没有 serviceToken，尝试使用 passToken 获取
      if (cookies.containsKey('passToken') && cookies.containsKey('userId')) {
        _passToken = cookies['passToken'];
        _userId = cookies['userId'];
        print('🔧 [MiIoT] 从 Cookie 中获取到 passToken，尝试获取 serviceToken');

        // 使用 passToken 获取 serviceToken
        final success = await _getServiceTokenWithPassToken();
        if (success) {
          print('✅ [MiIoT] Cookie 登录成功! userId: $_userId');
          return true;
        }
      }

      // 🎯 如果标记了 STS 验证完成，但没有获取到 token，说明需要特殊处理
      // 不要再调用 login() 避免无限循环
      if (cookies.containsKey('_stsVerified')) {
        print('⚠️ [MiIoT] STS 验证已完成但未获取到 token');
        print('⚠️ [MiIoT] 可用的 Cookie 字段: ${cookies.keys}');

        // 🎯 修复：无论是否有 userId，都尝试使用验证后的 session 重新登录
        // 因为 deviceId 已经被小米服务器记录为已验证状态
        if (cookies.containsKey('userId')) {
          _userId = cookies['userId'];
        }

        print('🔧 [MiIoT] 尝试使用验证后的 session 获取 serviceToken...');

        // 尝试再次登录，但这次小米服务器应该已经认可了验证
        // 使用相同的 deviceId 确保 session 一致
        final success = await _loginAfterStsVerification(account, password);
        if (success) {
          print('✅ [MiIoT] 验证后登录成功!');
          return true;
        }

        // 如果还是失败，返回错误但不要无限循环
        print('❌ [MiIoT] 验证后登录仍然失败');
        // 🎯 注意：_lastLoginResponse 已经在 _loginAfterStsVerification 中被设置为非 70016 的错误
        return false;
      }

      // 🎯 如果 Cookie 中没有必要的信息且没有 STS 验证标记，尝试普通登录
      print('⚠️ [MiIoT] Cookie 中没有必要的认证信息，尝试普通登录');
      return login(account, password);
    } catch (e, stackTrace) {
      print('❌ [MiIoT] Cookie 登录异常: $e');
      print('堆栈: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      return false;
    }
  }

  /// 🎯 STS 验证完成后再次尝试登录
  /// 此时小米服务器应该已经记录了验证状态
  Future<bool> _loginAfterStsVerification(String account, String password) async {
    try {
      print('🔧 [MiIoT] STS 验证后尝试登录...');

      // 🎯 关键修复：清除旧的登录响应，避免无限循环！
      // 因为旧响应中可能包含 code: 70016，导致 UI 层再次跳转到验证页面
      _lastLoginResponse = null;

      // 🎯 确保使用相同的 deviceId（使用 Completer 防止竞态条件）
      await ensureDeviceIdLoaded();
      print('🔧 [MiIoT] STS 验证后使用 deviceId: $_deviceId');

      final headers = {
        'User-Agent': 'APP/com.xiaomi.mihome APPV/6.0.103 iosPassportSDK/3.9.0 iOS/14.4 miHSTS',
      };

      // 1. 获取 sign
      final signResponse = await _dio.get(
        'https://account.xiaomi.com/pass/serviceLogin',
        queryParameters: {
          'sid': 'micoapi',
          '_json': 'true',
        },
        options: Options(
          headers: {
            ...headers,
            'Cookie': 'sdkVersion=3.9; deviceId=$_deviceId',
          },
          responseType: ResponseType.plain,
        ),
      );

      final signData = _parseJsonResponse(signResponse.data);
      if (signData == null) {
        print('❌ [MiIoT] 获取 sign 失败');
        return false;
      }

      final sign = signData['_sign'] as String?;
      final qs = signData['qs'] as String?;
      final callback = signData['callback'] as String?;

      if (sign == null) {
        print('❌ [MiIoT] sign 为空');
        return false;
      }

      // 2. 计算密码 MD5
      final passwordHash = md5.convert(utf8.encode(password)).toString().toUpperCase();

      // 3. 登录请求
      final loginResponse = await _dio.post(
        'https://account.xiaomi.com/pass/serviceLoginAuth2',
        data: {
          '_json': 'true',
          'qs': qs ?? '',
          'sid': 'micoapi',
          '_sign': sign,
          'callback': callback ?? '',
          'user': account,
          'hash': passwordHash,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            ...headers,
            'Cookie': 'sdkVersion=3.9; deviceId=$_deviceId',
          },
          responseType: ResponseType.plain,
        ),
      );

      final loginResponseData = _parseJsonResponse(loginResponse.data);
      if (loginResponseData == null) {
        print('❌ [MiIoT] 登录响应解析失败');
        return false;
      }

      print('📝 [MiIoT] 验证后登录响应: code=${loginResponseData['code']}, desc=${loginResponseData['desc']}');
      print('📝 [MiIoT] 响应字段: ${loginResponseData.keys}');

      // 检查是否成功获取到关键信息
      if (loginResponseData['code'] == 0) {
        final location = loginResponseData['location'] as String?;
        _ssecurity = loginResponseData['ssecurity'] as String?;
        final nonce = loginResponseData['nonce'];

        if (location != null && location.isNotEmpty && _ssecurity != null) {
          // 计算 clientSign 并获取 serviceToken
          final nsec = 'nonce=$nonce&$_ssecurity';
          final clientSignBytes = sha1.convert(utf8.encode(nsec)).bytes;
          final clientSign = base64Encode(clientSignBytes);

          final tokenUrl = '$location&clientSign=${Uri.encodeComponent(clientSign)}';
          final tokenResponse = await _dio.get(
            tokenUrl,
            options: Options(
              followRedirects: false,
              validateStatus: (status) => status! < 400 || status == 302,
              headers: headers,
            ),
          );

          // 从 Cookie 中提取 serviceToken
          final cookies = tokenResponse.headers['set-cookie'];
          if (cookies != null) {
            for (var cookie in cookies) {
              if (cookie.contains('serviceToken=')) {
                _serviceToken = _extractCookieValue(cookie, 'serviceToken');
              }
            }
          }

          if (_serviceToken != null) {
            _userId = loginResponseData['userId']?.toString();
            print('✅ [MiIoT] 验证后登录成功! userId: $_userId');
            return true;
          }
        }
      }

      print('❌ [MiIoT] 验证后登录未能获取 serviceToken');
      // 🎯 设置明确的错误响应，告知 UI 层验证后登录失败
      _lastLoginResponse = {
        'code': -1,
        'desc': '验证完成但登录失败，请重试',
      };
      return false;
    } catch (e) {
      print('❌ [MiIoT] 验证后登录异常: $e');
      // 🎯 设置明确的错误响应
      _lastLoginResponse = {
        'code': -1,
        'desc': '验证后登录异常: $e',
      };
      return false;
    }
  }

  /// 🎯 使用 passToken 获取 serviceToken
  Future<bool> _getServiceTokenWithPassToken() async {
    try {
      if (_passToken == null || _userId == null) {
        print('❌ [MiIoT] passToken 或 userId 为空');
        return false;
      }

      print('🔧 [MiIoT] 使用 passToken 获取 serviceToken...');

      // 构建请求 URL
      final url = 'https://account.xiaomi.com/pass/serviceLogin?sid=micoapi&_json=true';

      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': 'APP/com.xiaomi.mihome APPV/6.0.103 iosPassportSDK/3.9.0 iOS/14.4 miHSTS',
            'Cookie': 'passToken=$_passToken; userId=$_userId',
          },
          responseType: ResponseType.plain,
        ),
      );

      final data = _parseJsonResponse(response.data);
      if (data == null) {
        print('❌ [MiIoT] 响应解析失败');
        return false;
      }

      print('📝 [MiIoT] passToken 登录响应: code=${data['code']}');

      // 检查是否成功
      if (data['code'] == 0) {
        final location = data['location'] as String?;
        _ssecurity = data['ssecurity'] as String?;
        final nonce = data['nonce'];

        if (location != null && _ssecurity != null) {
          // 计算 clientSign
          final nsec = 'nonce=$nonce&$_ssecurity';
          final clientSignBytes = sha1.convert(utf8.encode(nsec)).bytes;
          final clientSign = base64Encode(clientSignBytes);

          // 获取 serviceToken
          final tokenUrl = '$location&clientSign=${Uri.encodeComponent(clientSign)}';
          final tokenResponse = await _dio.get(
            tokenUrl,
            options: Options(
              followRedirects: false,
              validateStatus: (status) => status! < 400 || status == 302,
            ),
          );

          // 从 Cookie 中提取 serviceToken
          final setCookies = tokenResponse.headers['set-cookie'];
          if (setCookies != null) {
            for (var cookie in setCookies) {
              if (cookie.contains('serviceToken=')) {
                _serviceToken = _extractCookieValue(cookie, 'serviceToken');
              }
            }
          }

          if (_serviceToken != null) {
            print('✅ [MiIoT] 成功获取 serviceToken');
            return true;
          }
        }
      }

      print('❌ [MiIoT] 无法使用 passToken 获取 serviceToken');
      return false;
    } catch (e) {
      print('❌ [MiIoT] passToken 登录异常: $e');
      return false;
    }
  }

  /// 获取设备列表
  Future<List<MiDevice>> getDevices() async {
    if (!isLoggedIn) {
      print('❌ [MiIoT] 未登录，无法获取设备列表');
      return [];
    }

    try {
      print('📱 [MiIoT] 获取设备列表...');

      final response = await _dio.get(
        'https://api.mina.mi.com/admin/v2/device_list',
        options: Options(
          headers: {
            'Cookie': 'serviceToken=$_serviceToken; userId=$_userId',
          },
        ),
      );

      if (response.statusCode != 200) {
        print('❌ [MiIoT] 获取设备列表失败: ${response.statusCode}');
        return [];
      }

      final data = response.data as Map<String, dynamic>;
      final deviceList = data['data'] as List<dynamic>? ?? [];

      final devices = <MiDevice>[];
      for (var deviceData in deviceList) {
        final ip = deviceData['localip'] as String? ??
            deviceData['localIp'] as String? ??
            deviceData['ip'] as String?;
        final device = MiDevice(
          deviceId: deviceData['deviceID'] as String? ?? '',
          did: deviceData['miotDID'] as String? ?? '',
          name: deviceData['alias'] as String? ??
              deviceData['name'] as String? ??
              '未知设备',
          hardware: deviceData['hardware'] as String? ?? '',
          ip: ip,
        );

        if (device.deviceId.isNotEmpty && device.did.isNotEmpty) {
          devices.add(device);
          final ipSuffix = device.ip != null && device.ip!.isNotEmpty
              ? ' - ${device.ip}'
              : '';
          print('  📱 ${device.name} (${device.hardware})$ipSuffix');
        }
      }

      // 🎯 缓存设备列表
      _devices = devices;
      print('✅ [MiIoT] 找到 ${devices.length} 个设备');
      return devices;
    } catch (e) {
      print('❌ [MiIoT] 获取设备列表异常: $e');
      return [];
    }
  }

  /// 播放音乐URL
  /// [deviceId] 设备ID
  /// [musicUrl] 音乐播放地址（必须是公网可访问的URL）
  /// [compatMode] 是否使用兼容模式（某些老音箱需要）
  /// [musicName] 音乐名称（用于生成音频ID）
  Future<bool> playMusic({
    required String deviceId,
    required String musicUrl,
    bool compatMode = false,
    String? musicName,
    int? durationMs, // 🎯 歌曲时长（毫秒），传给设备可能改善 play_song_detail 返回
    int? startOffsetMs, // 🎯 起始播放位置（毫秒），用于从暂停位置恢复（player_play_music 专用）
  }) async {
    if (!isLoggedIn) {
      print('❌ [MiIoT] 未登录，无法播放音乐');
      return false;
    }

    // 🎯 关键修复：处理URL重定向！
    // 小爱音箱不支持HTTP重定向，必须先解析获取最终的真实URL
    String playUrl = musicUrl;
    bool useProxy = false;

    // 🔧 检查URL是否包含redirect参数（QQ音乐特征）
    if (musicUrl.contains('redirect=1') || musicUrl.contains('wx.music.tc.qq.com')) {
      print('🔄 [MiIoT] 检测到重定向URL，先解析真实地址...');
      try {
        // 🔧 改用 GET 请求并跟随重定向，获取最终的真实 URL
        final response = await _dio.get(
          musicUrl,
          options: Options(
            followRedirects: true, // 自动跟随重定向
            maxRedirects: 5, // 最多跟随5次重定向
            validateStatus: (status) => status! < 400,
            headers: {
              'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
              'Range': 'bytes=0-1', // 只请求1字节，节省流量
            },
          ),
        );

        // 🔧 获取最终的重定向地址（从响应的 realUri 获取）
        final realUri = response.realUri;
        if (realUri.toString() != musicUrl) {
          playUrl = realUri.toString();
          print('✅ [MiIoT] 解析到真实URL: ${playUrl.substring(0, playUrl.length > 80 ? 80 : playUrl.length)}...');
        } else {
          // 尝试从响应头获取
          final location = response.headers.value('location');
          if (location != null && location.isNotEmpty) {
            playUrl = location;
            print('✅ [MiIoT] 从响应头获取真实URL: ${playUrl.substring(0, playUrl.length > 80 ? 80 : playUrl.length)}...');
          } else {
            print('⚠️ [MiIoT] 未找到重定向地址，使用原始URL');
          }
        }
      } catch (e) {
        print('⚠️ [MiIoT] 解析重定向失败，使用原始URL: $e');
      }
    }

    // 🎯 使用代理服务器转发音频流（可选）
    // 小爱音箱直接访问某些CDN可能失败（User-Agent限制等）
    // 通过本地代理服务器转发，可以完美解决这些问题
    // 🔧 优先使用本地代理（同局域网），其次公共代理，最后直接URL

    // 🎯 智能代理选择：根据网络环境自动切换
    // WiFi 环境：优先使用本地代理（速度快、稳定）
    // 移动网络：直接使用公共代理（跳过本地代理检测，节省3秒超时）
    final networkDetector = NetworkDetector();
    final isWiFi = await networkDetector.isWiFiConnected();
    final device = _devices.cast<MiDevice?>().firstWhere(
          (d) => d?.deviceId == deviceId || d?.did == deviceId,
          orElse: () => null,
        );
    final deviceIp = device?.ip;
    final localIp = _proxyServer?.localIp;
    final sameSubnet = _isSameSubnet(deviceIp, localIp);

    // 网易云直连在当前设备上更稳定；QQ 直连仅用于实验
    final forceDirectForKnownCdn = MusicCdnUrlPolicy.shouldForceDirectForMiIoT(
      playUrl,
      enableQqDirect: _enableQqDirectPlayExperiment,
    );
    // QQ/酷我默认必须走代理（不回退直连）
    final requireProxyForKnownCdn =
        !forceDirectForKnownCdn && MusicCdnUrlPolicy.shouldRequireProxyForMiIoT(playUrl);
    if (forceDirectForKnownCdn) {
      final directType = MusicCdnUrlPolicy.isNeteaseCdn(playUrl) ? '网易云CDN' : 'QQ音乐CDN';
      print('🎯 [MiIoT] 检测到$directType，跳过代理并直连播放');
      if (directType == 'QQ音乐CDN') {
        print('🧪 [MiIoT] QQ直连实验已启用：本次将直接下发给小爱音箱');
      }
      print('   直连URL: ${playUrl.substring(0, playUrl.length > 80 ? 80 : playUrl.length)}...');
    } else if (MusicCdnUrlPolicy.isKuwoCdn(playUrl)) {
      print('🧪 [MiIoT] 酷我代理策略已启用：本次必须走代理');
    } else if (MusicCdnUrlPolicy.isQqCdn(playUrl)) {
      print('🧪 [MiIoT] QQ代理策略已启用：本次必须走代理');
    }

    // 方案1：尝试使用本地代理（仅在 WiFi 环境下）
    if (!forceDirectForKnownCdn && isWiFi && _proxyServer != null && _proxyServer!.isRunning) {
      if (deviceIp != null && localIp != null && !sameSubnet) {
        print('⚠️ [MiIoT] 设备IP与手机IP不同网段，跳过本地代理');
        print('   设备IP: $deviceIp');
        print('   手机IP: $localIp');
      } else if (deviceIp == null || localIp == null) {
        print('⚠️ [MiIoT] 无法获取设备或手机IP，仍使用本地代理');
      } else {
        print('✅ [MiIoT] 设备IP与手机IP同网段，允许本地代理');
        print('   设备IP: $deviceIp');
        print('   手机IP: $localIp');
      }

      final originalUrl = playUrl;
      try {
        // 🎯 直连模式优先通过本地代理推送 URL（base64 包裹），
        // 避免音箱直连音乐 CDN 被限制造成 403。
        // 注意：这里不再请求外部站点做探测，避免误判与额外外网依赖。
        if (deviceIp == null || localIp == null || sameSubnet) {
          playUrl = _proxyServer!.getProxyUrl(playUrl);
          useProxy = true;
          print('✅ [MiIoT] 使用本地代理转发（URL已base64封装）');
          print('   原始URL: ${originalUrl.substring(0, originalUrl.length > 80 ? 80 : originalUrl.length)}...');
          print('   代理URL: ${playUrl.substring(0, playUrl.length > 80 ? 80 : playUrl.length)}...');
        } else {
          print('⚠️ [MiIoT] 已确认不同网段，跳过本地代理');
        }
      } catch (e) {
        print('⚠️ [MiIoT] 本地代理封装失败，跳过使用: $e');
      }
    } else if (!isWiFi && _proxyServer != null && _proxyServer!.isRunning) {
      print('📱 [MiIoT] 移动网络环境，跳过本地代理（设备通常不可回连手机）');
    }

    // 方案2：本地代理不可用时，尝试公共代理
    if (!forceDirectForKnownCdn && !useProxy && _publicProxyUrl != null && _publicProxyUrl!.isNotEmpty) {
      final originalUrl = playUrl;
      try {
        // 使用 Cloudflare Workers 代理格式
        playUrl = '$_publicProxyUrl/proxy?url=${Uri.encodeComponent(playUrl)}';
        useProxy = true;
        print('🔄 [MiIoT] 本地代理不可用，使用公共代理转发');
        print('   原始URL: ${originalUrl.substring(0, originalUrl.length > 80 ? 80 : originalUrl.length)}...');
        print('   代理URL: ${playUrl.substring(0, playUrl.length > 80 ? 80 : playUrl.length)}...');
      } catch (e) {
        print('⚠️ [MiIoT] 使用公共代理失败: $e');
      }
    }

    // 对 QQ/酷我：代理不可用则直接失败，不回退直连
    if (requireProxyForKnownCdn && !useProxy) {
      print('❌ [MiIoT] QQ/酷我要求走代理，但当前代理不可用，取消播放');
      return false;
    }

    // 方案3：代理都不可用，直接使用真实URL（仅用于非QQ/酷我）
    if (!useProxy) {
      print('⚠️ [MiIoT] 代理不可用，直接使用真实URL');
      print('🔗 [MiIoT] 播放URL: ${playUrl.substring(0, playUrl.length > 80 ? 80 : playUrl.length)}...');
    }

    // 🔧 调试：记录URL协议
    final isHttps = playUrl.startsWith('https://');
    final isHttp = playUrl.startsWith('http://');
    print('🎵 [MiIoT] 播放音乐: $playUrl');
    print('📱 [MiIoT] 目标设备: $deviceId');
    print('🔧 [MiIoT] URL协议: ${isHttps ? "HTTPS" : (isHttp ? "HTTP" : "未知")}');

    // 🎯 获取设备硬件信息（如果有的话）
    String? hardware;
    try {
      // 从缓存的设备列表中获取硬件信息
      if (_devices.isNotEmpty) {
        final device = _devices.firstWhere(
          (d) => d.deviceId == deviceId || d.did == deviceId,
          orElse: () => MiDevice(deviceId: '', did: '', name: '', hardware: ''),
        );
        hardware = device.hardware;
        if (hardware.isNotEmpty) {
          final hardwareDesc = MiHardwareDetector.getHardwareDescription(hardware);
          final playMethod = MiHardwareDetector.getRecommendedPlayMethod(hardware);
          print('📱 [MiIoT] 设备硬件: $hardware ($hardwareDesc)');
          print('🎵 [MiIoT] 推荐播放方式: $playMethod');
        }
      }
    } catch (e) {
      print('⚠️ [MiIoT] 获取设备硬件信息失败: $e');
    }

    // 🎯 方案1：使用 player_play_url（简单播放）
    final method1 = 'player_play_url';
    final message1 = jsonEncode({
      'url': playUrl,  // 🔧 使用原始URL
      'type': 2, // 2=普通类型
      'media': 'app_ios',
      if (durationMs != null) 'duration': durationMs, // 🎯 传入歌曲时长
    });

    // 🎯 方案2：使用 player_play_music（完整播放，支持更多设备）
    // 参考 miservice-fork: https://github.com/yihong0618/MiService
    String audioId = MiAudioIdGenerator.DEFAULT_AUDIO_ID;

    // 如果提供了音乐名称，尝试生成音频ID
    if (musicName != null && musicName.isNotEmpty) {
      try {
        // 首先尝试从URL中提取音频ID
        final extractedId = MiAudioIdGenerator.extractAudioIdFromUrl(playUrl);
        if (extractedId != null) {
          audioId = extractedId;
          print('🎵 [MiIoT] 从URL提取到音频ID: $audioId');
        } else {
          // 如果URL中无法提取，则基于音乐名称生成
          audioId = await MiAudioIdGenerator.generateAudioId(musicName: musicName, deviceId: deviceId);
          print('🎵 [MiIoT] 生成音频ID: $audioId');
        }
      } catch (e) {
        print('⚠️ [MiIoT] 生成音频ID失败，使用默认ID: $e');
      }
    }

    // 🔧 关键修复：audio_type 应该为空字符串！
    // 根据 miservice-fork 源码：
    // - type=2 时 audio_type = "" (默认/普通播放)
    // - type=1 时 audio_type = "MUSIC" (音乐播放，会有灯光效果)
    // 之前错误地设置为 "MUSIC"，导致音箱有反应但不响
    final music = {
      'payload': {
        'audio_type': '',  // 🔧 修复：使用空字符串而不是 "MUSIC"
        'audio_items': [
          {
            'item_id': {
              'audio_id': audioId,
              'cp': {
                'album_id': '-1',
                'episode_index': 0,
                'id': '355454500',
                'name': 'xiaowei',
              },
            },
            'stream': {'url': playUrl},
          }
        ],
        'list_params': {
          'listId': '-1',
          'loadmore_offset': 0,
          'origin': 'xiaowei',
          'type': 'MUSIC',
        },
      },
      'play_behavior': 'REPLACE_ALL',
    };
    final method2 = 'player_play_music';
    final message2 = jsonEncode({
      'startaudioid': audioId,
      'music': jsonEncode(music), // 注意：music 需要二次 JSON 编码
      if (durationMs != null) 'duration': durationMs, // 🎯 传入歌曲时长
      if (startOffsetMs != null && startOffsetMs > 0)
        'startOffset': startOffsetMs, // 🎯 从指定位置开始播放（毫秒），用于暂停后恢复
    });

    // 🎯 播放前先完整停止当前播放
    // 对齐 xiaomusic force_stop_xiaoai: pause → stop
    print('⏸️ [MiIoT] 播放前先暂停当前播放...');
    await pause(deviceId);
    print('⏹️ [MiIoT] 停止当前播放...');
    await stop(deviceId);

    // 🎯 智能选择播放方案
    List<Map<String, dynamic>> attempts = [];

    // 检查设备是否需要使用 player_play_music API
    if (hardware != null && MiHardwareDetector.needsPlayMusicApi(hardware)) {
      print('🎯 [MiIoT] 设备需要使用 player_play_music API');
      attempts = [
        {'name': 'player_play_music (完整)', 'method': method2, 'message': message2},
        {'name': 'player_play_url (备用)', 'method': method1, 'message': message1},
      ];
    } else {
      print('🎯 [MiIoT] 设备可以使用 player_play_url API');
      attempts = [
        {'name': 'player_play_url (简单)', 'method': method1, 'message': message1},
        {'name': 'player_play_music (备用)', 'method': method2, 'message': message2},
      ];
    }

    for (var i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      print('🔄 [MiIoT] 尝试方案${i + 1}/${attempts.length}: ${attempt['name']}');

      // 🎯 关键修复：使用 POST 请求体，而不是 URL 查询参数！
      final requestBody = {
        'deviceId': deviceId,
        'method': attempt['method'],
        'path': 'mediaplayer',
        'message': attempt['message'], // message 已经是 JSON 字符串
        'requestId': 'app_ios_${DateTime.now().millisecondsSinceEpoch}',
      };

      print('📡 [MiIoT] 请求URL: https://api2.mina.mi.com/remote/ubus');
      print('📦 [MiIoT] 请求体: $requestBody');

      try {
        final response = await _dio.post(
          'https://api2.mina.mi.com/remote/ubus',
          data: requestBody,
          options: Options(
            headers: {
              'Cookie': 'serviceToken=$_serviceToken; userId=$_userId',
              'Content-Type': 'application/x-www-form-urlencoded', // 表单格式
              'User-Agent': 'MiHome/6.0.103 (com.xiaomi.mihome; build:6.0.103.1; iOS 14.4.0) Alamofire/6.0.103 MICO/iOSApp/appStore/6.0.103',
            },
            contentType: Headers.formUrlEncodedContentType, // 表单编码
          ),
        );

        print('📡 [MiIoT] 响应状态: ${response.statusCode}');
        print('📡 [MiIoT] 响应数据: ${response.data}');

        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map && data['code'] == 0) {
            print('✅ [MiIoT] 播放成功! 使用方案: ${attempt['name']}');
            // 对齐 xiaomusic: player_play_music 配合 REPLACE_ALL 会自动开始播放
            // 不需要额外的 resume() 或状态检查
            return true;
          } else {
            print('⚠️ [MiIoT] 方案${i + 1}返回非成功状态: ${data}');
          }
        } else {
          print('⚠️ [MiIoT] 方案${i + 1}失败: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ [MiIoT] 方案${i + 1}异常: $e');

        if (e is DioException && e.response != null) {
          print('📡 [MiIoT] 错误响应状态: ${e.response?.statusCode}');
          print('📡 [MiIoT] 错误响应数据: ${e.response?.data}');
        }

        if (i == attempts.length - 1) {
          print('❌ [MiIoT] 所有播放方案都失败了');
          return false;
        }

        print('⏩ [MiIoT] 继续尝试下一个方案...');
      }
    }

    return false;
  }

  bool _isSameSubnet(String? ipA, String? ipB) {
    if (ipA == null || ipB == null) {
      return false;
    }
    final partsA = ipA.split('.');
    final partsB = ipB.split('.');
    if (partsA.length != 4 || partsB.length != 4) {
      return false;
    }
    return partsA[0] == partsB[0] &&
        partsA[1] == partsB[1] &&
        partsA[2] == partsB[2];
  }

  /// 暂停播放
  Future<bool> pause(String deviceId) async {
    return await _sendPlayerOperation(deviceId, 'pause');
  }

  /// 继续播放
  Future<bool> resume(String deviceId) async {
    return await _sendPlayerOperation(deviceId, 'play');
  }

  /// 设备端下一首
  Future<bool> next(String deviceId) async {
    print('⏭️ [MiIoT] 设备端下一首: $deviceId');
    return await _sendPlayerOperation(deviceId, 'next');
  }

  /// 设备端上一首
  Future<bool> previous(String deviceId) async {
    print('⏮️ [MiIoT] 设备端上一首: $deviceId');
    return await _sendPlayerOperation(deviceId, 'prev');
  }

  /// 切换播放/暂停
  Future<bool> toggle(String deviceId) async {
    print('⏯️ [MiIoT] 切换播放/暂停: $deviceId');
    return await _sendPlayerOperation(deviceId, 'toggle');
  }

  /// 设置循环模式
  /// 使用正确的 player_set_loop ubus API
  /// [loopType] 0=单曲循环, 1=列表循环, 3=随机播放
  Future<bool> setLoopType(String deviceId, int loopType) async {
    print('🔁 [MiIoT] 设置循环模式: type=$loopType (设备: $deviceId)');
    return await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_set_loop',
      message: {'type': loopType, 'media': 'common'},
    );
  }

  /// 设置播放模式
  /// [deviceId] 设备ID
  /// [playMode] 播放模式 (ONE/ALL/RND/SIN/SEQ)
  /// [dotts] 是否播放TTS提示音
  Future<bool> setPlayMode({
    required String deviceId,
    required String playMode,
    bool dotts = true,
  }) async {
    if (!MiPlayMode.isValidMode(playMode)) {
      print('❌ [MiIoT] 无效的播放模式: $playMode');
      return false;
    }

    try {
      print('🎵 [MiIoT] 设置播放模式: ${MiPlayMode.getModeDescription(playMode)}');

      // 🎯 使用正确的 player_set_loop API（而非 player_play_operation）
      final loopType = _playModeToLoopType(playMode);
      final success = await setLoopType(deviceId, loopType);
      if (success) {
        print('✅ [MiIoT] 播放模式设置成功: ${MiPlayMode.getModeDescription(playMode)}');
      } else {
        print('❌ [MiIoT] 播放模式设置失败');
      }

      return success;
    } catch (e) {
      print('❌ [MiIoT] 设置播放模式异常: $e');
      return false;
    }
  }

  /// 将 MiPlayMode 常量映射到 player_set_loop 的 type 值
  int _playModeToLoopType(String playMode) {
    switch (playMode) {
      case MiPlayMode.PLAY_TYPE_ONE:  // 单曲循环
      case MiPlayMode.PLAY_TYPE_SIN:  // 单曲播放
        return 0;
      case MiPlayMode.PLAY_TYPE_ALL:  // 全部循环
      case MiPlayMode.PLAY_TYPE_SEQ:  // 顺序播放
        return 1;
      case MiPlayMode.PLAY_TYPE_RND:  // 随机播放
        return 3;
      default:
        return 1;
    }
  }

  /// 停止播放
  Future<bool> stop(String deviceId) async {
    return await _sendPlayerOperation(deviceId, 'stop');
  }

  /// 获取当前播放模式
  /// [deviceId] 设备ID
  /// 返回播放模式字符串，如果获取失败返回null
  /// 🎯 从 player_get_play_status 返回的 loop_type 字段解析真实循环模式
  Future<String?> getPlayMode(String deviceId) async {
    try {
      print('🎵 [MiIoT] 获取当前播放模式: $deviceId');

      final status = await getPlayStatus(deviceId);
      if (status == null) {
        print('⚠️ [MiIoT] 无法获取播放状态');
        return null;
      }

      // 🎯 从 loop_type 字段解析真实循环模式
      final loopType = status['loop_type'] as int?;
      final mode = _loopTypeToPlayMode(loopType);
      print('✅ [MiIoT] 获取播放模式成功: loop_type=$loopType → $mode');
      return mode;
    } catch (e) {
      print('❌ [MiIoT] 获取播放模式异常: $e');
      return null;
    }
  }

  /// 将 loop_type 转换回 MiPlayMode 常量
  String _loopTypeToPlayMode(int? loopType) {
    switch (loopType) {
      case 0: return MiPlayMode.PLAY_TYPE_ONE;  // 单曲循环
      case 1: return MiPlayMode.PLAY_TYPE_ALL;  // 列表循环
      case 3: return MiPlayMode.PLAY_TYPE_RND;  // 随机播放
      default: return MiPlayMode.PLAY_TYPE_ALL;  // 默认列表循环
    }
  }

  /// 设置音量
  Future<bool> setVolume(String deviceId, int volume) async {
    return await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_set_volume',
      message: {'volume': volume, 'media': 'app_ios'},
    );
  }

  /// 跳转播放进度
  /// [positionMs] 目标位置（毫秒）
  /// 注意：API 原始拼写为 player_set_positon（少了一个 i），这是固件的拼写错误
  Future<bool> seekTo(String deviceId, int positionMs) async {
    print('🎯 [MiIoT] 跳转进度: ${positionMs}ms (设备: $deviceId)');
    return await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_set_positon', // ⚠️ 固件原始拼写，少了一个 i
      message: {'position': positionMs, 'media': 'app_ios'},
    );
  }

  /// 设置播放速率
  /// [rate] 播放速率字符串，如 "0.5", "1.0", "1.5", "2.0"
  Future<bool> setPlayRate(String deviceId, String rate) async {
    print('⏩ [MiIoT] 设置播放速率: $rate (设备: $deviceId)');
    return await _sendUbusRequest(
      deviceId: deviceId,
      method: 'set_playrate',
      message: {'rate': rate},
    );
  }

  /// 设置睡眠定时器（定时暂停播放）
  /// [hour] 小时, [minute] 分钟, [second] 秒
  Future<bool> setSleepTimer(String deviceId, {int hour = 0, int minute = 30, int second = 0}) async {
    print('😴 [MiIoT] 设置睡眠定时器: ${hour}h ${minute}m ${second}s (设备: $deviceId)');
    return await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_set_shutdown_timer',
      message: {'action': 'pause_later', 'hour': hour, 'minute': minute, 'second': second, 'media': 'app_ios'},
    );
  }

  /// 取消睡眠定时器
  Future<bool> cancelSleepTimer(String deviceId) async {
    print('😴 [MiIoT] 取消睡眠定时器 (设备: $deviceId)');
    return await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_set_shutdown_timer',
      message: {'action': 'cancel_ending'},
    );
  }

  /// 获取睡眠定时器状态
  /// 返回 {remain_time: 毫秒, type: 0或1}，type=0 表示无定时器
  Future<Map<String, dynamic>?> getSleepTimer(String deviceId) async {
    print('😴 [MiIoT] 查询睡眠定时器 (设备: $deviceId)');
    final result = await _sendUbusRequest(
      deviceId: deviceId,
      method: 'get_shutdown_timer',
      message: {},
      returnResult: true,
    );
    return result is Map<String, dynamic> ? result : null;
  }

  /// 获取播放状态
  Future<Map<String, dynamic>?> getPlayStatus(String deviceId) async {
    final result = await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_get_play_status',
      message: {'media': 'app_ios'},
      returnResult: true,
    );

    // 🎯 解析 info 字符串（API返回的是JSON字符串，需要二次解析）
    if (result != null && result is Map) {
      final info = result['info'];
      if (info != null && info is String) {
        try {
          final parsed = jsonDecode(info) as Map<String, dynamic>;
          print('✅ [MiIoT] 播放状态解析成功: status=${parsed['status']}, position=${parsed['play_song_detail']?['position']}');
          return parsed;
        } catch (e) {
          print('❌ [MiIoT] 解析播放状态info失败: $e');
        }
      }
    }

    return result is Map<String, dynamic> ? result : null;
  }

  /// 🔬 实验性：调用 player_play_status（区别于 player_get_play_status）
  /// 固件中存在两个不同的方法，可能返回不同格式的状态数据
  Future<Map<String, dynamic>?> getPlayStatusAlt(String deviceId) async {
    print('🔬 [MiIoT] 实验性调用 player_play_status...');
    final result = await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_play_status',
      message: {},
      returnResult: true,
    );
    print('🔬 [MiIoT] player_play_status 返回: $result');

    // 尝试解析 info 字符串
    if (result != null && result is Map) {
      final info = result['info'];
      if (info != null && info is String) {
        try {
          final parsed = jsonDecode(info) as Map<String, dynamic>;
          print('🔬 [MiIoT] player_play_status 解析成功: $parsed');
          return parsed;
        } catch (e) {
          print('🔬 [MiIoT] player_play_status 解析失败: $e');
        }
      }
    }

    return result is Map<String, dynamic> ? result : null;
  }

  /// 🔬 实验性：调用 player_get_context 获取播放上下文
  /// 可能返回播放队列、当前曲目详情等信息
  Future<Map<String, dynamic>?> getPlayContext(String deviceId) async {
    print('🔬 [MiIoT] 实验性调用 player_get_context...');
    final result = await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_get_context',
      message: {},
      returnResult: true,
    );
    print('🔬 [MiIoT] player_get_context 返回: $result');

    // 尝试解析 info 字符串
    if (result != null && result is Map) {
      final info = result['info'];
      if (info != null && info is String) {
        try {
          final parsed = jsonDecode(info) as Map<String, dynamic>;
          print('🔬 [MiIoT] player_get_context 解析成功: $parsed');
          return parsed;
        } catch (e) {
          print('🔬 [MiIoT] player_get_context 解析失败: $e');
        }
      }
    }

    return result is Map<String, dynamic> ? result : null;
  }

  /// 发送播放控制指令（播放/暂停/停止）
  /// 使用 player_play_operation 方法，这是正确的 API
  Future<bool> _sendPlayerOperation(String deviceId, String action) async {
    return await _sendUbusRequest(
      deviceId: deviceId,
      method: 'player_play_operation',
      message: {'action': action, 'media': 'app_ios'},
    );
  }

  /// 通用 ubus 请求方法
  /// [returnResult] 为 true 时返回完整响应数据，为 false 时只返回成功/失败
  Future<dynamic> _sendUbusRequest({
    required String deviceId,
    required String method,
    required Map<String, dynamic> message,
    bool returnResult = false,
  }) async {
    if (!isLoggedIn) {
      print('❌ [MiIoT] 未登录');
      return returnResult ? null : false;
    }

    try {
      print('🎵 [MiIoT] 发送 ubus 请求: $method -> $deviceId');
      print('📦 [MiIoT] message: $message');

      // 🎯 按照 miservice-fork 的格式：message 必须是 JSON 字符串
      final requestBody = {
        'deviceId': deviceId,
        'method': method,
        'path': 'mediaplayer',
        'message': jsonEncode(message), // 关键：message 必须是 JSON 字符串！
        'requestId': 'app_ios_${DateTime.now().millisecondsSinceEpoch}',
      };

      final response = await _dio.post(
        'https://api2.mina.mi.com/remote/ubus',
        data: requestBody,
        options: Options(
          headers: {
            'Cookie': 'serviceToken=$_serviceToken; userId=$_userId',
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'MiHome/6.0.103 (com.xiaomi.mihome; build:6.0.103.1; iOS 14.4.0) Alamofire/6.0.103 MICO/iOSApp/appStore/6.0.103',
          },
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      print('📡 [MiIoT] 响应: ${response.statusCode} - ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['code'] == 0) {
          print('✅ [MiIoT] 请求成功: $method');
          if (returnResult) {
            return data['data']; // 返回具体数据
          }
          return true;
        }
      }

      print('⚠️ [MiIoT] 请求失败: $method');
      return returnResult ? null : false;
    } catch (e) {
      print('❌ [MiIoT] 请求异常: $e');
      return returnResult ? null : false;
    }
  }

  /// 解析JSON响应（处理可能的字符串包裹）
  Map<String, dynamic>? _parseJsonResponse(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        return data;
      }

      String jsonStr = data.toString();
      // 移除可能的&&&START&&&前缀
      if (jsonStr.startsWith('&&&START&&&')) {
        jsonStr = jsonStr.substring(11);
      }

      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      print('❌ [MiIoT] JSON解析失败: $e');
      return null;
    }
  }

  /// 从Cookie字符串中提取值
  String? _extractCookieValue(String cookie, String key) {
    final regex = RegExp('$key=([^;]+)');
    final match = regex.firstMatch(cookie);
    return match?.group(1);
  }

  /// 登出
  void logout() {
    _serviceToken = null;
    _userId = null;
    _ssecurity = null;
    _deviceId = null;
    print('👋 [MiIoT] 已登出');
  }
}

/// 小米设备模型
class MiDevice {
  final String deviceId;
  final String did;
  final String name;
  final String hardware;
  final String? ip;

  MiDevice({
    required this.deviceId,
    required this.did,
    required this.name,
    required this.hardware,
    this.ip,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'did': did,
        'name': name,
        'hardware': hardware,
        'ip': ip,
      };

  factory MiDevice.fromJson(Map<String, dynamic> json) => MiDevice(
        deviceId: json['deviceId'] as String,
        did: json['did'] as String,
        name: json['name'] as String,
        hardware: json['hardware'] as String,
        ip: json['ip'] as String?,
      );
}
