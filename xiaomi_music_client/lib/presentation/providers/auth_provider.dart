import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';

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
  AuthNotifier() : super(const AuthInitial()) {
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString(AppConstants.prefsServerUrl);
      final username = prefs.getString(AppConstants.prefsUsername);
      final password = prefs.getString(AppConstants.prefsPassword);

      if (serverUrl != null && username != null && password != null) {
        debugPrint('尝试自动登录: $username@$serverUrl');
        await login(
          serverUrl: serverUrl,
          username: username,
          password: password,
          saveCredentials: false, // 不重复保存
        );
      }
    } catch (e) {
      debugPrint('自动登录失败: $e');
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
  return AuthNotifier();
});

// 提示：`apiServiceProvider` 已迁移至 `presentation/providers/dio_provider.dart`
