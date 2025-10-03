# JS 音源修复 - 快速测试指南

## 🚀 快速测试步骤

### 1. 重启 APP

```bash
flutter run
```

### 2. 加载 JS 脚本

1. 打开 APP
2. 进入 **设置** → **JS 音源设置**
3. 如果已有脚本，点击 **重新加载**
4. 如果没有脚本，导入 LX Music 脚本

### 3. 查看日志 - 关键指标

在终端日志中，**必须**看到以下内容：

✅ **成功标志**（按顺序）：

```
[UnifiedJS] 🔄 重置 module.exports
[UnifiedJS] 🔄 执行脚本...
[UnifiedJS] ✅ 脚本执行完成
[UnifiedJS] 🎬 触发脚本初始化事件...
[LX] 注册事件监听器: inited            ← 关键！脚本注册了监听器
[UnifiedJS] 触发 lx.emit("inited")      ← 关键！触发了事件
[LX] 触发事件: inited                   ← 关键！事件被触发
[UnifiedJS] ⏳ 等待脚本异步初始化...
[UnifiedJS] ✅ 脚本验证成功 (300ms)     ← 关键！验证成功
[UnifiedJS] module.exports的键: search, getUrl, ...  ← 关键！有导出
[UnifiedJS] ✅ 脚本加载和验证成功
```

❌ **失败标志**（需要修复）：

```
[UnifiedJS] module.exports的键: (无键)   ← 错误！没有导出
[UnifiedJS] 🔍 脚本验证结果: no_functions ← 错误！没有找到函数
```

### 4. 测试搜索功能

1. 返回主界面
2. 点击**搜索**标签
3. 输入 "林俊杰" 或其他歌手名
4. 点击搜索

✅ **成功标志**：
- 看到搜索结果列表
- 点击歌曲可以播放
- 日志中看到 `[XMC] ✅ searchOnline: 成功，结果=XX条`

❌ **失败标志**：
- 提示 "JS 音源未加载"
- 没有搜索结果
- 日志中看到 `[XMC] ❌ JS流程搜索失败`

## 📊 对比：修复前 vs 修复后

### 修复前 ❌

```
[UnifiedJS] ✅ 脚本执行完成
[UnifiedJS] ⏳ 等待脚本异步初始化...
[UnifiedJS] module.exports的键: (无键)        ← 问题！
[UnifiedJS] 🔍 脚本验证结果: no_functions    ← 问题！
[XMC] ⚠️ JS脚本未加载，尝试自动加载...       ← 问题！
```

### 修复后 ✅

```
[UnifiedJS] ✅ 脚本执行完成
[UnifiedJS] 🎬 触发脚本初始化事件...         ← 新增！
[LX] 注册事件监听器: inited                  ← 新增！
[UnifiedJS] 触发 lx.emit("inited")           ← 新增！
[LX] 触发事件: inited                        ← 新增！
[UnifiedJS] ⏳ 等待脚本异步初始化...
[UnifiedJS] ✅ 脚本验证成功 (300ms)          ← 成功！
[UnifiedJS] module.exports的键: search, getUrl, ... ← 成功！
```

## 🔍 故障排查

### 问题 1: 仍然提示 "JS 音源未加载"

**检查点**：
1. ✅ 代码是否已更新？
   ```bash
   git status
   # 应该看到 unified_js_runtime_service.dart 已修改
   ```

2. ✅ APP 是否已重启？
   ```bash
   # 停止 APP
   # 重新运行
   flutter run
   ```

3. ✅ 脚本是否重新加载？
   - 进入设置 → JS 音源设置
   - 点击"重新加载"按钮

### 问题 2: 日志中没有 "[LX] 注册事件监听器"

**可能原因**：
- 脚本不是 LX Music 格式
- 脚本内容损坏

**解决方法**：
- 重新下载 LX Music 脚本
- 确保脚本版本是 V3.0

### 问题 3: 日志中有 "[LX] 注册事件监听器" 但没有 "[LX] 触发事件"

**可能原因**：
- `_triggerScriptInitialization()` 未执行

**解决方法**：
- 检查代码是否正确添加了触发逻辑
- 重新编译 APP

### 问题 4: 验证等待超时（800ms 后仍然失败）

**可能原因**：
- 脚本执行出错
- 脚本需要网络请求

**解决方法**：
- 查看完整日志，寻找错误信息
- 确保网络连接正常

## 📝 日志关键词快速搜索

在终端中使用以下命令过滤关键日志：

```bash
# 查看 JS 加载相关日志
flutter run 2>&1 | grep -E "UnifiedJS|LX\]"

# 查看搜索相关日志
flutter run 2>&1 | grep -E "XMC.*[Ss]earch"

# 查看 module.exports 相关日志
flutter run 2>&1 | grep -E "module\.exports"
```

## ✅ 成功指标总结

全部满足才算成功：

1. ✅ 日志中有 "[LX] 注册事件监听器: inited"
2. ✅ 日志中有 "[UnifiedJS] 触发 lx.emit('inited')"
3. ✅ 日志中有 "[LX] 触发事件: inited"
4. ✅ 日志中有 "脚本验证成功"
5. ✅ 日志中有 "module.exports的键: search, getUrl, ..."
6. ✅ 搜索功能正常，能返回结果
7. ✅ 可以正常播放音乐

## 📚 更多信息

- 详细修复说明：`JS_SOURCE_FIX.md`
- 完整总结：`JS_LOAD_FIX_SUMMARY.md`
- 使用指南：`READY_TO_USE.md`

---

**预期测试时间**：3-5 分钟
