import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/local_js_source_service.dart';
import '../../data/services/webview_js_source_service.dart';
import 'source_settings_provider.dart';
import 'js_script_manager_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 提供已加载脚本的本地 JS 音源服务。
final jsSourceServiceProvider = FutureProvider<LocalJsSourceService?>((
  ref,
) async {
  final settings = ref.watch(sourceSettingsProvider);
  final scriptManager = ref.read(jsScriptManagerProvider.notifier);
  final selectedScript = scriptManager.selectedScript;
  
  final jsSelected =
      settings.primarySource == 'js_external' || settings.enabled;
  if (!jsSelected || selectedScript == null) return null;
  
  final svc = await LocalJsSourceService.create();
  await svc.loadScript(settings, selectedScript);
  if (!svc.isReady) return null;
  return svc;
});

/// 提供一个隐藏 WebView 的 JS 音源服务
final webviewJsSourceControllerProvider = StateProvider<WebViewController?>(
  (ref) => null,
);

final webviewJsSourceServiceProvider = FutureProvider<WebViewJsSourceService?>((
  ref,
) async {
  final settings = ref.watch(sourceSettingsProvider);
  final ctrl = ref.watch(webviewJsSourceControllerProvider);
  final jsSelected =
      settings.primarySource == 'js_external' || settings.enabled;
  if (!jsSelected || settings.scriptUrl.isEmpty || ctrl == null) return null;
  final svc = WebViewJsSourceService(ctrl);
  await svc.init(settings);
  return svc;
});
