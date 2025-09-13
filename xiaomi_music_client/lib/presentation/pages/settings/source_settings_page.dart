import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/source_settings_provider.dart';
import '../../providers/js_script_manager_provider.dart';
import '../../providers/js_proxy_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../../data/models/js_script.dart';

class SourceSettingsPage extends ConsumerStatefulWidget {
  const SourceSettingsPage({super.key});

  @override
  ConsumerState<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends ConsumerState<SourceSettingsPage> {
  late TextEditingController _apiCtrl;
  String _platform = 'qq';
  bool _initialized = false;
  // _jsEnabled 已由 _primary 状态隐含控制，无需单独使用
  String _primary = 'unified'; // 'unified' | 'js_external'
  String _jsSearchStrategy =
      'qqFirst'; // qqFirst|kuwoFirst|neteaseFirst|qqOnly|kuwoOnly|neteaseOnly

  @override
  void initState() {
    super.initState();
    _apiCtrl = TextEditingController();

    // Riverpod 限制：listen 不能放在 initState，这里不监听
  }

  void _initializeFromProvider(SourceSettings s) {
    if (_initialized) return;
    _apiCtrl.text = s.unifiedApiBase;
    _platform = s.platform == 'auto' ? 'qq' : s.platform;
    _primary = s.primarySource;
    _jsSearchStrategy = s.jsSearchStrategy;
    _initialized = true;
  }

  @override
  void dispose() {
    _apiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(sourceSettingsProvider);
    final scripts = ref.watch(jsScriptManagerProvider);
    final scriptManager = ref.read(jsScriptManagerProvider.notifier);
    final selectedScript = scriptManager.selectedScript;

    // 只在首次初始化时同步provider状态到本地控件
    if (!_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeFromProvider(settings);
        setState(() {});
      });
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: const Text('音源设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 音源选择卡片
          _buildSourceTypeCard(context, onSurface),
          const SizedBox(height: 16),

          // 配置区域
          if (_primary == 'unified') ...[_buildUnifiedApiCard(context)],
          if (_primary == 'js_external') ...[
            _buildJsScriptCard(context, scripts, selectedScript, scriptManager),
          ],

          const SizedBox(height: 24),
          _buildSaveButton(context, settings, selectedScript),
        ],
      ),
    );
  }

  Widget _buildSourceTypeCard(BuildContext context, Color onSurface) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '音源类型',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '选择音乐搜索和播放的数据来源',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            // 统一API 选项
            _buildSourceOption(
              context,
              title: '统一 API',
              subtitle: '稳定快速的多平台接口',
              icon: Icons.cloud_outlined,
              value: 'unified',
              isSelected: _primary == 'unified',
              onTap: () => setState(() => _primary = 'unified'),
            ),
            const SizedBox(height: 12),
            // JS外置脚本 选项
            _buildSourceOption(
              context,
              title: 'JS 脚本',
              subtitle: '使用JS脚本获取音源',
              icon: Icons.code_outlined,
              value: 'js_external',
              isSelected: _primary == 'js_external',
              onTap: () => setState(() => _primary = 'js_external'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedApiCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '统一 API 配置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '优先平台',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _buildPlatformDropdown(context),
          ],
        ),
      ),
    );
  }

  Widget _buildJsScriptCard(
    BuildContext context,
    List<JsScript> scripts,
    JsScript? selectedScript,
    JsScriptManager scriptManager,
  ) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.code_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'JS 脚本配置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  tooltip: '导入脚本',
                  onSelected:
                      (value) => _handleScriptImport(value, scriptManager),
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'local_file',
                          child: Row(
                            children: [
                              Icon(Icons.file_open),
                              SizedBox(width: 8),
                              Text('本地文件'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'url',
                          child: Row(
                            children: [
                              Icon(Icons.link),
                              SizedBox(width: 8),
                              Text('在线地址'),
                            ],
                          ),
                        ),
                      ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (scripts.isEmpty) ...[
              Text(
                '暂无可用脚本，请导入脚本',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ] else ...[
              Text(
                '选择脚本 (当前: ${selectedScript?.name ?? "未选择"})',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ...scripts.map(
                (script) => _buildScriptTile(
                  context,
                  script,
                  selectedScript?.id == script.id,
                  scriptManager,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '搜索源优先级',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              _buildJsSearchStrategyDropdown(context),
              const SizedBox(height: 6),
              Text(
                '说明：仅在“JS 脚本”流程下用于搜索源选择；播放解析仍走JS解析。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScriptTile(
    BuildContext context,
    JsScript script,
    bool isSelected,
    JsScriptManager scriptManager,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 2 : 0,
      color:
          isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : Theme.of(context).colorScheme.surface,
      child: ListTile(
        leading: Icon(
          script.source == JsScriptSource.builtin
              ? Icons.integration_instructions
              : script.source == JsScriptSource.localFile
              ? Icons.file_present
              : Icons.link,
          color:
              isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          script.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          '${script.source.displayName} • ${script.description}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            if (!script.isBuiltIn) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed:
                    () => _confirmDeleteScript(context, script, scriptManager),
                tooltip: '删除脚本',
              ),
            ],
          ],
        ),
        onTap: () async {
          await scriptManager.selectScript(script.id);
          setState(() {}); // 触发UI更新
        },
      ),
    );
  }

  Widget _buildPlatformDropdown(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _platform,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'qq', child: Text('QQ音乐')),
            DropdownMenuItem(value: 'wangyi', child: Text('网易云音乐')),
            DropdownMenuItem(value: 'kugou', child: Text('酷狗音乐')),
            DropdownMenuItem(value: 'kuwo', child: Text('酷我音乐')),
            DropdownMenuItem(value: 'migu', child: Text('咪咕音乐')),
          ],
          onChanged: (v) => setState(() => _platform = v ?? 'qq'),
        ),
      ),
    );
  }

  Widget _buildJsSearchStrategyDropdown(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _jsSearchStrategy,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'qqFirst', child: Text('优先 QQ → 酷我/网易回退')),
            DropdownMenuItem(
              value: 'kuwoFirst',
              child: Text('优先 酷我 → QQ/网易回退'),
            ),
            DropdownMenuItem(
              value: 'neteaseFirst',
              child: Text('优先 网易 → QQ/酷我回退'),
            ),
            DropdownMenuItem(value: 'qqOnly', child: Text('仅 QQ')),
            DropdownMenuItem(value: 'kuwoOnly', child: Text('仅 酷我')),
            DropdownMenuItem(value: 'neteaseOnly', child: Text('仅 网易')),
          ],
          onChanged: (v) => setState(() => _jsSearchStrategy = v ?? 'qqFirst'),
        ),
      ),
    );
  }

  Widget _buildSaveButton(
    BuildContext context,
    SourceSettings settings,
    JsScript? selectedScript,
  ) {
    return FilledButton.icon(
      onPressed: () => _saveSettings(settings, selectedScript),
      icon: const Icon(Icons.save_rounded),
      label: const Text('保存'),
    );
  }

  Future<void> _handleScriptImport(
    String type,
    JsScriptManager scriptManager,
  ) async {
    bool success = false;

    if (type == 'local_file') {
      success = await scriptManager.importFromLocalFile();
    } else if (type == 'url') {
      success = await _showUrlImportDialog(scriptManager);
    }

    if (success && mounted) {
      AppSnackBar.show(
        context,
        const SnackBar(content: Text('脚本导入成功'), backgroundColor: Colors.green),
      );
    } else if (!success && mounted) {
      AppSnackBar.show(
        context,
        const SnackBar(content: Text('脚本导入失败'), backgroundColor: Colors.red),
      );
    }
  }

  Future<bool> _showUrlImportDialog(JsScriptManager scriptManager) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('导入在线脚本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '脚本名称',
                    hintText: '给脚本起个名字',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: '脚本地址',
                    hintText: 'https://example.com/script.js',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isNotEmpty &&
                      urlController.text.trim().isNotEmpty) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text('导入'),
              ),
            ],
          ),
    );

    if (result == true) {
      return await scriptManager.importFromUrl(
        urlController.text.trim(),
        nameController.text.trim(),
      );
    }

    return false;
  }

  Future<void> _confirmDeleteScript(
    BuildContext context,
    JsScript script,
    JsScriptManager scriptManager,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除脚本'),
            content: Text('确定要删除脚本 "${script.name}" 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await scriptManager.deleteScript(script.id);
    }
  }

  Future<void> _saveSettings(
    SourceSettings settings,
    JsScript? selectedScript,
  ) async {
    try {
      final newSettings = settings.copyWith(
        unifiedApiBase: settings.unifiedApiBase, // 固定使用默认值
        platform: _platform,
        enabled: _primary == 'js_external',
        primarySource: _primary,
        scriptUrl:
            selectedScript?.source == JsScriptSource.url
                ? selectedScript?.content ?? ''
                : (selectedScript?.source == JsScriptSource.builtin
                    ? selectedScript?.content ?? ''
                    : ''),
        scriptPreset: selectedScript?.id ?? 'builtin_xiaoqiu',
        localScriptPath:
            selectedScript?.source == JsScriptSource.localFile
                ? selectedScript?.content ?? ''
                : '',
        jsSearchStrategy: _jsSearchStrategy,
      );

      await ref.read(sourceSettingsNotifierProvider).save(newSettings);

      // 保存后尝试将所选脚本加载到 QuickJS 代理，确保播放解析使用所选脚本
      if (_primary == 'js_external' && selectedScript != null) {
        try {
          await ref
              .read(jsProxyProvider.notifier)
              .loadScriptByScript(selectedScript);
        } catch (_) {}
      }
      if (!mounted) return;

      AppSnackBar.show(
        context,
        const SnackBar(content: Text('音源设置已保存'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildSourceOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colorScheme.primaryContainer.withOpacity(0.3)
                  : Colors.transparent,
          border: Border.all(
            color:
                isSelected
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? colorScheme.primary.withOpacity(0.1)
                        : colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color:
                    isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
