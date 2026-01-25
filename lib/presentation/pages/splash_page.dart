import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/initialization_provider.dart';

/// Splash 启动页：展示 App Logo，执行初始化逻辑
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();

    // 启动初始化流程
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInitialization();
    });
  }

  /// 启动初始化流程
  Future<void> _startInitialization() async {
    final notifier = ref.read(initializationProvider.notifier);
    await notifier.initialize();

    // 初始化完成后跳转
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        context.go('/');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initState = ref.watch(initializationProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // APP Logo 带缩放动画 - 与原生启屏页完全一致
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SvgPicture.asset(
                      'assets/hmusic-logo.svg',
                      width: 240,
                      height: 240,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 1),
              // 下方内容
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                  const SizedBox(height: 40),

                  // APP 名称
                  const Text(
                    'HMusic',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 副标题
                  Text(
                    '播放 NAS 音乐',
                    style: TextStyle(
                      fontSize: 17,
                      color: const Color(0xFF4A5568).withOpacity(0.75),
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 80),

                  // 加载进度条
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 60),
                    child: Column(
                      children: [
                        // 进度条
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            height: 6,
                            child: LinearProgressIndicator(
                              value: initState.progress,
                              backgroundColor: Colors.grey.withOpacity(0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF21B0A5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 加载文本
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: Text(
                            initState.message,
                            key: ValueKey<String>(initState.message),
                            style: TextStyle(
                              fontSize: 15,
                              color: const Color(0xFF4A5568).withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60),

                  // 版本信息
                  Text(
                    'Version 1.2.1',
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFF718096).withOpacity(0.6),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}
