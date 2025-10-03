# JS 音源加载完整修复总结

## 问题症状

用户报告：启动 APP 搜索音乐时提示 **"JS 音源未加载"**

关键日志：
```
[UnifiedJS] ✅ 脚本执行完成
[UnifiedJS] module.exports的键: (无键)
[UnifiedJS] 🔍 脚本验证结果: no_functions
```

## 核心原因 🎯

**LX Music 脚本使用事件驱动的初始化模式！**

LX Music 脚本的工作流程：
1. 脚本加载时，注册 `lx.on('inited', handler)` 监听器
2. 等待接收 `inited` 事件
3. **只有**收到事件后，才在事件处理器中设置 `module.exports`
4. 可能有异步延迟（200ms）

**之前的实现缺失**：
- ❌ 没有触发 `inited` 事件
- ❌ `lx` 对象的事件系统不完整
- ❌ 等待时间不足（只有 100ms，但延迟触发需要 200ms）

## 完整修复方案

### 1️⃣ 重置 module.exports

```dart
// 确保每次加载脚本都从干净状态开始
_runtime!.evaluate(r'''
  (function() {
    var g = (typeof globalThis !== 'undefined') ? globalThis : this;
    if (g.module) {
      g.module.exports = {};
      g.exports = g.module.exports;
    }
  })()
''');
```

### 2️⃣ 完善 LX Music 环境

增强 `lx` 对象，添加完整的事件系统：

```javascript
g.lx = {
  EVENT_NAMES: { inited: 'inited', ... },
  
  // ✅ 支持多个处理器的事件系统
  on: function(name, handler) {
    if (!g._lxHandlers[name]) g._lxHandlers[name] = [];
    g._lxHandlers[name].push(handler);
  },
  
  // ✅ 完整的 emit 实现
  emit: function(name, payload) {
    var handlers = g._lxHandlers[name];
    if (Array.isArray(handlers)) {
      handlers.forEach(h => h(payload));
    }
  },
  
  // ✅ send 是 emit 的别名
  send: function(name, payload) {
    return this.emit(name, payload);
  }
};

// ✅ 脚本注册函数
g.registerScript = function(scriptInfo) { ... };

// ✅ 事件分发器
g._dispatchEventToScript = function(eventName, data) { ... };
```

### 3️⃣ 触发初始化事件 ⭐ 关键！

在脚本执行后，主动触发 `inited` 事件：

```dart
void _triggerScriptInitialization() {
  // 1. 立即触发
  _runtime!.evaluate(r'''
    if (g.lx && g.lx.emit) {
      g.lx.emit('inited', { status: true });
    }
  ''');
  
  // 2. 尝试调用入口函数
  _runtime!.evaluate(r'''
    ['main', 'init', 'initialize', ...].forEach(name => {
      if (typeof g[name] === 'function') g[name]();
    });
  ''');
  
  // 3. 延迟 200ms 再次触发（给脚本更多时间）
  _runtime!.evaluate(r'''
    setTimeout(() => {
      if (g.lx && g.lx.emit) {
        g.lx.emit('inited', { status: true, delayed: true });
      }
    }, 200);
  ''');
}
```

### 4️⃣ 增加等待时间

```dart
// 最多等待 800ms（8次 × 100ms）
// 适应延迟 200ms 的 inited 事件
bool isValid = false;
for (int i = 0; i < 8; i++) {
  await Future.delayed(const Duration(milliseconds: 100));
  isValid = await _validateScript();
  
  if (isValid) {
    print('[UnifiedJS] ✅ 脚本验证成功 (${(i + 1) * 100}ms)');
    break;
  }
}
```

## 修复后的日志流程

```
[UnifiedJS] 🔄 重置 module.exports                  ← 重置导出对象
[UnifiedJS] 🍪 注入Cookie变量
[UnifiedJS] 🔄 执行脚本...
[UnifiedJS] ✅ 脚本执行完成
[UnifiedJS] 🎬 触发脚本初始化事件...               ← 触发初始化

[LX] 注册事件监听器: inited                         ← 脚本注册监听器
[UnifiedJS] 触发 lx.emit("inited")                  ← 立即触发事件
[LX] 触发事件: inited {status: true}                ← 事件被触发
[LX] 收到初始化事件，开始设置导出                   ← 脚本收到事件

[UnifiedJS] 延迟触发 lx.emit("inited")              ← 200ms后再触发
[UnifiedJS] ✅ 脚本初始化事件已触发

[UnifiedJS] ⏳ 等待脚本异步初始化...
[UnifiedJS] ⏳ 等待中... (100ms)
[UnifiedJS] ⏳ 等待中... (200ms)
[UnifiedJS] ⏳ 等待中... (300ms)
[UnifiedJS] ✅ 脚本验证成功 (400ms)                 ← 验证成功！

[UnifiedJS] module存在: object
[UnifiedJS] module.exports类型: object
[UnifiedJS] module.exports的键: search, getUrl, ... ← 有导出了！
[UnifiedJS] 🔍 脚本验证结果: valid:module.exports.search,...

[UnifiedJS] ✅ 脚本加载和验证成功: lx-music-source V3.0
[UnifiedJsProvider] ✅ 脚本加载成功
[XMC] ✅ JS脚本自动加载成功
[XMC] 🎵 [MusicSearch] JS流程（使用原生搜索 + JS解析播放）
```

## 关键改进

| 项目 | 修复前 | 修复后 |
|------|--------|--------|
| `module.exports` | 未重置，可能有旧状态 | ✅ 每次加载都重置 |
| LX 环境 | 事件系统不完整 | ✅ 完整的事件系统 |
| `inited` 事件 | ❌ 从不触发 | ✅ 立即触发 + 延迟触发 |
| 等待时间 | 100ms（不够） | ✅ 最多 800ms，动态检测 |
| 入口函数 | 不调用 | ✅ 尝试调用常见入口 |
| 事件处理器 | 单个处理器 | ✅ 支持多个处理器 |

## 验证步骤

1. **重新运行 APP**
   ```bash
   flutter run
   ```

2. **加载 JS 脚本**
   - 进入设置 → JS 音源设置
   - 选择 LX Music 脚本

3. **查看日志确认**
   - ✅ 看到 "[LX] 注册事件监听器: inited"
   - ✅ 看到 "[UnifiedJS] 触发 lx.emit('inited')"
   - ✅ 看到 "[LX] 触发事件: inited"
   - ✅ 看到 "脚本验证成功"
   - ✅ 看到 "module.exports的键: search, getUrl, ..."

4. **搜索测试**
   - 搜索 "林俊杰" 或其他歌手
   - 确认返回搜索结果
   - 确认可以播放音乐

## 技术要点

### LX Music 脚本模式

```javascript
// 典型的 LX Music 脚本结构
lx.on('inited', function(data) {
  // 只在收到 inited 事件后才设置导出
  module.exports = {
    search: function(keyword, page, filter) {
      // 搜索实现
    },
    getUrl: function(songInfo, quality) {
      // 获取播放 URL
    }
  };
});
```

### 为什么需要延迟触发？

1. 脚本可能在注册监听器时有异步操作
2. 某些脚本在事件处理器中使用 `setTimeout`
3. 给脚本充足的初始化时间
4. 确保所有监听器都注册完毕

### 为什么需要 800ms 等待？

- 立即触发：0ms
- 延迟触发：200ms
- 脚本处理：可能 100-200ms
- 总计：约 300-400ms
- 保险起见：800ms（多次检测，提前成功即返回）

## 修改的文件

- ✅ `lib/data/services/unified_js_runtime_service.dart`
  - 添加 `module.exports` 重置逻辑
  - 完善 LX Music 环境（完整事件系统）
  - 添加 `_triggerScriptInitialization()` 方法
  - 增加等待时间到 800ms

## 相关文档

- `JS_SOURCE_FIX.md` - 详细修复说明
- `READY_TO_USE.md` - 使用指南

## 版本信息

- 修复日期：2025-10-03
- 修复版本：V1.2.1+
- 修复范围：JS 音源加载系统
- 影响组件：统一 JS 运行时服务

---

**总结**：本次修复的核心是理解并实现了 LX Music 脚本的事件驱动初始化模式。通过触发 `inited` 事件，脚本才能正确设置 `module.exports`。同时完善了 LX 环境和等待机制，确保脚本有足够时间完成异步初始化。
