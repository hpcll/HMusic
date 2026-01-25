import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SshSettings {
  final String host;
  final int port;
  final String username;
  final String password;
  final String subDir; // 相对 /opt/xiaomusic/music 的子目录，可为空
  final bool useHttpUpload; // true 用 HTTP 接口，false 用 SCP

  const SshSettings({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.subDir = '',
    this.useHttpUpload = false,
  });

  SshSettings copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? subDir,
    bool? useHttpUpload,
  }) {
    return SshSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      subDir: subDir ?? this.subDir,
      useHttpUpload: useHttpUpload ?? this.useHttpUpload,
    );
  }
}

class SshSettingsNotifier extends StateNotifier<SshSettings> {
  static const _kHost = 'ssh_host';
  static const _kPort = 'ssh_port';
  static const _kUser = 'ssh_user';
  static const _kPass = 'ssh_pass';
  static const _kSubDir = 'ssh_music_subdir';
  static const _kUseHttp = 'ssh_use_http_upload';

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  SshSettingsNotifier()
    : super(
        const SshSettings(
          host: '',
          port: 22,
          username: '',
          password: '',
          subDir: '',
          useHttpUpload: false,
        ),
      ) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString(_kHost);
      final port = prefs.getInt(_kPort);
      final user = prefs.getString(_kUser);
      final pass = prefs.getString(_kPass);
      final sub = prefs.getString(_kSubDir);
      final useHttp = prefs.getBool(_kUseHttp);
      if (host != null || port != null || user != null || pass != null) {
        state = state.copyWith(
          host: host ?? state.host,
          port: port ?? state.port,
          username: user ?? state.username,
          password: pass ?? state.password,
          subDir: sub ?? state.subDir,
          useHttpUpload: useHttp ?? state.useHttpUpload,
        );
      }
    } catch (e) {
      print('❌ [SshSettings] 加载设置失败: $e');
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> save(SshSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, settings.host);
    await prefs.setInt(_kPort, settings.port);
    await prefs.setString(_kUser, settings.username);
    await prefs.setString(_kPass, settings.password);
    await prefs.setString(_kSubDir, settings.subDir);
    await prefs.setBool(_kUseHttp, settings.useHttpUpload);
  }
}

final sshSettingsProvider =
    StateNotifierProvider<SshSettingsNotifier, SshSettings>((ref) {
      return SshSettingsNotifier();
    });
