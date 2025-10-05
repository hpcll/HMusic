import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SourceSettings {
  final bool enabled;
  final String scriptUrl; // 远程 JS 地址
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
  final bool useBuiltinScript; // 是否使用内置脚本（优先级高于scriptUrl）
  final String
  primarySource; // 主要音源选择: 'unified' | 'youtube' | 'js_external' | 'js_builtin'
  final String scriptPreset; // 预置脚本选择: 'xiaoqiu' | 'custom' | 'local_file'
  final String localScriptPath; // 本地脚本文件路径
  final String
  jsSearchStrategy; // JS流程下搜索优先级: qqOnly|kuwoOnly|neteaseOnly|qqFirst|kuwoFirst|neteaseFirst
  final String defaultDownloadQuality; // 默认下载音质: 'lossless' | 'high' | 'standard'

  const SourceSettings({
    this.enabled = true,
    // 公开版本不提供默认JS脚本，用户需要自行添加
    this.scriptUrl = '',
    this.platform = 'auto',
    this.cookieNetease = '',
    this.cookieTencent = '',
    this.useJsForSearch = false,
    this.jsOnlyNoFallback = false,
    this.useUnifiedApi = true, // 新用户默认使用统一API，更稳定可靠
    this.unifiedApiBase = 'https://music.txqq.pro', // 统一API默认地址
    this.useYouTubeProxy = false, // 公开版本不包含YouTube代理功能
    this.youTubeDownloadSource = '', // 移除YouTube相关配置
    this.youTubeAudioQuality = '', // 移除YouTube相关配置
    this.enableTts = false, // 默认关闭TTS功能
    this.ttsTestText = '你好，这是TTS测试', // 默认TTS测试文字
    this.useBuiltinScript = false, // 公开版本无内置脚本
    this.primarySource = 'unified', // 默认使用统一API
    this.scriptPreset = 'custom', // 默认选择自定义
    this.localScriptPath = '', // 默认无本地脚本路径
    this.jsSearchStrategy = 'qqFirst',
    this.defaultDownloadQuality = 'high', // 默认高品质 (320k)
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
    bool? useBuiltinScript,
    String? primarySource,
    String? scriptPreset,
    String? localScriptPath,
    String? jsSearchStrategy,
    String? defaultDownloadQuality,
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
      useBuiltinScript: useBuiltinScript ?? this.useBuiltinScript,
      primarySource: primarySource ?? this.primarySource,
      scriptPreset: scriptPreset ?? this.scriptPreset,
      localScriptPath: localScriptPath ?? this.localScriptPath,
      jsSearchStrategy: jsSearchStrategy ?? this.jsSearchStrategy,
      defaultDownloadQuality: defaultDownloadQuality ?? this.defaultDownloadQuality,
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
  static const _kUseBuiltinScript = 'source_use_builtin_script';
  static const _kPrimarySource = 'source_primary_source';
  static const _kScriptPreset = 'source_script_preset';
  static const _kLocalScriptPath = 'source_local_script_path';
  static const _kJsSearchStrategy = 'source_js_search_strategy';
  static const _kDefaultDownloadQuality = 'source_default_download_quality';

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
      final useBuiltinScript = prefs.getBool(_kUseBuiltinScript);
      final primarySource = prefs.getString(_kPrimarySource);
      final scriptPreset = prefs.getString(_kScriptPreset);
      final localScriptPath = prefs.getString(_kLocalScriptPath);
      final jsSearchStrategy = prefs.getString(_kJsSearchStrategy);
      final defaultDownloadQuality = prefs.getString(_kDefaultDownloadQuality);

      print('[XMC] 🔧 [SourceSettings] 加载设置:');
      print('  - enabled: $enabled');
      print('  - scriptUrl: $scriptUrl');
      print('  - useJsForSearch: $useJsSearch');
      print('  - jsOnlyNoFallback: $jsOnly');
      print('  - useUnifiedApi: $useUnifiedApi');
      print('  - useYouTubeProxy: $useYouTubeProxy');
      print('  - youTubeDownloadSource: $youTubeDownloadSource');
      print('  - youTubeAudioQuality: $youTubeAudioQuality');
      print('  - enableTts: $enableTts');
      print('  - ttsTestText: $ttsTestText');
      print('  - useBuiltinScript: $useBuiltinScript');
      print('  - primarySource: $primarySource (从SharedPreferences读取)');
      print('  - scriptPreset: $scriptPreset');
      print('  - localScriptPath: $localScriptPath');
      print('  - unifiedApiBase: $unifiedApiBase');
      print('  - state.primarySource: ${state.primarySource} (当前状态默认值)');

      // 公开版本：清理所有可能的xiaoqiu.js遗留配置
      String? finalUrl = scriptUrl;
      bool needsCleanup = false;

      if (finalUrl != null && finalUrl.contains('xiaoqiu.js')) {
        print('[XMC] 🧹 [SourceSettings] 检测到遗留的xiaoqiu.js配置，自动清理');
        finalUrl = '';
        needsCleanup = true;
      }

      // 只有检测到xiaoqiu.js时才重置primarySource，避免覆盖用户的JS设置
      if (needsCleanup) {
        // 清理遗留配置
        await prefs.setString(_kScriptUrl, '');
        await prefs.setBool(_kUseBuiltinScript, false);
        await prefs.setString(_kScriptPreset, 'custom');
        await prefs.setString(_kPrimarySource, 'unified');
      }

      // 确保公开版本的默认设置
      finalUrl = finalUrl ?? state.scriptUrl;

      // 调试：最终的primarySource值
      final finalPrimarySource =
          needsCleanup ? 'unified' : (primarySource ?? state.primarySource);
      print('[XMC] 🔧 [SourceSettings] 最终primarySource设置:');
      print('  - needsCleanup: $needsCleanup');
      print('  - primarySource from prefs: $primarySource');
      print('  - state.primarySource: ${state.primarySource}');
      print('  - finalPrimarySource: $finalPrimarySource');

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
        useBuiltinScript: useBuiltinScript ?? state.useBuiltinScript,
        // 只有在清理遗留配置时才强制设为unified，否则保持用户设置
        primarySource: finalPrimarySource,
        scriptPreset: scriptPreset ?? state.scriptPreset,
        localScriptPath: localScriptPath ?? state.localScriptPath,
        jsSearchStrategy: jsSearchStrategy ?? state.jsSearchStrategy,
        defaultDownloadQuality: defaultDownloadQuality ?? state.defaultDownloadQuality,
      );
    } catch (e) {
      print('[XMC] ❌ [SourceSettings] 加载设置失败: $e');
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> save(SourceSettings s) async {
    print('[XMC] 🔧 [SourceSettings] 开始保存设置:');
    print('  - enabled: ${s.enabled}');
    print('  - useJsForSearch: ${s.useJsForSearch}');
    print('  - jsOnlyNoFallback: ${s.jsOnlyNoFallback}');
    print('  - useUnifiedApi: ${s.useUnifiedApi}');
    print('  - useYouTubeProxy: ${s.useYouTubeProxy}');
    print('  - youTubeDownloadSource: ${s.youTubeDownloadSource}');
    print('  - youTubeAudioQuality: ${s.youTubeAudioQuality}');
    print('  - enableTts: ${s.enableTts}');
    print('  - ttsTestText: ${s.ttsTestText}');
    print('  - useBuiltinScript: ${s.useBuiltinScript}');
    print('  - primarySource: ${s.primarySource}');
    print('  - scriptPreset: ${s.scriptPreset}');
    print('  - localScriptPath: ${s.localScriptPath}');
    print('  - unifiedApiBase: ${s.unifiedApiBase}');

    try {
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
      await prefs.setBool(_kUseBuiltinScript, s.useBuiltinScript);
      await prefs.setString(_kPrimarySource, s.primarySource);
      await prefs.setString(_kScriptPreset, s.scriptPreset);
      await prefs.setString(_kLocalScriptPath, s.localScriptPath);
      await prefs.setString(_kJsSearchStrategy, s.jsSearchStrategy);
      await prefs.setString(_kDefaultDownloadQuality, s.defaultDownloadQuality);

      // 只有保存成功后才更新state
      state = s;

      print('[XMC] 🔧 [SourceSettings] 设置保存成功');
    } catch (e) {
      print('[XMC] ❌ [SourceSettings] 保存设置失败: $e');
      rethrow; // 重新抛出异常，让UI层处理
    }

    // 验证保存结果
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEnabled = prefs.getBool(_kEnabled);
      final savedUseJs = prefs.getBool(_kUseJsForSearch);
      final savedJsOnly = prefs.getBool(_kJsOnlyNoFallback);
      final savedUseUnified = prefs.getBool(_kUseUnifiedApi);
      final savedUseYouTube = prefs.getBool(_kUseYouTubeProxy);
      final savedYouTubeSource = prefs.getString(_kYouTubeDownloadSource);
      final savedYouTubeQuality = prefs.getString(_kYouTubeAudioQuality);
      final savedEnableTts = prefs.getBool(_kEnableTts);
      final savedTtsTestText = prefs.getString(_kTtsTestText);
      final savedUseBuiltinScript = prefs.getBool(_kUseBuiltinScript);
      final savedPrimarySource = prefs.getString(_kPrimarySource);
      final savedLocalScriptPath = prefs.getString(_kLocalScriptPath);
      final savedJsSearchStrategy = prefs.getString(_kJsSearchStrategy);

      final savedApiBase = prefs.getString(_kUnifiedApiBase);
      final savedScriptPreset = prefs.getString(_kScriptPreset);

      print('[XMC] 🔧 [SourceSettings] SharedPreferences保存验证:');
      print('  - enabled: $savedEnabled');
      print('  - useJsForSearch: $savedUseJs');
      print('  - jsOnlyNoFallback: $savedJsOnly');
      print('  - useUnifiedApi: $savedUseUnified');
      print('  - useYouTubeProxy: $savedUseYouTube');
      print('  - youTubeDownloadSource: $savedYouTubeSource');
      print('  - youTubeAudioQuality: $savedYouTubeQuality');
      print('  - enableTts: $savedEnableTts');
      print('  - ttsTestText: $savedTtsTestText');
      print('  - useBuiltinScript: $savedUseBuiltinScript');
      print('  - primarySource: $savedPrimarySource');
      print('  - scriptPreset: $savedScriptPreset');
      print('  - localScriptPath: $savedLocalScriptPath');
      print('  - unifiedApiBase: $savedApiBase');
      print('  - jsSearchStrategy: $savedJsSearchStrategy');
    } catch (e) {
      print('[XMC] ⚠️ [SourceSettings] 验证保存结果时出错: $e');
    }
  }
}

/// 原始的StateNotifierProvider，用于状态管理
final sourceSettingsProvider =
    StateNotifierProvider<SourceSettingsNotifier, SourceSettings>((ref) {
      return SourceSettingsNotifier();
    });

/// 直接访问notifier的provider（用于保存设置）
final sourceSettingsNotifierProvider = sourceSettingsProvider.notifier;
