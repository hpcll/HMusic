import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import 'direct_mode_provider.dart'; // 🎯 导入播放模式定义

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final DioClient client;
  final String serverUrl;
  final String username;

  const AuthAuthenticated({
    required this.client,
    required this.serverUrl,
    required this.username,
  });
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref; // 🎯 保存 ref 引用以便访问其他 Provider

  AuthNotifier(this.ref) : super(const AuthInitial()) {
    _loadSavedCredentials();
    _listenToModeChanges();
  }

  // 🔧 监听播放模式变化，切换到 xiaomusic 模式时自动登录
  void _listenToModeChanges() {
    ref.listen<PlaybackMode>(playbackModeProvider, (previous, next) {
      if (previous == PlaybackMode.miIoTDirect && next == PlaybackMode.xiaomusic) {
        debugPrint('🔧 [AuthProvider] 检测到模式切换: 直连 -> xiaomusic，尝试自动登录');
        // 如果当前未登录，尝试加载保存的凭证
        if (state is! AuthAuthenticated) {
          // 🔧 延迟一小段时间，等待 SharedPreferences 更新完成
          Future.delayed(const Duration(milliseconds: 100), () {
            _loadSavedCredentials();
          });
        }
      }
    });
  }

  Future<void> _loadSavedCredentials() async {
    try {
      // 🎯 关键修复：检查当前播放模式，只在 xiaomusic 模式下自动登录
      final prefs = await SharedPreferences.getInstance();

      // 🎯 读取播放模式（与 direct_mode_provider.dart 中的逻辑一致）
      final modeString = prefs.getString('playback_mode');
      final playbackMode = modeString == 'miIoTDirect'
          ? PlaybackMode.miIoTDirect
          : PlaybackMode.xiaomusic;

      debugPrint('🔧 [AuthProvider] 当前播放模式: $playbackMode');

      // 🎯 只有在 xiaomusic 模式下才尝试自动登录
      if (playbackMode != PlaybackMode.xiaomusic) {
        debugPrint('🔧 [AuthProvider] 非 xiaomusic 模式，跳过自动登录');
        return;
      }

      final serverUrl = prefs.getString(AppConstants.prefsServerUrl);
      final username = prefs.getString(AppConstants.prefsUsername);
      final password = prefs.getString(AppConstants.prefsPassword);

      if (serverUrl != null && username != null && password != null) {
        debugPrint('🔧 [AuthProvider] xiaomusic 模式，尝试自动登录: $username@$serverUrl');
        // 自动登录时不显示 Loading 状态，直接尝试登录
        await _silentLogin(
          serverUrl: serverUrl,
          username: username,
          password: password,
        );
      } else {
        debugPrint('🔧 [AuthProvider] xiaomusic 模式，但未保存登录凭证');
      }
    } catch (e) {
      debugPrint('❌ [AuthProvider] 自动登录失败: $e');
    }
  }

  /// 静默登录（不显示 Loading 状态）
  Future<void> _silentLogin({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      String cleanUrl = serverUrl.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'http://$cleanUrl';
      }

      final client = DioClient(
        baseUrl: cleanUrl,
        username: username,
        password: password,
      );

      // 简单连通性校验
      await client.get('/getversion');

      state = AuthAuthenticated(
        client: client,
        serverUrl: cleanUrl,
        username: username,
      );
      debugPrint('✅ [AuthProvider] 静默登录成功: $username@$cleanUrl');
    } catch (e) {
      debugPrint('❌ [AuthProvider] 静默登录失败: $e');
      // 失败时保持 AuthInitial 状态，显示登录页
      state = const AuthInitial();
    }
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    bool saveCredentials = true,
  }) async {
    state = const AuthLoading();

    try {
      String cleanUrl = serverUrl.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'http://$cleanUrl';
      }

      final client = DioClient(
        baseUrl: cleanUrl,
        username: username,
        password: password,
      );

      // 简单连通性校验
      await client.get('/getversion');

      if (saveCredentials) {
        await _saveCredentials(cleanUrl, username, password);
      }

      state = AuthAuthenticated(
        client: client,
        serverUrl: cleanUrl,
        username: username,
      );
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.prefsServerUrl);
      await prefs.remove(AppConstants.prefsUsername);
      await prefs.remove(AppConstants.prefsPassword);

      state = const AuthInitial();
    } catch (e) {
      state = AuthError('登出失败: $e');
    }
  }

  Future<void> _saveCredentials(
    String serverUrl,
    String username,
    String password,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefsServerUrl, serverUrl);
    await prefs.setString(AppConstants.prefsUsername, username);
    await prefs.setString(AppConstants.prefsPassword, password);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref); // 🎯 传入 ref 引用
});

// 提示：`apiServiceProvider` 已迁移至 `presentation/providers/dio_provider.dart`
