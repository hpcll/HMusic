import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/direct_mode_provider.dart';

/// 直连模式登录页面
/// 用户输入小米账号密码，无需xiaomusic服务端
class DirectModeLoginPage extends ConsumerStatefulWidget {
  const DirectModeLoginPage({super.key});

  @override
  ConsumerState<DirectModeLoginPage> createState() =>
      _DirectModeLoginPageState();
}

class _DirectModeLoginPageState extends ConsumerState<DirectModeLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 调用Provider登录
    await ref.read(directModeProvider.notifier).login(
          account: _accountController.text.trim(),
          password: _passwordController.text,
          saveCredentials: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    // 监听登录状态
    final directModeState = ref.watch(directModeProvider);

    // 登录成功后跳转
    ref.listen<DirectModeState>(directModeProvider, (previous, next) {
      if (next is DirectModeAuthenticated) {
        // 登录成功，跳转到主页
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录成功！找到 ${next.devices.length} 个设备'),
          ),
        );
        // 使用GoRouter导航
        context.go('/');
      } else if (next is DirectModeError) {
        // 登录失败，显示错误
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message)),
        );
      }
    });

    final isLoading = directModeState is DirectModeLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('直连模式登录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isLoading ? null : () => context.go('/login'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Logo和标题
              Icon(
                Icons.phone_android,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                '直连模式',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '使用小米账号登录，直接控制小爱音箱',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // 小米账号输入框
              TextFormField(
                controller: _accountController,
                decoration: InputDecoration(
                  labelText: '小米账号',
                  hintText: '手机号/邮箱',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入小米账号';
                  }
                  return null;
                },
                enabled: !isLoading,
              ),

              const SizedBox(height: 16),

              // 密码输入框
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '小米账号密码',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码';
                  }
                  return null;
                },
                enabled: !isLoading,
              ),

              const SizedBox(height: 32),

              // 登录按钮
              ElevatedButton(
                onPressed: isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '登录',
                        style: TextStyle(fontSize: 16),
                      ),
              ),

              const SizedBox(height: 24),

              // 提示信息
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '使用说明',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• 直连模式无需服务器，开箱即用\n'
                      '• 使用您的小米账号直接登录\n'
                      '• 登录后可直接控制小爱音箱\n'
                      '• 您的账号信息仅用于登录小米IoT',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 切换到xiaomusic模式
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        // 切换回xiaomusic模式
                        ref
                            .read(playbackModeProvider.notifier)
                            .setMode(PlaybackMode.xiaomusic);
                        context.go('/login');
                      },
                child: const Text('切换到 xiaomusic 模式 →'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
