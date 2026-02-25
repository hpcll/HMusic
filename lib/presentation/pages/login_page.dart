import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import '../providers/direct_mode_provider.dart';
import '../../core/constants/app_constants.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final GlobalKey<FormState> _formKey;
  final _serverUrlController = TextEditingController(
    text: AppConstants.defaultServerUrl,
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();
    void listener() { if (mounted) setState(() {}); }
    _serverUrlController.addListener(listener);
    _usernameController.addListener(listener);
    _passwordController.addListener(listener);
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    ref.read(authProvider.notifier).login(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    final isLight = Theme.of(context).brightness == Brightness.light;
    final isLoading = authState is AuthLoading;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
        child: Stack(
          children: [
            // 主内容
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                bottom: keyboardHeight > 0 ? keyboardHeight + 20 : 20.0,
              ),
              child: Column(
                children: [
                  SizedBox(height: screenHeight * 0.13),

                  // Logo和标题区域
                  Column(
                    children: [
                      SvgPicture.asset(
                        'assets/hmusic-logo.svg',
                        width: 120,
                        colorFilter: ColorFilter.mode(
                          isLight
                              ? const Color(0xFF21B0A5)
                              : const Color(0xFF21B0A5).withValues(alpha: 0.9),
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'xiaomusic 模式',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: isLight
                              ? const Color(0xFF2D3748)
                              : Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '连接 xiaomusic 服务端，播放 NAS 音乐',
                        style: TextStyle(
                          fontSize: 16,
                          color: isLight
                              ? const Color(0xFF4A5568)
                              : Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 60),

                  // 登录表单卡片
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color:
                          isLight
                              ? Colors.white
                              : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color:
                            isLight
                                ? Colors.black.withOpacity(0.06)
                                : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                      boxShadow:
                          isLight
                              ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                              : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 40,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 服务器地址输入框
                          _buildModernTextField(
                            controller: _serverUrlController,
                            labelText: '服务器地址',
                            hintText: AppConstants.defaultServerUrl,
                            prefixIcon: Icons.dns_rounded,
                            textInputAction: TextInputAction.next,
                            enableClear: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请输入服务器地址';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // 用户名输入框
                          _buildModernTextField(
                            controller: _usernameController,
                            labelText: '用户名（选填）',
                            hintText: '未设置可留空',
                            prefixIcon: Icons.person_rounded,
                            textInputAction: TextInputAction.next,
                            enableClear: true,
                          ),

                          const SizedBox(height: 20),

                          // 密码输入框
                          _buildModernTextField(
                            controller: _passwordController,
                            labelText: '密码（选填）',
                            hintText: '未设置可留空',
                            prefixIcon: Icons.lock_rounded,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _handleLogin(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                size: 22,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),

                          const SizedBox(height: 32),

                          // 错误提示 / 登录提示（互斥）
                          if (authState is AuthError)
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B6B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFF6B6B,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: const Color(0xFFFF6B6B),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      authState.message,
                                      style: const TextStyle(
                                        color: Color(0xFFFF6B6B),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '后台未设置账号密码？直接点击登录',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // 登录按钮
                          _buildModernButton(
                            onPressed:
                                authState is AuthLoading ? null : _handleLogin,
                            isLoading: authState is AuthLoading,
                          ),

                        ],
                      ),
                    ),
                  ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
              // 返回按钮
              Positioned(
                top: 4,
                left: 0,
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: isLight ? const Color(0xFF2D3748) : Colors.white,
                  ),
                  onPressed: isLoading
                      ? null
                      : () => ref.read(playbackModeProvider.notifier).clearMode(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    bool enableClear = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            prefixIcon,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            size: 26,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
        ),
        suffixIcon: suffixIcon ?? (
          enableClear && controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    size: 22,
                  ),
                  onPressed: () => controller.clear(),
                )
              : null
        ),
        labelStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          fontSize: 14,
        ),
        filled: true,
        fillColor:
            Theme.of(context).brightness == Brightness.light
                ? Colors.black.withOpacity(0.03)
                : Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 2),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFFF6B6B),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildModernButton({
    required VoidCallback? onPressed,
    required bool isLoading,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient:
            onPressed != null
                ? const LinearGradient(
                  colors: [Color(0xFF23B0A6), Color(0xFF1EA396)],
                )
                : LinearGradient(
                  colors: [
                    Colors.grey.withOpacity(0.3),
                    Colors.grey.withOpacity(0.3),
                  ],
                ),
        borderRadius: BorderRadius.circular(16),
        boxShadow:
            onPressed != null
                ? [
                  BoxShadow(
                    color: const Color(0xFF23B0A6).withOpacity(0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
                : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            alignment: Alignment.center,
            child:
                isLoading
                    ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : const Text(
                      '登录',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}
