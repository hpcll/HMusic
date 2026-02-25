import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../providers/direct_mode_provider.dart';
import '../widgets/app_snackbar.dart';
import 'captcha_webview_page.dart';

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
  void initState() {
    super.initState();
    void listener() {
      if (mounted) setState(() {});
    }
    _accountController.addListener(listener);
    _passwordController.addListener(listener);
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
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

  /// 🎯 显示 WebView 验证码页面
  /// 用户在 WebView 中完成验证后，自动重试登录
  Future<void> _showCaptchaWebView(
    BuildContext context,
    DirectModeNeedsCaptcha captchaState,
  ) async {
    debugPrint('🌐 [DirectMode] 显示 WebView 验证码页面');

    // 🎯 用于跟踪验证是否完成和提取的 Cookie
    bool verificationCompleted = false;
    Map<String, String>? extractedCookies;

    // 显示 WebView 验证码页面
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CaptchaWebViewPage(
          captchaUrl: captchaState.captchaUrl,
          onVerificationComplete: (cookies) {
            debugPrint('✅ [DirectMode] WebView 验证完成，准备重试登录');
            final safeCookies = <String, String>{};
            cookies?.forEach((k, v) {
              if (k == 'passToken' ||
                  k == 'serviceToken' ||
                  k == 'ssecurity') {
                safeCookies[k] = v.length <= 6
                    ? '***'
                    : '${v.substring(0, 3)}***${v.substring(v.length - 3)}';
              } else {
                safeCookies[k] = v;
              }
            });
            debugPrint('🍪 [DirectMode] 收到 Cookie: $safeCookies');
            verificationCompleted = true;
            extractedCookies = cookies;
          },
        ),
      ),
    );

    // 🎯 只有当验证完成后才重试登录，避免无限循环
    if (mounted && verificationCompleted) {
      debugPrint('🔄 [DirectMode] 验证完成，自动重试登录');

      // 🎯 使用提取的 Cookie 进行登录
      await ref.read(directModeProvider.notifier).loginWithCookies(
            account: captchaState.account,
            password: captchaState.password,
            cookies: extractedCookies,
            saveCredentials: true,
          );
    } else {
      debugPrint('⚠️ [DirectMode] 用户取消验证，不重试登录');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听登录状态
    final directModeState = ref.watch(directModeProvider);

    // 登录成功后跳转
    ref.listen<DirectModeState>(directModeProvider, (previous, next) {
      if (next is DirectModeAuthenticated) {
        AppSnackBar.showSuccess(
          context,
          '登录成功！找到 ${next.devices.length} 个设备',
        );
        context.go('/');
      } else if (next is DirectModeNeedsCaptcha) {
        _showCaptchaWebView(context, next);
      } else if (next is DirectModeError) {
        AppSnackBar.showError(
          context,
          next.message,
        );
      }
    });

    final isLoading = directModeState is DirectModeLoading;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

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
                        '直连模式',
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
                        '使用小米账号登录，直接控制小爱音箱',
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
                      color: isLight
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isLight
                            ? Colors.black.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                      boxShadow: isLight
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
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
                          // 小米账号输入框
                          _buildModernTextField(
                            controller: _accountController,
                            labelText: '小米账号',
                            hintText: '手机号/邮箱',
                            prefixIcon: Icons.person_rounded,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.emailAddress,
                            enableClear: true,
                            enabled: !isLoading,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return '请输入小米账号';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // 密码输入框
                          _buildModernTextField(
                            controller: _passwordController,
                            labelText: '密码',
                            hintText: '小米账号密码',
                            prefixIcon: Icons.lock_rounded,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _handleLogin(),
                            enabled: !isLoading,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                size: 22,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请输入密码';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 32),

                          // 错误提示
                          if (directModeState is DirectModeError)
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B6B)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFF6B6B)
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFFF6B6B),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      directModeState.message,
                                      style: const TextStyle(
                                        color: Color(0xFFFF6B6B),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // 登录按钮
                          _buildModernButton(
                            onPressed: isLoading ? null : _handleLogin,
                            isLoading: isLoading,
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
    bool enabled = true,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    TextInputType? keyboardType,
    void Function(String)? onSubmitted,
    bool enableClear = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      keyboardType: keyboardType,
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
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            size: 26,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
        ),
        suffixIcon: suffixIcon ??
            (enableClear && controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                      size: 22,
                    ),
                    onPressed: () => controller.clear(),
                  )
                : null),
        labelStyle: TextStyle(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          fontSize: 14,
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.light
            ? Colors.black.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: Color(0xFF667EEA), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: Color(0xFFFF6B6B), width: 2),
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
        gradient: onPressed != null
            ? const LinearGradient(
                colors: [Color(0xFF23B0A6), Color(0xFF1EA396)],
              )
            : LinearGradient(
                colors: [
                  Colors.grey.withValues(alpha: 0.3),
                  Colors.grey.withValues(alpha: 0.3),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: const Color(0xFF23B0A6).withValues(alpha: 0.22),
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
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
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
