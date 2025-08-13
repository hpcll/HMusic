import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SourceSettings {
  final bool enabled;
  final String scriptUrl; // 远程 JS 地址（如 sixyin latest.js）
  final String
  platform; // 可选：优先平台，如 'auto' | 'qq' | 'netease' | 'kuwo' | 'kugou'
  final String cookieNetease; // MUSIC_U=
  final String cookieTencent; // ts_last= 等
  final bool useJsForSearch; // 是否使用JS音源执行搜索
  final bool jsOnlyNoFallback; // 仅JS调试：禁用回落到内置
  final bool useUnifiedApi; // 是否使用统一API (music.txqq.pro)
  final String unifiedApiBase; // 统一API基础地址
  final bool useYouTubeProxy; // 是否使用YouTube代理搜索 (需要翻墙)
  final String youTubeDownloadSource; // YouTube下载源选择
  final String youTubeAudioQuality; // YouTube音频质量选择
  final bool enableTts; // 是否启用TTS文字转语音功能
  final String ttsTestText; // TTS测试文字

  const SourceSettings({
    this.enabled = true,
    // 使用支持完整功能的xiaoqiu.js作为默认脚本
    this.scriptUrl =
        'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js',
    this.platform = 'auto',
    this.cookieNetease = '',
    this.cookieTencent = '',
    this.useJsForSearch = false,
    this.jsOnlyNoFallback = false,
    this.useUnifiedApi = true, // 新用户默认使用统一API，更稳定可靠
    this.unifiedApiBase = 'https://music.txqq.pro', // 统一API默认地址
    this.useYouTubeProxy = false, // 默认关闭YouTube代理（需要翻墙）
    this.youTubeDownloadSource = 'oceansaver', // 默认使用OceanSaver下载源
    this.youTubeAudioQuality = '320k', // 默认使用320k高音质
    this.enableTts = false, // 默认关闭TTS功能
    this.ttsTestText = '你好，这是TTS测试', // 默认TTS测试文字
  });

  SourceSettings copyWith({
    bool? enabled,
    String? scriptUrl,
    String? platform,
    String? cookieNetease,
    String? cookieTencent,
    bool? useJsForSearch,
    bool? jsOnlyNoFallback,
    bool? useUnifiedApi,
    String? unifiedApiBase,
    bool? useYouTubeProxy,
    String? youTubeDownloadSource,
    String? youTubeAudioQuality,
    bool? enableTts,
    String? ttsTestText,
  }) {
    return SourceSettings(
      enabled: enabled ?? this.enabled,
      scriptUrl: scriptUrl ?? this.scriptUrl,
      platform: platform ?? this.platform,
      cookieNetease: cookieNetease ?? this.cookieNetease,
      cookieTencent: cookieTencent ?? this.cookieTencent,
      useJsForSearch: useJsForSearch ?? this.useJsForSearch,
      jsOnlyNoFallback: jsOnlyNoFallback ?? this.jsOnlyNoFallback,
      useUnifiedApi: useUnifiedApi ?? this.useUnifiedApi,
      unifiedApiBase: unifiedApiBase ?? this.unifiedApiBase,
      useYouTubeProxy: useYouTubeProxy ?? this.useYouTubeProxy,
      youTubeDownloadSource:
          youTubeDownloadSource ?? this.youTubeDownloadSource,
      youTubeAudioQuality: youTubeAudioQuality ?? this.youTubeAudioQuality,
      enableTts: enableTts ?? this.enableTts,
      ttsTestText: ttsTestText ?? this.ttsTestText,
    );
  }
}

class SourceSettingsNotifier extends StateNotifier<SourceSettings> {
  static const _kEnabled = 'source_enabled';
  static const _kScriptUrl = 'source_script_url';
  static const _kPlatform = 'source_platform';
  static const _kNetease = 'source_cookie_netease';
  static const _kTencent = 'source_cookie_tencent';
  static const _kUseJsForSearch = 'source_use_js_search';
  static const _kJsOnlyNoFallback = 'source_js_only_no_fallback';
  static const _kUseUnifiedApi = 'source_use_unified_api';
  static const _kUnifiedApiBase = 'source_unified_api_base';
  static const _kUseYouTubeProxy = 'source_use_youtube_proxy';
  static const _kYouTubeDownloadSource = 'source_youtube_download_source';
  static const _kYouTubeAudioQuality = 'source_youtube_audio_quality';
  static const _kEnableTts = 'source_enable_tts';
  static const _kTtsTestText = 'source_tts_test_text';

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  SourceSettingsNotifier() : super(const SourceSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_kEnabled);
      final scriptUrl = prefs.getString(_kScriptUrl);
      final platform = prefs.getString(_kPlatform);
      final cookieNe = prefs.getString(_kNetease);
      final cookieTx = prefs.getString(_kTencent);
      final useJsSearch = prefs.getBool(_kUseJsForSearch);
      final jsOnly = prefs.getBool(_kJsOnlyNoFallback);
      final useUnifiedApi = prefs.getBool(_kUseUnifiedApi);
      final unifiedApiBase = prefs.getString(_kUnifiedApiBase);
      final useYouTubeProxy = prefs.getBool(_kUseYouTubeProxy);
      final youTubeDownloadSource = prefs.getString(_kYouTubeDownloadSource);
      final youTubeAudioQuality = prefs.getString(_kYouTubeAudioQuality);
      final enableTts = prefs.getBool(_kEnableTts);
      final ttsTestText = prefs.getString(_kTtsTestText);

      print('🔧 [SourceSettings] 加载设置:');
      print('  - enabled: $enabled');
      print('  - useJsForSearch: $useJsSearch');
      print('  - jsOnlyNoFallback: $jsOnly');
      print('  - useUnifiedApi: $useUnifiedApi');
      print('  - useYouTubeProxy: $useYouTubeProxy');
      print('  - youTubeDownloadSource: $youTubeDownloadSource');
      print('  - youTubeAudioQuality: $youTubeAudioQuality');
      print('  - enableTts: $enableTts');
      print('  - ttsTestText: $ttsTestText');
      print('  - 原始URL长度: ${scriptUrl?.length ?? 0}');
      print('  - 原始URL: $scriptUrl');
      print('  - unifiedApiBase: $unifiedApiBase');

      // 若用户未设置脚本 URL，则保留我们预设的镜像默认值
      final finalUrl =
          (scriptUrl == null || scriptUrl.isEmpty)
              ? state.scriptUrl
              : scriptUrl;
      print('🔧 [SourceSettings] 最终URL长度: ${finalUrl.length}');
      print('🔧 [SourceSettings] 最终URL: $finalUrl');

      state = state.copyWith(
        enabled: enabled ?? state.enabled,
        scriptUrl: finalUrl,
        platform: platform ?? state.platform,
        cookieNetease: cookieNe ?? state.cookieNetease,
        cookieTencent: cookieTx ?? state.cookieTencent,
        useJsForSearch: useJsSearch ?? state.useJsForSearch,
        jsOnlyNoFallback: jsOnly ?? state.jsOnlyNoFallback,
        useUnifiedApi: useUnifiedApi ?? state.useUnifiedApi,
        unifiedApiBase: unifiedApiBase ?? state.unifiedApiBase,
        useYouTubeProxy: useYouTubeProxy ?? state.useYouTubeProxy,
        youTubeDownloadSource:
            youTubeDownloadSource ?? state.youTubeDownloadSource,
        youTubeAudioQuality: youTubeAudioQuality ?? state.youTubeAudioQuality,
        enableTts: enableTts ?? state.enableTts,
        ttsTestText: ttsTestText ?? state.ttsTestText,
      );
    } catch (e) {
      print('❌ [SourceSettings] 加载设置失败: $e');
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> save(SourceSettings s) async {
    print('🔧 [SourceSettings] 开始保存设置:');
    print('  - enabled: ${s.enabled}');
    print('  - useJsForSearch: ${s.useJsForSearch}');
    print('  - jsOnlyNoFallback: ${s.jsOnlyNoFallback}');
    print('  - useUnifiedApi: ${s.useUnifiedApi}');
    print('  - useYouTubeProxy: ${s.useYouTubeProxy}');
          print('  - youTubeDownloadSource: ${s.youTubeDownloadSource}');
      print('  - youTubeAudioQuality: ${s.youTubeAudioQuality}');
      print('  - enableTts: ${s.enableTts}');
      print('  - ttsTestText: ${s.ttsTestText}');
    print('  - scriptUrl长度: ${s.scriptUrl.length}');
    print('  - unifiedApiBase: ${s.unifiedApiBase}');

    // 先更新state
    state = s;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_kEnabled, s.enabled);
    await prefs.setString(_kScriptUrl, s.scriptUrl);
    await prefs.setString(_kPlatform, s.platform);
    await prefs.setString(_kNetease, s.cookieNetease);
    await prefs.setString(_kTencent, s.cookieTencent);
    await prefs.setBool(_kUseJsForSearch, s.useJsForSearch);
    await prefs.setBool(_kJsOnlyNoFallback, s.jsOnlyNoFallback);
    await prefs.setBool(_kUseUnifiedApi, s.useUnifiedApi);
    await prefs.setString(_kUnifiedApiBase, s.unifiedApiBase);
    await prefs.setBool(_kUseYouTubeProxy, s.useYouTubeProxy);
    await prefs.setString(_kYouTubeDownloadSource, s.youTubeDownloadSource);
    await prefs.setString(_kYouTubeAudioQuality, s.youTubeAudioQuality);
    await prefs.setBool(_kEnableTts, s.enableTts);
    await prefs.setString(_kTtsTestText, s.ttsTestText);

    // 立即验证保存是否成功
    final savedEnabled = prefs.getBool(_kEnabled);
    final savedUseJs = prefs.getBool(_kUseJsForSearch);
    final savedJsOnly = prefs.getBool(_kJsOnlyNoFallback);
    final savedUseUnified = prefs.getBool(_kUseUnifiedApi);
    final savedUseYouTube = prefs.getBool(_kUseYouTubeProxy);
    final savedYouTubeSource = prefs.getString(_kYouTubeDownloadSource);
    final savedYouTubeQuality = prefs.getString(_kYouTubeAudioQuality);
    final savedEnableTts = prefs.getBool(_kEnableTts);
    final savedTtsTestText = prefs.getString(_kTtsTestText);
    final savedUrl = prefs.getString(_kScriptUrl);
    final savedApiBase = prefs.getString(_kUnifiedApiBase);

    print('🔧 [SourceSettings] SharedPreferences保存验证:');
    print('  - enabled: $savedEnabled');
    print('  - useJsForSearch: $savedUseJs');
    print('  - jsOnlyNoFallback: $savedJsOnly');
    print('  - useUnifiedApi: $savedUseUnified');
    print('  - useYouTubeProxy: $savedUseYouTube');
    print('  - youTubeDownloadSource: $savedYouTubeSource');
    print('  - youTubeAudioQuality: $savedYouTubeQuality');
    print('  - enableTts: $savedEnableTts');
    print('  - ttsTestText: $savedTtsTestText');
    print('  - scriptUrl: $savedUrl');
    print('  - unifiedApiBase: $savedApiBase');

    print('🔧 [SourceSettings] 最终state状态:');
    print('  - state.enabled: ${state.enabled}');
    print('  - state.useJsForSearch: ${state.useJsForSearch}');
    print('  - state.jsOnlyNoFallback: ${state.jsOnlyNoFallback}');
    print('  - state.useUnifiedApi: ${state.useUnifiedApi}');
    print('  - state.useYouTubeProxy: ${state.useYouTubeProxy}');
    print('  - state.youTubeDownloadSource: ${state.youTubeDownloadSource}');
    print('  - state.youTubeAudioQuality: ${state.youTubeAudioQuality}');
  }
}

/// 原始的StateNotifierProvider，用于状态管理
final sourceSettingsProvider =
    StateNotifierProvider<SourceSettingsNotifier, SourceSettings>((ref) {
      return SourceSettingsNotifier();
    });

/// 直接访问notifier的provider（用于保存设置）
final sourceSettingsNotifierProvider = sourceSettingsProvider.notifier;
