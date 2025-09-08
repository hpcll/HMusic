#!/bin/bash
set -e

# xiaomusic OpenWrt Docker 网络模式部署脚本

# 默认配置
OPENWRT_IP=${OPENWRT_IP:-"192.168.31.2"}
OPENWRT_USER=${OPENWRT_USER:-"root"}
OPENWRT_PORT=${OPENWRT_PORT:-22}
NETWORK_MODE=${NETWORK_MODE:-"host"}
CONTAINER_IP=${CONTAINER_IP:-"192.168.31.100"}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  cat <<EOF
xiaomusic OpenWrt Docker 网络模式部署脚本

用法: $0 [选项]

网络模式选项:
  -n MODE     网络模式 (bridge|host|macvlan，默认: host)
  -i IP       容器IP地址 (仅macvlan模式，默认: 192.168.31.100)
  
基本选项:
  -h IP       OpenWrt IP地址 (默认: 192.168.31.2)
  -u USER     SSH用户名 (默认: root)
  -P PORT     SSH端口 (默认: 22)
  --help      显示帮助信息

网络模式说明:
  bridge   - 默认桥接模式 (端口映射)
  host     - 宿主机网络模式 (直接使用OpenWrt网络)
  macvlan  - 独立IP模式 (容器获得独立局域网IP)

示例:
  $0 -n host                                    # 使用host网络模式
  $0 -n macvlan -i 192.168.31.100               # 使用macvlan，容器IP为192.168.31.100
  $0 -h 192.168.31.5 -n bridge                  # 在其他OpenWrt设备上使用桥接模式
EOF
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      NETWORK_MODE="$2"
      shift 2
      ;;
    -i)
      CONTAINER_IP="$2"
      shift 2
      ;;
    -h)
      OPENWRT_IP="$2"
      shift 2
      ;;
    -u)
      OPENWRT_USER="$2"
      shift 2
      ;;
    -P)
      OPENWRT_PORT="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      log_error "未知参数: $1"
      usage
      exit 1
      ;;
  esac
done

# 验证网络模式
if [[ ! "$NETWORK_MODE" =~ ^(bridge|host|macvlan)$ ]]; then
  log_error "无效的网络模式: $NETWORK_MODE"
  usage
  exit 1
fi

log_info "=== xiaomusic OpenWrt Docker 网络部署 ==="
log_info "目标设备: ${OPENWRT_USER}@${OPENWRT_IP}:${OPENWRT_PORT}"
log_info "网络模式: ${NETWORK_MODE}"
if [[ "$NETWORK_MODE" == "macvlan" ]]; then
  log_info "容器IP: ${CONTAINER_IP}"
fi
log_info "============================================"

# 检查SSH连接
log_info "检查SSH连接..."
if ! ssh -p "$OPENWRT_PORT" -o ConnectTimeout=5 -o BatchMode=yes "${OPENWRT_USER}@${OPENWRT_IP}" "echo 'SSH连接正常'" 2>/dev/null; then
  log_error "SSH连接失败！请先运行 ./setup-ssh-key.sh 配置SSH密钥"
  exit 1
fi
log_success "SSH连接正常"

# 检查Docker支持
log_info "检查OpenWrt Docker支持..."
if ! ssh -p "$OPENWRT_PORT" "${OPENWRT_USER}@${OPENWRT_IP}" "which docker" 2>/dev/null; then
  log_error "OpenWrt上未安装Docker！"
  exit 1
fi
log_success "Docker已安装"

# 创建部署目录
log_info "创建部署目录..."
ssh -p "$OPENWRT_PORT" "${OPENWRT_USER}@${OPENWRT_IP}" "mkdir -p /opt/xiaomusic/{config,music,logs,playlists,lyrics}"

# 生成配置文件
log_info "生成xiaomusic配置文件..."
cat > /tmp/xiaomusic-config.json <<EOF
{
  "hardware": "L06A",
  "port": 8090,
  "verbose": true,
  "ffmpeg_location": "/usr/bin/ffmpeg",
  "music_path": "/app/music",
  "log_file": "/app/logs/xiaomusic.log"
}
EOF

scp -P "$OPENWRT_PORT" /tmp/xiaomusic-config.json "${OPENWRT_USER}@${OPENWRT_IP}:/opt/xiaomusic/config/config.json"
rm /tmp/xiaomusic-config.json

# 根据网络模式选择docker-compose文件
case "$NETWORK_MODE" in
  "host")
    log_info "使用Host网络模式..."
    COMPOSE_FILE="docker-compose-host.yml"
    scp -P "$OPENWRT_PORT" "$COMPOSE_FILE" "${OPENWRT_USER}@${OPENWRT_IP}:/opt/xiaomusic/docker-compose.yml"
    ;;
  "macvlan")
    log_info "使用Macvlan网络模式..."
    # 检查网络接口
    INTERFACE=$(ssh -p "$OPENWRT_PORT" "${OPENWRT_USER}@${OPENWRT_IP}" "ip route | grep default | awk '{print \$5}' | head -1")
    if [[ -z "$INTERFACE" ]]; then
      INTERFACE="br-lan"  # OpenWrt默认LAN桥接接口
    fi
    log_info "检测到网络接口: $INTERFACE"
    
    # 生成macvlan配置
    cat > /tmp/docker-compose-macvlan.yml <<EOF
version: '3.8'

services:
  xiaomusic:
    image: hanxi/xiaomusic:main
    container_name: xiaomusic
    restart: unless-stopped
    networks:
      lan:
        ipv4_address: $CONTAINER_IP
    volumes:
      - ./config:/app/config
      - ./music:/app/music
      - ./logs:/app/logs
      - ./playlists:/app/playlists
      - ./lyrics:/app/lyrics
    environment:
      - TZ=Asia/Shanghai
      - PYTHONUNBUFFERED=1
    command: ["xiaomusic", "--config", "/app/config/config.json"]

networks:
  lan:
    driver: macvlan
    driver_opts:
      parent: $INTERFACE
    ipam:
      config:
        - subnet: 192.168.31.0/24
          gateway: 192.168.31.1
          ip_range: $CONTAINER_IP/32
EOF
    scp -P "$OPENWRT_PORT" /tmp/docker-compose-macvlan.yml "${OPENWRT_USER}@${OPENWRT_IP}:/opt/xiaomusic/docker-compose.yml"
    rm /tmp/docker-compose-macvlan.yml
    ;;
  "bridge")
    log_info "使用Bridge网络模式..."
    scp -P "$OPENWRT_PORT" "docker-compose.yml" "${OPENWRT_USER}@${OPENWRT_IP}:/opt/xiaomusic/"
    ;;
esac

# 停止现有服务
log_info "停止现有服务..."
ssh -p "$OPENWRT_PORT" "${OPENWRT_USER}@${OPENWRT_IP}" "cd /opt/xiaomusic && docker-compose down" 2>/dev/null || true

# 启动服务
log_info "启动xiaomusic服务..."
ssh -p "$OPENWRT_PORT" "${OPENWRT_USER}@${OPENWRT_IP}" "cd /opt/xiaomusic && docker-compose up -d"

# 等待服务启动
log_info "等待服务启动..."
sleep 10

# 检查服务状态
log_info "检查服务状态..."
if ssh -p "$OPENWRT_PORT" "${OPENWRT_USER}@${OPENWRT_IP}" "docker ps | grep xiaomusic" >/dev/null 2>&1; then
  log_success "xiaomusic服务启动成功！"
  
  log_info "============================================="
  log_success "🎉 部署完成！"
  log_info "============================================="
  
  case "$NETWORK_MODE" in
    "host")
      log_info "🌐 Web控制台: http://${OPENWRT_IP}:8090"
      log_info "📡 网络模式: Host (直接使用OpenWrt网络)"
      ;;
    "macvlan")
      log_info "🌐 Web控制台: http://${CONTAINER_IP}:8090"
      log_info "📡 网络模式: Macvlan (独立IP: ${CONTAINER_IP})"
      ;;
    "bridge")
      log_info "🌐 Web控制台: http://${OPENWRT_IP}:8090"
      log_info "📡 网络模式: Bridge (端口映射)"
      ;;
  esac
  
  log_info "📁 音乐目录: /opt/xiaomusic/music/"
  log_info "⚙️  配置文件: /opt/xiaomusic/config/config.json"
  log_info "============================================="
else
  log_error "服务启动失败！请检查日志:"
  log_info "ssh -p $OPENWRT_PORT ${OPENWRT_USER}@${OPENWRT_IP} 'docker logs xiaomusic'"
  exit 1
fi
