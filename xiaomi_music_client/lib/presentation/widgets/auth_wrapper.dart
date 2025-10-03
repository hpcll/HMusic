import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/login_page.dart';
import '../pages/main_page.dart';
import '../providers/auth_provider.dart';
import '../providers/unified_js_provider.dart';
import '../providers/source_settings_provider.dart';
import '../providers/js_script_manager_provider.dart';

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});
  
  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _jsPreloadAttempted = false;
  
  @override
  void initState() {
    super.initState();
    
    // 使用postFrameCallback确保在第一帧渲染后执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptJsPreload();
    });
  }
  
  /// 尝试预加载JS脚本（后台执行，不阻塞UI）
  Future<void> _attemptJsPreload() async {
    // 避免重复预加载
    if (_jsPreloadAttempted) return;
    _jsPreloadAttempted = true;
    
    final authState = ref.read(authProvider);
    
    // 只在已登录状态下预加载
    if (authState is! AuthAuthenticated) {
      print('[AuthWrapper] ℹ️ 未登录，跳过JS预加载');
      return;
    }
    
    try {
      // ✨ 关键修复：等待设置加载完成
      final settingsNotifier = ref.read(sourceSettingsProvider.notifier);
      int waitCount = 0;
      while (!settingsNotifier.isLoaded && waitCount < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      
      if (!settingsNotifier.isLoaded) {
        print('[AuthWrapper] ⚠️ 设置加载超时，跳过预加载');
        return;
      }
      
      // 现在设置已经加载完成，可以安全读取
      final settings = ref.read(sourceSettingsProvider);
      print('[AuthWrapper] 📋 音源设置: primarySource=${settings.primarySource}');
      
      if (settings.primarySource != 'js_external') {
        print('[AuthWrapper] ℹ️ 未启用JS音源，跳过预加载');
        return;
      }
      
      // 获取选中的脚本
      final scriptManager = ref.read(jsScriptManagerProvider.notifier);
      final selectedScript = scriptManager.selectedScript;
      
      if (selectedScript == null) {
        print('[AuthWrapper] ⚠️ 未选择JS脚本，跳过预加载');
        return;
      }
      
      // 后台预加载脚本
      print('[AuthWrapper] 🚀 开始后台预加载JS脚本: ${selectedScript.name}');
      final jsNotifier = ref.read(unifiedJsProvider.notifier);
      
      // 传入Cookie（如果有）
      final success = await jsNotifier.loadScript(
        selectedScript,
        cookieNetease: settings.cookieNetease,
        cookieTencent: settings.cookieTencent,
      );
      
      if (success) {
        print('[AuthWrapper] ✅ JS脚本预加载完成');
      } else {
        print('[AuthWrapper] ⚠️ JS脚本预加载失败');
      }
      
    } catch (e) {
      print('[AuthWrapper] ❌ JS预加载异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    
    // 监听登录状态变化，成功登录后重置预加载标记
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous is! AuthAuthenticated && next is AuthAuthenticated) {
        print('[AuthWrapper] 🔑 检测到登录成功，准备预加载JS');
        _jsPreloadAttempted = false;
        
        // 延迟一小段时间再预加载，让其他Provider先初始化
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _attemptJsPreload();
          }
        });
      }
    });

    return switch (authState) {
      AuthAuthenticated() => const MainPage(),
      AuthLoading() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _ => const LoginPage(),
    };
  }
}
