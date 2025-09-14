import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';

class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverCtrl.text =
        prefs.getString(AppConstants.prefsServerUrl) ?? 'http://localhost:8090';
    _userCtrl.text = prefs.getString(AppConstants.prefsUsername) ?? '';
    _passCtrl.text = prefs.getString(AppConstants.prefsPassword) ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefsServerUrl, _serverCtrl.text.trim());
    await prefs.setString(AppConstants.prefsUsername, _userCtrl.text.trim());
    await prefs.setString(AppConstants.prefsPassword, _passCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('服务器账号设置已保存'), backgroundColor: Colors.green),
    );
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器账号设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _serverCtrl,
            decoration: const InputDecoration(labelText: '服务器地址 (含协议)')
                .copyWith(helperText: '例如：http://192.168.31.2:8090'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // 打印到调试日志，便于找回
                    // 注意：包含敏感信息，仅用于本地调试
                    debugPrint('Server URL: ${_serverCtrl.text}');
                    debugPrint('Username : ${_userCtrl.text}');
                    debugPrint('Password : ${_passCtrl.text}');
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已输出到调试日志')),
                    );
                  },
                  icon: const Icon(Icons.bug_report),
                  label: const Text('输出到日志'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              // 直接尝试用当前值登录（验证有效性）
              await ref.read(authProvider.notifier).login(
                    serverUrl: _serverCtrl.text,
                    username: _userCtrl.text,
                    password: _passCtrl.text,
                    saveCredentials: true,
                  );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已尝试登录（如失败请检查服务器可达性）')),
              );
            },
            icon: const Icon(Icons.login),
            label: const Text('验证并登录'),
          ),
        ],
      ),
    );
  }
}


