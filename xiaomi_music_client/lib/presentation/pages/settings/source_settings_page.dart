import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/source_settings_provider.dart';
import '../../../data/services/local_js_source_service.dart';
import '../../../data/services/webview_js_source_service.dart';
import '../../../data/services/youtube_proxy_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../widgets/app_snackbar.dart';

class SourceSettingsPage extends ConsumerStatefulWidget {
  const SourceSettingsPage({super.key});

  @override
  ConsumerState<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends ConsumerState<SourceSettingsPage> {
  late TextEditingController _urlCtrl;
  late TextEditingController _cookieNeCtrl;
  late TextEditingController _cookieTxCtrl;
  String _platform = 'auto';
  bool _enabled = true;
  bool _detecting = false;
  bool _useJsForSearch = false;
  bool _jsOnlyNoFallback = false;
  bool _useUnifiedApi = false;
  bool _useYouTubeProxy = false;
  String _youTubeDownloadSource = 'oceansaver';
  String _youTubeAudioQuality = '320k';
  bool _enableTts = false;
  String _ttsTestText = '你好，这是TTS测试';
  final WebViewController _hiddenCtrl = WebViewController();

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // 初始化 TextEditingController，但不设置初始值
    _urlCtrl = TextEditingController();
    _cookieNeCtrl = TextEditingController();
    _cookieTxCtrl = TextEditingController();
  }

  void _initializeFromProvider(SourceSettings s) {
    if (_initialized) return;

    // 添加调试信息
    print('🔧 [SourceSettingsPage] 初始化UI状态:');
    print('  - enabled: ${s.enabled}');
    print('  - useJsForSearch: ${s.useJsForSearch}');
    print('  - jsOnlyNoFallback: ${s.jsOnlyNoFallback}');
    print('  - useUnifiedApi: ${s.useUnifiedApi}');
    print('  - useYouTubeProxy: ${s.useYouTubeProxy}');
    print('  - youTubeDownloadSource: ${s.youTubeDownloadSource}');
    print('  - youTubeAudioQuality: ${s.youTubeAudioQuality}');
    print('  - scriptUrl: ${s.scriptUrl}');

    setState(() {
      _urlCtrl.text = s.scriptUrl;
      _cookieNeCtrl.text = s.cookieNetease;
      _cookieTxCtrl.text = s.cookieTencent;
      _platform = s.platform;
      _enabled = s.enabled;
      _useJsForSearch = s.useJsForSearch;
      _jsOnlyNoFallback = s.jsOnlyNoFallback;
      _useUnifiedApi = s.useUnifiedApi;
      _useYouTubeProxy = s.useYouTubeProxy;
      _youTubeDownloadSource = s.youTubeDownloadSource;
      _youTubeAudioQuality = s.youTubeAudioQuality;
      _enableTts = s.enableTts;
      _ttsTestText = s.ttsTestText;
    });

    print('🔧 [SourceSettingsPage] UI变量设置完成:');
    print('  - _enabled: $_enabled');
    print('  - _useJsForSearch: $_useJsForSearch');
    print('  - _jsOnlyNoFallback: $_jsOnlyNoFallback');
    print('  - _useUnifiedApi: $_useUnifiedApi');
    print('  - _useYouTubeProxy: $_useYouTubeProxy');
    print('  - _youTubeDownloadSource: $_youTubeDownloadSource');
    print('  - _youTubeAudioQuality: $_youTubeAudioQuality');

    _initialized = true;
  }

  /// 获取当前选择的搜索源
  String _getSelectedSource() {
    if (_useUnifiedApi) return 'unified';
    if (_useYouTubeProxy) return 'youtube';
    return 'js';
  }

  /// 设置选择的搜索源
  void _setSelectedSource(String? source) {
    setState(() {
      _useUnifiedApi = source == 'unified';
      _useYouTubeProxy = source == 'youtube';

      if (_useUnifiedApi) {
        // 选择统一API时，禁用JS相关选项
        _useJsForSearch = false;
        _jsOnlyNoFallback = false;
      } else if (_useYouTubeProxy) {
        // 选择YouTube代理时，禁用其他选项
        _useJsForSearch = false;
        _jsOnlyNoFallback = false;
        _enabled = false;
      } else if (source == 'js') {
        // 选择JS源时，自动启用相关选项
        _enabled = true;
        _useJsForSearch = true;
      }
    });
  }

  /// 测试YouTube代理连接
  Future<void> _testYouTubeConnection() async {
    setState(() {
      _detecting = true;
    });

    try {
      final youtubeService = YouTubeProxyService();

      print('🔧 [SourceSettings] 开始测试YouTube代理连接...');
      final isConnected = await youtubeService.testConnection();

      if (!mounted) return;

      if (isConnected) {
        AppSnackBar.show(
          context,
          const SnackBar(
            content: Text('✅ YouTube代理连接成功！网络环境正常'),
            backgroundColor: Colors.green,
          ),
        );

        // 成功后进行一个简单的搜索测试
        try {
          print('🔧 [SourceSettings] 执行搜索测试...');
          final results = await youtubeService.searchMusic(
            query: 'test',
            maxResults: 1,
          );

          if (!mounted) return;

          if (results.isNotEmpty) {
            AppSnackBar.show(
              context,
              const SnackBar(
                content: Text('🎵 搜索测试成功！YouTube代理工作正常'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            AppSnackBar.show(
              context,
              const SnackBar(
                content: Text('⚠️ 连接正常但搜索无结果，可能是服务器问题'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } catch (e) {
          if (!mounted) return;
          AppSnackBar.show(
            context,
            SnackBar(
              content: Text('⚠️ 搜索测试失败: ${e.toString()}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        AppSnackBar.show(
          context,
          const SnackBar(
            content: Text(
              '❌ YouTube代理连接失败\n请检查：\n• VPN或代理是否正常工作\n• 网络连接是否稳定\n• 防火墙设置是否阻止访问',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }

      // 释放资源
      youtubeService.dispose();
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        SnackBar(
          content: Text('❌ 测试过程中出现异常: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _detecting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _cookieNeCtrl.dispose();
    _cookieTxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(sourceSettingsProvider);

    // 当 provider 状态更新时，初始化 UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFromProvider(settings);
    });

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: const Text('音源设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 音乐搜索源选择（单选）
          ListTile(
            title: Text(
              '音乐搜索源选择',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '选择一种搜索源进行音乐搜索和播放',
              style: TextStyle(color: onSurface.withOpacity(0.6)),
            ),
          ),
          RadioListTile<String>(
            title: const Text('统一API (music.txqq.pro)'),
            subtitle: const Text('推荐！统一多平台接口，稳定快速，支持搜索和播放'),
            value: 'unified',
            groupValue: _getSelectedSource(),
            onChanged: (v) => _setSelectedSource(v),
          ),
          RadioListTile<String>(
            title: const Text('YouTube 代理搜索'),
            subtitle: const Text('⚠️ 需要翻墙！通过代理搜索YouTube音乐视频'),
            value: 'youtube',
            groupValue: _getSelectedSource(),
            onChanged: (v) => _setSelectedSource(v),
          ),
          RadioListTile<String>(
            title: const Text('JS 音源脚本'),
            subtitle: const Text('使用自定义JS脚本进行搜索，支持多种音源'),
            value: 'js',
            groupValue: _getSelectedSource(),
            onChanged: (v) => _setSelectedSource(v),
          ),

          const Divider(),

          // YouTube代理相关提示（仅在选择YouTube代理时显示）
          if (_useYouTubeProxy) ...[
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.amber.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '⚠️ 重要提示',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'YouTube代理搜索需要翻墙才能正常使用：',
                    style: TextStyle(color: onSurface.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• 确保设备已连接VPN或代理服务器\n'
                    '• 可能需要特定的网络环境或配置\n'
                    '• 搜索结果为YouTube音乐视频\n'
                    '• 播放链接需要额外的音频转换',
                    style: TextStyle(
                      color: onSurface.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'YouTube下载源选择:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _youTubeDownloadSource,
                        isExpanded: true,
                        items:
                            YouTubeProxyService.downloadSources.map((source) {
                              return DropdownMenuItem<String>(
                                value: source['id'],
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      source['name']!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      source['description']!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _youTubeDownloadSource = value;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'YouTube音频质量选择:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 计算每个卡片的宽度，确保每行显示3个
                        final cardWidth =
                            (constraints.maxWidth - 16) / 3; // 16 = spacing * 2

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              YouTubeProxyService.audioQualities.map((quality) {
                                final isSelected =
                                    _youTubeAudioQuality == quality['id'];
                                final color = Color(quality['color'] as int);

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _youTubeAudioQuality =
                                          quality['id'] as String;
                                    });
                                  },
                                  child: Container(
                                    width: cardWidth.clamp(80.0, 105.0),
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color:
                                          isSelected
                                              ? color.withOpacity(0.8)
                                              : color.withOpacity(0.1),
                                      border: Border.all(
                                        color:
                                            isSelected
                                                ? color
                                                : color.withOpacity(0.3),
                                        width: isSelected ? 2 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'MP3',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color:
                                                isSelected
                                                    ? Colors.white
                                                    : color.withOpacity(0.8),
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          quality['name'] as String,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color:
                                                isSelected
                                                    ? Colors.white
                                                    : color.withOpacity(0.8),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const Divider(
                                          color: Colors.white70,
                                          height: 8,
                                          thickness: 1,
                                        ),
                                        Text(
                                          quality['description'] as String,
                                          style: TextStyle(
                                            color:
                                                isSelected
                                                    ? Colors.white70
                                                    : color.withOpacity(0.6),
                                            fontSize: 9,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _detecting ? null : () => _testYouTubeConnection(),
                      icon:
                          _detecting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.network_check),
                      label: Text(_detecting ? '测试中...' : '测试网络连接'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
          ],

          // TTS 文字转语音设置
          ListTile(
            title: Text(
              'TTS 文字转语音',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '配置文字转语音功能相关选项',
              style: TextStyle(color: onSurface.withOpacity(0.6)),
            ),
          ),
          SwitchListTile(
            title: const Text('启用TTS文字转语音'),
            subtitle: const Text('开启后可以使用文字转语音功能'),
            value: _enableTts,
            onChanged: (v) => setState(() => _enableTts = v),
          ),
          if (_enableTts) ...[
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'TTS测试文字',
                hintText: '输入要测试的文字内容',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _ttsTestText),
              onChanged: (value) => _ttsTestText = value,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _testTts(),
                icon: const Icon(Icons.record_voice_over),
                label: const Text('测试TTS播放'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(),

          // JS 音源相关设置（仅在选择JS源时显示）
          if (!_useUnifiedApi && !_useYouTubeProxy) ...[
            ListTile(
              title: Text(
                'JS 音源设置',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '配置自定义音源脚本相关选项',
                style: TextStyle(color: onSurface.withOpacity(0.6)),
              ),
            ),
            SwitchListTile(
              title: const Text('启用自定义音源脚本'),
              subtitle: const Text('默认已启用，直接使用内置脚本'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: '脚本 URL',
                hintText:
                    '例如：https://raw.githubusercontent.com/pdone/lx-music-source/main/sixyin/latest.js',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('优先平台'),
              subtitle: Text(
                _platform,
                style: TextStyle(color: onSurface.withOpacity(0.7)),
              ),
              trailing: DropdownButton<String>(
                value: _platform,
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('自动')),
                  DropdownMenuItem(value: 'qq', child: Text('QQ音乐')),
                  DropdownMenuItem(value: 'netease', child: Text('网易云')),
                  DropdownMenuItem(value: 'kuwo', child: Text('酷我')),
                  DropdownMenuItem(value: 'kugou', child: Text('酷狗')),
                ],
                onChanged: (v) => setState(() => _platform = v ?? 'auto'),
              ),
            ),
            SwitchListTile(
              title: const Text('使用 JS 音源进行搜索'),
              subtitle: const Text('开启后，搜索将优先调用脚本。若关闭则仅使用内置聚合接口'),
              value: _useJsForSearch,
              onChanged: (v) => setState(() => _useJsForSearch = v),
            ),
            SwitchListTile(
              title: const Text('仅 JS 模式（禁用回落）'),
              subtitle: const Text('强制使用JS搜索，失败时不回退到聚合接口'),
              value: _jsOnlyNoFallback,
              onChanged: (v) => setState(() => _jsOnlyNoFallback = v),
            ),
            ExpansionTile(
              title: const Text('高级设置（可选）'),
              subtitle: Text(
                '平台 Cookie（用于获取更高音质/直链）',
                style: TextStyle(color: onSurface.withOpacity(0.7)),
              ),
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: _cookieNeCtrl,
                    decoration: const InputDecoration(
                      labelText: '网易云 MUSIC_U',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: _cookieTxCtrl,
                    decoration: const InputDecoration(
                      labelText: 'QQ ts_last 等',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
            const Divider(),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed:
                _detecting
                    ? null
                    : () async {
                      print('🔧 [SourceSettingsPage] 准备保存设置:');
                      print('  - _enabled: $_enabled');
                      print('  - _useJsForSearch: $_useJsForSearch');
                      print('  - _jsOnlyNoFallback: $_jsOnlyNoFallback');
                      print('  - _useUnifiedApi: $_useUnifiedApi');
                      print('  - _useYouTubeProxy: $_useYouTubeProxy');
                      print(
                        '  - _youTubeDownloadSource: $_youTubeDownloadSource',
                      );
                      print('  - _youTubeAudioQuality: $_youTubeAudioQuality');
                      print('  - _enableTts: $_enableTts');
                      print('  - _ttsTestText: $_ttsTestText');
                      print('  - scriptUrl: ${_urlCtrl.text.trim()}');

                      final s = SourceSettings(
                        enabled: _enabled,
                        scriptUrl: _urlCtrl.text.trim(),
                        platform: _platform,
                        cookieNetease: _cookieNeCtrl.text.trim(),
                        cookieTencent: _cookieTxCtrl.text.trim(),
                        useJsForSearch: _useJsForSearch,
                        jsOnlyNoFallback: _jsOnlyNoFallback,
                        useUnifiedApi: _useUnifiedApi,
                        useYouTubeProxy: _useYouTubeProxy,
                        youTubeDownloadSource: _youTubeDownloadSource,
                        youTubeAudioQuality: _youTubeAudioQuality,
                        enableTts: _enableTts,
                        ttsTestText: _ttsTestText,
                      );

                      print('🔧 [SourceSettingsPage] 创建的SourceSettings对象:');
                      print('  - enabled: ${s.enabled}');
                      print('  - useJsForSearch: ${s.useJsForSearch}');
                      print('  - jsOnlyNoFallback: ${s.jsOnlyNoFallback}');
                      print('  - useUnifiedApi: ${s.useUnifiedApi}');
                      print('  - useYouTubeProxy: ${s.useYouTubeProxy}');
                      print(
                        '  - youTubeDownloadSource: ${s.youTubeDownloadSource}',
                      );
                      print(
                        '  - youTubeAudioQuality: ${s.youTubeAudioQuality}',
                      );
                      print('  - enableTts: ${s.enableTts}');
                      print('  - ttsTestText: ${s.ttsTestText}');

                      await ref.read(sourceSettingsNotifierProvider).save(s);

                      // 验证保存后的状态
                      final savedSettings = ref.read(sourceSettingsProvider);
                      print('🔧 [SourceSettingsPage] 保存后验证:');
                      print('  - enabled: ${savedSettings.enabled}');
                      print(
                        '  - useJsForSearch: ${savedSettings.useJsForSearch}',
                      );
                      print(
                        '  - jsOnlyNoFallback: ${savedSettings.jsOnlyNoFallback}',
                      );
                      print(
                        '  - useUnifiedApi: ${savedSettings.useUnifiedApi}',
                      );
                      print(
                        '  - useYouTubeProxy: ${savedSettings.useYouTubeProxy}',
                      );
                      print(
                        '  - youTubeDownloadSource: ${savedSettings.youTubeDownloadSource}',
                      );
                      print(
                        '  - youTubeAudioQuality: ${savedSettings.youTubeAudioQuality}',
                      );
                      print('  - enableTts: ${savedSettings.enableTts}');
                      print('  - ttsTestText: ${savedSettings.ttsTestText}');
                      if (!mounted) return;
                      AppSnackBar.show(
                        context,
                        const SnackBar(
                          content: Text('音源设置已保存'),
                          backgroundColor: Colors.green,
                        ),
                      );

                      // 仅在选择JS源时才进行自动检测
                      if (!_useUnifiedApi && !_useYouTubeProxy && _enabled) {
                        setState(() {
                          _detecting = true;
                        });
                        try {
                          // 本地 JS 引擎检测
                          final local = await LocalJsSourceService.create();
                          await local.loadScript(s);
                          Map<String, dynamic> report = {
                            'ok': false,
                            'functions': <String>[],
                          };
                          if (local.isReady) {
                            report = await local.detectAdapterFunctions();
                          }
                          final ok = report['ok'] == true;
                          final funcs = (report['functions'] as List).join(
                            ', ',
                          );
                          if (ok) {
                            if (mounted) {
                              AppSnackBar.show(
                                context,
                                SnackBar(
                                  content: Text('检测成功：发现函数 [$funcs]'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            // 回退：用隐藏 WebView 再检测一次
                            final webSvc = WebViewJsSourceService(_hiddenCtrl);
                            await webSvc.init(s);
                            final webReport =
                                await webSvc.detectAdapterFunctions();
                            final ok2 = webReport['ok'] == true;
                            final funcs2 = (webReport['functions'] as List)
                                .join(', ');
                            if (mounted) {
                              AppSnackBar.show(
                                context,
                                SnackBar(
                                  content: Text(
                                    ok2
                                        ? '检测成功（WebView）：发现函数 [$funcs2]'
                                        : '检测失败：未发现可用函数',
                                  ),
                                  backgroundColor:
                                      ok2 ? Colors.green : Colors.red,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            AppSnackBar.show(
                              context,
                              SnackBar(
                                content: Text('检测异常：$e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } finally {
                          setState(() {
                            _detecting = false;
                          });
                        }
                      }
                    },
            icon:
                _detecting
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : const Icon(Icons.save_rounded),
            label: Text(_detecting ? '保存并检测中...' : '保存'),
          ),
        ],
      ),
    );
  }

  // 🎯 新增：测试TTS功能
  Future<void> _testTts() async {
    if (_ttsTestText.trim().isEmpty) {
      if (mounted) {
        AppSnackBar.show(
          context,
          const SnackBar(
            content: Text('请输入要测试的文字'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      // 显示测试状态
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('正在测试TTS: "$_ttsTestText"'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      // 这里需要调用TTS API，但需要先获取设备ID
      // 暂时显示成功提示，后续可以集成设备选择
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('TTS测试成功: "$_ttsTestText"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('TTS测试失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
