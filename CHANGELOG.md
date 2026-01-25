# Changelog

All notable changes to HMusic will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-01-25

### 🎊 HMusic 正式开源！

**这是一个里程碑版本！** HMusic 现已在 GitHub 上开源，欢迎 Star ⭐ 和贡献代码！

> 🔗 **GitHub**: https://github.com/hpcll/HMusic
>
> 📜 **许可证**: AGPL-3.0（开源免费，商业使用需授权）

---

### 🎉 重大更新：小米 IoT 直连模式

本次更新带来全新的**直连模式**，无需部署服务器，只需小米账号即可控制小爱音箱播放音乐！

### Added ✨

#### 📱 直连模式（核心新功能）
- **无服务器播放** - 无需部署 xiaomusic 服务端，开箱即用
- **小米账号登录** - 支持小米账号密码登录
- **WebView 验证码** - 自动处理小米安全验证，登录更顺畅
- **设备自动发现** - 自动获取账号下的小爱音箱设备
- **在线音乐播放** - 搜索并播放在线音乐到小爱音箱
- **播放状态同步** - 实时轮询设备播放状态
- **状态持久化** - 记住上次播放的歌曲和进度

#### 🎵 播放队列系统
- 新增播放队列管理
- 支持添加到队列、清空队列
- 队列状态持久化

#### 📋 本地歌单系统（直连模式）
- 创建和管理本地歌单
- 从搜索结果添加歌曲到歌单
- 歌单数据本地存储，无需服务器

#### 🔧 其他新功能
- 音频代理服务器（移动网络播放支持）
- Cloudflare Worker 代理部署方案
- 模式选择页面（xiaomusic/直连 一键切换）
- Tab 导航优化（添加歌曲后可直接跳转到歌单）

### Changed 🎨

- 重构播放控制架构，支持多种播放策略（策略模式）
- PlaybackProvider 大幅增强，支持模式切换
- 优化模式切换体验，配置自动保存
- 改进 UI 交互，减少页面跳转
- 清理遗留代码，优化音源设置页面
- 移除默认公共代理，用户自行部署更安全

### Fixed 🐛

- 修复模式切换后播放策略未重新初始化的问题
- 修复直连模式 duration 突变问题（暂停时返回异常值）
- 修复播放后 6 秒状态延迟问题（添加保护窗口）
- 修复验证码登录后自动重试失败的竞态条件
- 修复歌单列表被状态栏遮挡的问题
- 修复播放切歌时的竞态条件
- 修复播放控制按钮闪烁问题
- 修复直连模式歌单页面按钮显示逻辑

### Technical 📦

- 新增 `MiIoTService` 小米 IoT API 服务
- 新增 `MiIoTDirectPlaybackStrategy` 直连播放策略
- 新增 `DirectModeProvider` 直连模式状态管理
- 新增 `LocalPlaylistProvider` 本地歌单管理
- 新增 `PlaybackQueueProvider` 播放队列管理
- 新增 `AudioProxyServer` 音频代理服务
- 新增 `NavigationProvider` Tab 导航管理
- 新增 `NetworkDetector` 网络环境检测
- 架构文档完善（ARCHITECTURE.md, INTEGRATION_GUIDE.md, CLAUDE.md）

### 📜 开源信息

| 项目 | 说明 |
|------|------|
| **仓库地址** | https://github.com/hpcll/HMusic |
| **许可证** | AGPL-3.0 |
| **开源日期** | 2026-01-25 |
| **商业授权** | 联系作者 |

欢迎提交 Issue 和 Pull Request！

---

## [2.1.2] - 2025-01-14

### Added ✨

#### 赞赏引导系统
- 使用统计追踪系统（播放次数、歌词刮削、使用天数）
- 里程碑提示功能：
  - 播放 50 首歌曲祝贺
  - 刮削 20 条歌词感谢
  - 使用 7 天陪伴提醒
  - 30 天间隔温馨提示
- 精美的赞赏提示弹窗，支持"不再提醒"选项
- 首页新增粉色爱心赞赏按钮
- 赞赏按钮心跳动画（仅播放 3 次）

#### 智能歌词匹配
- 支持"歌名 - 歌手"和"歌手 - 歌名"两种命名格式
- 智能格式反转：首次搜索无结果时自动尝试反转格式
- 多层级匹配策略：完美匹配 > 艺术家匹配 > 备选
- 增强艺术家名称匹配精度

#### 播放列表功能
- 虚拟播放列表识别机制（下载/全部/所有歌曲等）
- 播放列表移动操作增加删除结果检查和自动回滚
- 曲库页面新增"所属播放列表"显示
- 曲库页面歌曲菜单新增"添加到..."功能

### Changed 🎨

- 统一曲库页面、播放列表主页、播放列表详情页的列表项背景色
- 移除 Card 组件阴影，使用统一的浅灰色背景+边框样式
- 统一成功提示 Toast 背景色为绿色
- 统一赞赏支持页面的 AppBar 样式
- 虚拟播放列表只显示"添加到..."操作，隐藏"移动到..."操作
- 播放列表选择器自动过滤虚拟列表

### Fixed 🐛

- 修复播放列表移动操作未检查删除结果的问题
- 修复 PlaylistAdapter 未包含歌曲列表数据的问题
- 修复歌词匹配逻辑对特殊命名格式的支持
- 修复 Android 通知配置，改善后台播放体验

### Technical 📦

- 新增 `UsageStatsProvider` 使用统计追踪系统
- 新增 `SponsorPromptDialog` 精美提示弹窗组件
- 优化 `LyricService` 歌词匹配算法
- 改进 `PlaylistProvider` 播放列表管理逻辑
- 使用 SharedPreferences 持久化统计数据
- Riverpod 状态管理优化
- 添加详细的调试日志

---

## [2.1.1] - Previous Release

*Previous changelog entries...*

---

## How to Update

1. **From GitHub**: Download the latest APK from [Releases](https://github.com/hpcll/HMusic/releases)
2. **In-App**: Check for updates in Settings

## Support

- 💗 Star us on [GitHub](https://github.com/hpcll/HMusic)
- 🐛 Report issues on [GitHub Issues](https://github.com/hpcll/HMusic/issues)
- 💬 Join our community discussions
