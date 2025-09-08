# xiaomusic OpenWrt Docker 部署指南

本指南将帮助您在 OpenWrt 路由器上通过 Docker 部署 xiaomusic 服务。

## 🎯 项目简介

基于 [hanxi/xiaomusic](https://github.com/hanxi/xiaomusic) 项目的 OpenWrt Docker 部署方案，让您可以在路由器上运行小爱音箱音乐控制服务。

## 📋 前置要求

### OpenWrt 路由器要求
- OpenWrt 系统（推荐 21.02 及以上版本）
- 至少 512MB RAM（推荐 1GB+）
- 至少 2GB 存储空间
- 已安装 Docker 和 Docker Compose

### 本地环境要求
- Linux/macOS 系统（支持 bash）
- 已安装 SSH 客户端
- 网络可访问 OpenWrt 设备

## 🚀 快速部署

### 第一步：配置 SSH 免密登录

首先配置 SSH 密钥，实现免密登录到 OpenWrt 设备：

```bash
# 使用默认配置（OpenWrt IP: 192.168.31.2）
./setup-ssh-key.sh

# 或指定自定义配置
./setup-ssh-key.sh -h 192.168.31.100 -u root -P 22
```

### 第二步：一键部署 xiaomusic

SSH 配置完成后，运行部署脚本：

```bash
# 基础部署（默认使用host网络模式）
./quick_deploy_xiaomusic.sh

# 使用不同网络模式部署
./quick_deploy_xiaomusic.sh -n host      # Host网络模式（默认）
./quick_deploy_xiaomusic.sh -n bridge    # 桥接模式
./quick_deploy_xiaomusic.sh -n macvlan -i 192.168.31.100  # 独立IP模式
```

### 第三步：访问服务

部署成功后，通过浏览器访问：
- Web 控制台：http://your_openwrt_ip:8090
- API 文档：http://your_openwrt_ip:8090/docs

## 🔧 部署参数说明

### setup-ssh-key.sh 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| -h IP | OpenWrt IP地址 | 192.168.31.2 |
| -u USER | SSH用户名 | root |
| -P PORT | SSH端口 | 22 |

### quick_deploy_xiaomusic.sh 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| -h IP | OpenWrt IP地址 | 192.168.31.2 |
| -u USER | SSH用户名 | root |
| -P PORT | SSH端口 | 22 |
| -v VERSION | xiaomusic版本 | latest |
| -p PORT | 服务端口 | 8090 |
| -a ACCOUNT | 小米账号 | - |
| -w PASSWORD | 小米密码 | - |
| -c COOKIE | 小米Cookie | - |

## 📁 目录结构

部署完成后，OpenWrt 上的目录结构：

```
/opt/xiaomusic/
├── docker-compose.yml      # Docker Compose 配置
├── xiaomusic-manager.sh    # 服务管理脚本
├── config/
│   └── config.json         # xiaomusic 配置文件
├── music/                  # 音乐文件目录
├── logs/                   # 日志文件目录
├── playlists/              # 播放列表目录
└── lyrics/                 # 歌词文件目录
```

## 🛠️ 服务管理

使用内置的管理脚本控制服务：

```bash
# SSH 登录到 OpenWrt
ssh root@192.168.31.2

# 查看服务状态
/opt/xiaomusic/xiaomusic-manager.sh status

# 启动服务
/opt/xiaomusic/xiaomusic-manager.sh start

# 停止服务
/opt/xiaomusic/xiaomusic-manager.sh stop

# 重启服务
/opt/xiaomusic/xiaomusic-manager.sh restart

# 查看日志
/opt/xiaomusic/xiaomusic-manager.sh logs

# 更新到最新版本
/opt/xiaomusic/xiaomusic-manager.sh update

# 进入容器 shell
/opt/xiaomusic/xiaomusic-manager.sh shell
```

## 🎵 音乐文件管理

### 上传音乐文件

```bash
# 上传单个音乐文件
scp -P 22 song.mp3 root@192.168.31.2:/opt/xiaomusic/music/

# 批量上传音乐文件
scp -P 22 *.mp3 root@192.168.31.2:/opt/xiaomusic/music/

# 上传整个音乐目录
scp -P 22 -r ./my_music/ root@192.168.31.2:/opt/xiaomusic/music/
```

### 支持的音乐格式

- MP3
- FLAC
- WAV
- APE
- OGG
- M4A

## ⚙️ 配置文件说明

主要配置文件位于 `/opt/xiaomusic/config/config.json`：

```json
{
  "hardware": "L06A",                    // 小爱音箱型号
  "port": 8090,                          // 服务端口
  "account": "your_xiaomi_account",      // 小米账号
  "password": "your_xiaomi_password",    // 小米密码
  "verbose": true,                       // 详细日志
  "music_path": "/app/music",           // 音乐文件路径
  "log_file": "/app/logs/xiaomusic.log", // 日志文件路径
  "enable_tts": true,                    // 启用TTS
  "default_volume": 30,                  // 默认音量
  "download_quality": "high"             // 下载质量
}
```

完整配置选项请参考 `config-example.json` 文件。

## 🔍 故障排除

### 常见问题

**1. SSH 连接失败**
```bash
# 检查网络连接
ping 192.168.31.2

# 检查 SSH 服务
telnet 192.168.31.2 22
```

**2. Docker 未安装**
```bash
# 在 OpenWrt 上安装 Docker
opkg update
opkg install docker dockerd docker-compose
/etc/init.d/dockerd start
/etc/init.d/dockerd enable
```

**3. 服务启动失败**
```bash
# 查看详细日志
docker logs xiaomusic

# 检查配置文件
cat /opt/xiaomusic/config/config.json
```

**4. 小爱音箱连接失败**
- 确保小爱音箱和 OpenWrt 在同一网络
- 检查小米账号密码是否正确
- 尝试使用小米 Cookie 登录

### 日志查看

```bash
# 实时查看服务日志
/opt/xiaomusic/xiaomusic-manager.sh logs

# 查看历史日志
cat /opt/xiaomusic/logs/xiaomusic.log

# 查看 Docker 容器日志
docker logs xiaomusic
```

## 🔄 更新升级

### 更新 xiaomusic 版本

```bash
# 使用管理脚本更新
/opt/xiaomusic/xiaomusic-manager.sh update

# 或手动更新
cd /opt/xiaomusic
docker-compose pull
docker-compose up -d
```

### 更新部署脚本

从 main 分支拉取最新的部署脚本：

```bash
git pull origin main
```

## 🛡️ 安全建议

1. **修改默认端口**：避免使用默认的 8090 端口
2. **启用认证**：在配置文件中启用 HTTP Basic Auth
3. **防火墙设置**：限制服务访问的IP范围
4. **定期更新**：保持 xiaomusic 和 OpenWrt 系统更新

## 📱 客户端应用

本项目还包含 Flutter 客户端应用，提供更好的用户体验：

- 🎵 播放控制：播放/暂停、上一首/下一首
- 🔊 音量控制：实时音量调节
- 📱 设备管理：多设备选择和状态显示
- 🔍 音乐搜索：搜索并直接播放
- 📋 播放列表：创建和管理播放列表

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。

## 🙏 致谢

- [hanxi/xiaomusic](https://github.com/hanxi/xiaomusic) - 核心音乐服务
- OpenWrt 社区 - 路由器系统支持
- Docker 社区 - 容器化方案

---

**如有问题，请查看故障排除部分或提交 Issue。**

