# JS 音源加载修复说明

## 问题描述

用户在启动 APP 搜索音乐时遇到以下问题：
- 提示 "JS 音源未加载"
- 日志显示脚本已执行，但 `module.exports` 是空对象
- 验证结果显示：`module.exports的键: (无键)`，`脚本验证结果: no_functions`

## 根本原因

1. **缺少 module.exports 重置**
   - 在加载新脚本时，没有重置 `module.exports`
   - 如果之前加载过脚本，可能保留旧状态
   - 导致新脚本无法正确设置导出对象

2. **未触发 LX Music 初始化事件** ⭐ 核心问题
   - LX Music 脚本使用**事件驱动**模式
   - 脚本通过 `lx.on('inited', handler)` 监听初始化事件
   - 只有收到 `inited` 事件后，才会设置 `module.exports`
   - 之前没有触发这个事件，导致脚本永远不会导出函数

3. **LX 环境不完整**
   - 原来的 `lx` 对象缺少完整的事件系统
   - `emit` 方法不支持多个事件处理器
   - 缺少 `registerScript`、`_dispatchEventToScript` 等关键函数

4. **异步等待时间不足**
   - 某些 JS 脚本使用 `setTimeout` 等异步方式设置导出
   - 延迟触发的 `inited` 事件在 200ms 后发生
   - 原来只等待 100ms 不够
   - 没有动态检测机制，浪费时间或等待不足

## 解决方案

### 1. 添加 module.exports 重置逻辑

在每次加载脚本前，先重置导出对象：

```dart
// ✨ 重置 module.exports（确保每次加载脚本都有干净的导出对象）
print('[UnifiedJS] 🔄 重置 module.exports');
_runtime!.evaluate(r'''
  (function() {
    var g = (typeof globalThis !== 'undefined') ? globalThis : (typeof window !== 'undefined' ? window : this);
    if (typeof g.module !== 'undefined' && g.module) {
      g.module.exports = {};
      g.exports = g.module.exports;
    }
  })()
''');
```

**作用**：
- 确保每次加载脚本都从干净状态开始
- 保证 `module.exports` 和 `exports` 正确关联
- 避免旧脚本状态干扰新脚本

### 2. 完善 LX Music 环境 ⭐ 关键修复

增强 `lx` 对象，添加完整的事件系统：

```javascript
// 完整的 LX Music 环境
g.lx = {
  EVENT_NAMES: { ... },
  
  // 支持多个事件处理器的 on 方法
  on: function(name, handler) {
    if (!g._lxHandlers[name]) {
      g._lxHandlers[name] = [];
    }
    g._lxHandlers[name].push(handler);
  },
  
  // 完整的 emit 方法
  emit: function(name, payload) {
    var handlers = g._lxHandlers[name];
    if (Array.isArray(handlers)) {
      for (var i = 0; i < handlers.length; i++) {
        handlers[i](payload);
      }
    }
  },
  
  // send 是 emit 的别名
  send: function(name, payload) {
    return this.emit(name, payload);
  },
  
  // ... 其他方法
};

// 脚本注册函数
g.registerScript = function(scriptInfo) { ... };

// 事件分发器
g._dispatchEventToScript = function(eventName, data) { ... };
```

### 3. 触发脚本初始化事件 ⭐ 核心步骤

在脚本执行后，主动触发 `inited` 事件：

```dart
void _triggerScriptInitialization() {
  // 1. 立即触发 inited 事件
  _runtime!.evaluate(r'''
    if (g.lx && g.lx.emit) {
      g.lx.emit('inited', { status: true, delayed: false });
    }
  ''');
  
  // 2. 尝试调用入口函数
  _runtime!.evaluate(r'''
    var candidates = ['main', 'init', 'initialize', ...];
    for (var i = 0; i < candidates.length; i++) {
      if (typeof g[candidates[i]] === 'function') {
        g[candidates[i]]();
      }
    }
  ''');
  
  // 3. 延迟 200ms 再次触发（给脚本更多时间）
  _runtime!.evaluate(r'''
    setTimeout(function() {
      if (g.lx && g.lx.emit) {
        g.lx.emit('inited', { status: true, delayed: true });
      }
    }, 200);
  ''');
}
```

**LX Music 脚本的典型模式**：
```javascript
// LX Music 脚本内部的代码
lx.on('inited', function(data) {
  console.log('收到初始化事件');
  
  // 在这里设置 module.exports
  module.exports = {
    search: function(keyword) { ... },
    getUrl: function(songInfo) { ... }
  };
});
```

### 4. 改进异步等待和验证机制

从固定等待改为动态轮询，并增加等待时间：

```dart
// 最多等待 800ms（8次 × 100ms）
// 延迟触发的 inited 事件在 200ms 后，所以需要足够的时间
bool isValid = false;
for (int i = 0; i < 8; i++) {
  await Future.delayed(const Duration(milliseconds: 100));
  isValid = await _validateScript();
  
  if (isValid) {
    print('[UnifiedJS] ✅ 脚本验证成功 (${(i + 1) * 100}ms)');
    break;
  }
  
  if (i < 7) {
    print('[UnifiedJS] ⏳ 等待中... (${(i + 1) * 100}ms)');
  }
}
```

**优势**：
- 最多等待 800ms（适应延迟 200ms 的 inited 事件）
- 一旦检测到有效导出就立即返回
- 同步导出的脚本可以快速完成（100ms）
- 异步导出的脚本有足够时间（200-800ms）
- 实时反馈等待状态，便于调试

## 效果预期

修复后，用户应该能看到以下改进：

1. **脚本加载更可靠**
   - `module.exports` 正确重置
   - LX 环境完整且功能齐全
   - `inited` 事件正确触发
   - 脚本导出的函数能被正确识别
   - 验证成功率大幅提高

2. **更好的日志输出**
   ```
   [UnifiedJS] 🔄 重置 module.exports
   [UnifiedJS] 🍪 注入Cookie变量
   [UnifiedJS] 🔄 执行脚本...
   [UnifiedJS] 📝 脚本前100字符: /*!...
   [UnifiedJS] ✅ 脚本执行完成
   [UnifiedJS] 🎬 触发脚本初始化事件...
   [LX] 注册事件监听器: inited                     ← 脚本注册监听器
   [UnifiedJS] 触发 lx.emit("inited")               ← 立即触发
   [LX] 触发事件: inited {status: true, ...}       ← 事件被触发
   [LX] 收到初始化事件                              ← 脚本接收事件
   [UnifiedJS] 延迟触发 lx.emit("inited")           ← 200ms后再触发
   [UnifiedJS] ✅ 脚本初始化事件已触发
   [UnifiedJS] ⏳ 等待脚本异步初始化...
   [UnifiedJS] ✅ 脚本验证成功 (300ms)              ← 验证成功！
   [UnifiedJS] module.exports的键: search, getUrl, ... ← 有导出！
   [UnifiedJS] ✅ 脚本加载和验证成功
   ```

3. **搜索功能恢复正常**
   - JS 音源可以正常使用
   - 不再提示 "JS 音源未加载"
   - 搜索结果正常返回
   - 播放 URL 正常解析

## 测试建议

1. **清除缓存后重新加载脚本**
   - 在设置中清除 JS 缓存
   - 重新导入 LX Music 脚本
   - 尝试搜索音乐

2. **查看日志输出**
   - 确认看到 "重置 module.exports" 日志
   - 确认看到 "触发脚本初始化事件" 日志
   - 确认看到 "[LX] 注册事件监听器: inited" 日志
   - 确认看到 "[LX] 触发事件: inited" 日志
   - 确认看到 "脚本验证成功" 日志
   - 确认 `module.exports的键` 不再是空

3. **测试不同脚本**
   - LX Music 脚本（事件驱动，需要 200-400ms）
   - 同步导出的脚本（应该 100ms 就成功）
   - 异步导出的脚本（可能需要 200-800ms）

## 技术细节

### LX Music 事件驱动模式

LX Music 脚本使用事件驱动的初始化模式：

```javascript
// 脚本执行时，先注册事件监听器
lx.on('inited', function(data) {
  console.log('收到初始化事件，开始设置导出');
  
  // 只有在收到 inited 事件后，才设置 module.exports
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

**关键点**：
1. 脚本加载时只注册监听器，不立即导出
2. 必须触发 `lx.emit('inited')` 事件
3. 脚本收到事件后才设置 `module.exports`
4. 可能有异步延迟（setTimeout）

### CommonJS 模块系统

标准的 CommonJS 模块系统中：
- `exports` 和 `module.exports` 初始时指向同一个对象
- 脚本可以通过 `module.exports = {...}` 重新赋值
- 或通过 `exports.xxx = ...` 添加属性
- 重置时需要确保两者的引用关系正确

### 异步导出模式

某些 JS 脚本可能这样写：
```javascript
// 方式1：setTimeout 延迟
setTimeout(() => {
  module.exports = {
    search: function() { ... },
    getUrl: function() { ... }
  };
}, 50);

// 方式2：事件驱动（LX Music）
lx.on('inited', (data) => {
  setTimeout(() => {
    module.exports = { ... };
  }, 100);
});
```

这就是为什么需要：
1. 触发初始化事件
2. 异步等待和轮询验证
3. 足够长的超时时间（800ms）

## 相关文件

- `lib/data/services/unified_js_runtime_service.dart` - JS 运行时服务
- `lib/presentation/providers/unified_js_provider.dart` - JS Provider
- `lib/presentation/providers/music_search_provider.dart` - 音乐搜索 Provider

## 版本

- 修复日期：2025-10-03
- 修复版本：V1.2.1+
