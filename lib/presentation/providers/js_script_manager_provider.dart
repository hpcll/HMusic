import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../data/models/js_script.dart';
import 'js_proxy_provider.dart';

class JsScriptManager extends StateNotifier<List<JsScript>> {
  static const _kScriptList = 'js_script_list';
  static const _kSelectedScriptId = 'selected_script_id';

  String? _selectedScriptId;
  String? get selectedScriptId => _selectedScriptId;
  JsScript? get selectedScript =>
      state.isNotEmpty && _selectedScriptId != null
          ? state.firstWhere(
            (s) => s.id == _selectedScriptId,
            orElse: () => state.first,
          )
          : null;

  JsScriptManager() : super([]) {
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scriptsJson = prefs.getString(_kScriptList);
      final selectedId = prefs.getString(_kSelectedScriptId);

      List<JsScript> scripts = [];

      // 公开版本不包含内置脚本，用户需要自行导入JS脚本

      // 加载用户导入的脚本
      if (scriptsJson != null && scriptsJson.isNotEmpty) {
        final List<dynamic> scriptsList = jsonDecode(scriptsJson);
        for (final scriptMap in scriptsList) {
          try {
            scripts.add(JsScript.fromMap(scriptMap as Map<String, dynamic>));
          } catch (e) {
            print('[XMC] ⚠️ [JsScriptManager] 跳过无效脚本: $e');
          }
        }
      }

      state = scripts;

      // 公开版本：清理遗留的内置脚本选择
      if (selectedId == 'builtin_xiaoqiu') {
        print('[XMC] 🧹 [JsScriptManager] 检测到遗留的内置脚本选择，自动清理');
        _selectedScriptId = scripts.isNotEmpty ? scripts.first.id : null;
        await _saveScripts(); // 保存清理后的状态
      } else {
        _selectedScriptId =
            selectedId ?? (scripts.isNotEmpty ? scripts.first.id : null);
      }

      print(
        '[XMC] 📚 [JsScriptManager] 加载了 ${scripts.length} 个脚本，当前选中: $_selectedScriptId',
      );
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 加载脚本失败: $e');
      state = [];
    }
  }

  Future<void> _saveScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 只保存非内置脚本
      final userScripts = state.where((s) => !s.isBuiltIn).toList();
      final scriptsJson = jsonEncode(
        userScripts.map((s) => s.toMap()).toList(),
      );

      await prefs.setString(_kScriptList, scriptsJson);
      if (_selectedScriptId != null) {
        await prefs.setString(_kSelectedScriptId, _selectedScriptId!);
      }

      print('[XMC] 💾 [JsScriptManager] 已保存 ${userScripts.length} 个用户脚本');
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 保存脚本失败: $e');
    }
  }

  // 从本地文件导入脚本
  Future<bool> importFromLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js'],
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) {
        return false;
      }

      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      // 读取文件内容以验证
      final file = File(filePath);
      final content = await file.readAsString();

      if (content.trim().isEmpty) {
        print('[XMC] ❌ [JsScriptManager] 脚本文件为空');
        return false;
      }

      // 生成脚本名称（去掉.js后缀）
      final scriptName =
          fileName.endsWith('.js')
              ? fileName.substring(0, fileName.length - 3)
              : fileName;

      final script = JsScript(
        id: const Uuid().v4(),
        name: scriptName,
        description: '从本地文件导入: $fileName',
        source: JsScriptSource.localFile,
        content: filePath, // 存储文件路径
        addedTime: DateTime.now(),
      );

      // 检查是否已存在同名脚本
      final existingIndex = state.indexWhere(
        (s) => s.name == script.name && s.source == JsScriptSource.localFile,
      );

      if (existingIndex >= 0) {
        // 替换已存在的脚本
        final newState = [...state];
        newState[existingIndex] = script;
        state = newState;
        print('[XMC] 🔄 [JsScriptManager] 替换已存在的脚本: ${script.name}');
      } else {
        // 添加新脚本
        state = [...state, script];
        print('[XMC] ➕ [JsScriptManager] 添加新脚本: ${script.name}');
      }

      await _saveScripts();
      return true;
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 导入本地脚本失败: $e');
      return false;
    }
  }

  // 从在线地址导入脚本
  Future<bool> importFromUrl(String url, String name) async {
    try {
      if (url.trim().isEmpty || name.trim().isEmpty) {
        return false;
      }

      final script = JsScript(
        id: const Uuid().v4(),
        name: name.trim(),
        description: '从在线地址导入: $url',
        source: JsScriptSource.url,
        content: url.trim(),
        addedTime: DateTime.now(),
      );

      // 检查是否已存在同名脚本
      final existingIndex = state.indexWhere(
        (s) => s.name == script.name && s.source == JsScriptSource.url,
      );

      if (existingIndex >= 0) {
        // 替换已存在的脚本
        final newState = [...state];
        newState[existingIndex] = script;
        state = newState;
        print('[XMC] 🔄 [JsScriptManager] 替换已存在的脚本: ${script.name}');
      } else {
        // 添加新脚本
        state = [...state, script];
        print('[XMC] ➕ [JsScriptManager] 添加新脚本: ${script.name}');
      }

      await _saveScripts();
      return true;
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 导入在线脚本失败: $e');
      return false;
    }
  }

  // 删除脚本（同时清除其缓存）
  Future<void> deleteScript(String scriptId, {WidgetRef? ref}) async {
    final script = state.firstWhere((s) => s.id == scriptId);
    if (script.isBuiltIn) {
      print('[XMC] ⚠️ [JsScriptManager] 无法删除内置脚本: ${script.name}');
      return;
    }

    state = state.where((s) => s.id != scriptId).toList();

    if (_selectedScriptId == scriptId && state.isNotEmpty) {
      _selectedScriptId = state.first.id;
    } else if (_selectedScriptId == scriptId && state.isEmpty) {
      _selectedScriptId = null;
    }

    await _saveScripts();
    print('[XMC] 🗑️ [JsScriptManager] 删除脚本: ${script.name}');

    try {
      final cacheKey = 'js_cached_content_${script.id ?? script.name}';
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.remove(cacheKey);
      print('[XMC] 🧹 [JsScriptManager] 已同步清除缓存: $ok');
    } catch (e) {
      print('[XMC] ⚠️ [JsScriptManager] 清除缓存失败: $e');
    }
  }

  // 选择脚本
  Future<void> selectScript(String scriptId) async {
    if (state.any((s) => s.id == scriptId)) {
      _selectedScriptId = scriptId;
      await _saveScripts();
      // 强制更新状态以通知监听者
      state = [...state];
      print('[XMC] 🎯 [JsScriptManager] 选择脚本: $scriptId');
    }
  }

  // 获取脚本的实际内容（对于本地文件，读取文件内容）
  Future<String?> getScriptContent(JsScript script) async {
    try {
      switch (script.source) {
        case JsScriptSource.builtin:
        case JsScriptSource.url:
          return script.content;
        case JsScriptSource.localFile:
          final file = File(script.content);
          if (await file.exists()) {
            return await file.readAsString();
          } else {
            print('[XMC] ❌ [JsScriptManager] 本地文件不存在: ${script.content}');
            return null;
          }
      }
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 读取脚本内容失败: $e');
      return null;
    }
  }
}

final jsScriptManagerProvider =
    StateNotifierProvider<JsScriptManager, List<JsScript>>((ref) {
      return JsScriptManager();
    });

// 获取当前选中的脚本
final selectedJsScriptProvider = Provider<JsScript?>((ref) {
  final scripts = ref.watch(jsScriptManagerProvider);
  final manager = ref.read(jsScriptManagerProvider.notifier);
  return manager.selectedScript;
});
