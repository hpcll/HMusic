# HMusic - 智能音乐播放器 🎵

> 从 NAS 音乐控制器进化为全能音乐播放器

基于 Flutter 开发的跨平台音乐播放器，支持本地播放和远程控制，提供完整的音乐管理功能。

[![Release](https://img.shields.io/github/v/release/hpcll/XiaoMi_Music_Client?label=版本)](https://github.com/hpcll/XiaoMi_Music_Client/releases)
[![License](https://img.shields.io/github/license/hpcll/XiaoMi_Music_Client)](LICENSE)

## ✨ 核心功能

### 🎵 本地播放模式
- 手机本地音乐播放，智能模式切换
- 本地音乐自动扫描和管理
- 播放状态完整保持和恢复
- 流畅的播放体验，无卡顿

### 🌐 远程控制模式
- 远程音乐播放控制
- 多设备管理和切换
- 实时状态同步
- 设备在线监控

### 📱 完整功能
- ✅ **播放控制** - 播放/暂停、上一曲/下一曲、播放模式切换
- ✅ **音乐封面** - 智能封面搜索，主色调自适应光圈
- ✅ **播放列表** - 创建、管理、播放自定义列表
- ✅ **音乐下载** - 多音质选择（无损/高品质/标准）
- ✅ **音乐搜索** - 快速搜索并播放
- ✅ **音乐库管理** - 浏览、搜索、删除音乐文件
- ✅ **播放通知** - Android/iOS 通知栏控制
- ✅ **应用内更新** - 自动检测和更新提醒

## 🎨 界面预览

### 四个主要页面
1. **播放** - 封面、进度、控制、音量
2. **搜索** - 实时搜索、快速播放
3. **播放列表** - 列表管理、批量操作
4. **音乐库** - 本地音乐浏览管理

## 🚀 快速开始

### 下载安装

从 [Releases](https://github.com/hpcll/XiaoMi_Music_Client/releases) 下载最新版本：
- **Android**: HMusic-v2.0.0.apk
- **iOS**: 即将推出

### 首次使用

1. 打开应用进入登录页面
2. 输入服务器信息：
   - **服务器地址**: `你的服务器IP:端口`
   - **用户名**: API 认证用户名
   - **密码**: API 认证密码
3. 登录后自动保存配置

### 功能使用

**本地播放**
- 应用自动扫描手机音乐
- 点击歌曲即可播放
- 支持播放列表管理

**远程控制**
- 选择远程设备
- 控制音乐播放
- 实时查看播放状态

## 💻 技术栈

- **框架**: Flutter 3.7+
- **状态管理**: Riverpod
- **网络**: Dio + HTTP Basic Auth
- **UI**: Material Design 3
- **播放**: audio_service + just_audio
- **缓存**: cached_network_image
- **架构**: Clean Architecture

## 📦 从源码构建

### 前置要求
- Flutter SDK 3.7+
- Dart SDK 3.0+
- Android Studio / Xcode

### 安装依赖
```bash
flutter pub get
```

### 运行应用
```bash
# Android
flutter run

# iOS
flutter run -d ios

# macOS
flutter run -d macos

# Web
flutter run -d chrome
```

### 构建 APK
```bash
flutter build apk --release
```

## 📂 项目结构

```
lib/
├── core/                 # 核心功能
│   ├── constants/        # 常量定义
│   ├── network/         # 网络层
│   └── utils/           # 工具类
├── data/                # 数据层
│   ├── models/          # 数据模型
│   └── services/        # API服务
├── domain/              # 业务逻辑层
│   └── repositories/    # 仓库接口
└── presentation/        # 表现层
    ├── pages/           # 页面
    ├── providers/       # 状态管理
    └── widgets/         # UI组件
```

## 🔧 配置说明

### 服务器要求
- 支持小爱音乐 API
- 开启 HTTP Basic Auth
- 网络可访问

### API 接口
详见 API 文档或查看代码中的 `services/` 目录

## 🐛 故障排除

**无法连接服务器**
- 检查服务器地址和端口
- 确保网络连通
- 验证 API 服务运行状态

**认证失败**
- 检查用户名密码
- 确认服务器开启 Basic Auth

**本地播放无声音**
- 检查手机音量
- 确认已授予存储权限
- 重启应用

## 📝 更新日志

查看 [RELEASE_V2.0.0.md](RELEASE_V2.0.0.md) 了解最新版本详情。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- Flutter 团队
- Riverpod 状态管理
- Material Design
- 所有贡献者和用户

---

**HMusic** - 让音乐更简单 🎶
