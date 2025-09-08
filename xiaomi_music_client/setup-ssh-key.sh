#!/bin/bash
set -e

# SSH密钥设置脚本（适配 xiaomusic，配置到 OpenWrt 免密登录）

OPENWRT_IP=${OPENWRT_IP:-"192.168.31.2"}
OPENWRT_USER=${OPENWRT_USER:-"root"}
OPENWRT_PORT=${OPENWRT_PORT:-22}

usage() {
  cat <<EOF
用法: $0 [-h IP] [-u USER] [-P PORT]
  -h  OpenWrt IP，默认 192.168.31.2
  -u  用户名，默认 root
  -P  SSH 端口，默认 22

示例:
  $0 -h 192.168.31.2 -u root -P 22
EOF
}

while getopts ":h:u:P:?" opt; do
  case "$opt" in
    h) OPENWRT_IP="$OPTARG" ;;
    u) OPENWRT_USER="$OPTARG" ;;
    P) OPENWRT_PORT="$OPTARG" ;;
    ?)
      usage; exit 0 ;;
  esac
done

echo "=== SSH密钥设置脚本 ==="
echo "目标: ${OPENWRT_USER}@${OPENWRT_IP}:${OPENWRT_PORT}"
echo "======================="

KEY_DIR="$HOME/.ssh"
PUB_KEY="$KEY_DIR/id_ed25519.pub"
PRV_KEY="$KEY_DIR/id_ed25519"

# 检查本地SSH密钥
if [ ! -f "$PUB_KEY" ]; then
  echo "❌ 未找到SSH公钥文件"
  echo "💡 正在生成新的SSH密钥 (ed25519)..."
  mkdir -p "$KEY_DIR"
  ssh-keygen -t ed25519 -f "$PRV_KEY" -N ""
fi

echo "🔑 找到SSH公钥: $PUB_KEY"

# 显示公钥内容
echo "📋 您的SSH公钥内容："
echo "===================="
cat "$PUB_KEY"
echo "===================="

echo
echo "🚀 开始配置免密登录...（需要输入一次 OpenWrt 密码用于上传公钥）"

# 上传公钥到OpenWrt
ssh-copy-id -p "$OPENWRT_PORT" -i "$PUB_KEY" "${OPENWRT_USER}@${OPENWRT_IP}"

echo "✅ SSH密钥配置完成"
echo
echo "🧪 测试免密登录..."
if ssh -p "$OPENWRT_PORT" -o ConnectTimeout=5 "${OPENWRT_USER}@${OPENWRT_IP}" "echo '免密登录测试成功'" 2>/dev/null; then
  echo "✅ 免密登录验证成功！"
  echo
  echo "📋 现在您可以："
  echo "  1) 无需密码 SSH 连接: ssh -p $OPENWRT_PORT ${OPENWRT_USER}@${OPENWRT_IP}"
  echo "  2) 一键部署 xiaomusic: ./quick_deploy_xiaomusic.sh"
  echo "  3) 直接上传音乐到设备: scp -P $OPENWRT_PORT 歌曲.mp3 ${OPENWRT_USER}@${OPENWRT_IP}:/opt/xiaomusic/music/"
  echo "  4) 批量上传（示例）: scp -P $OPENWRT_PORT *.mp3 ${OPENWRT_USER}@${OPENWRT_IP}:/opt/xiaomusic/music/"
else
  echo "⚠️  免密登录可能未完全配置成功，但公钥已上传。请手动测试:"
  echo "   ssh -p $OPENWRT_PORT ${OPENWRT_USER}@${OPENWRT_IP}"
fi

echo
echo "🎯 下一步: 可运行 ./quick_deploy_xiaomusic.sh 部署，或使用上面的 scp 命令上传音乐文件。"
echo
echo "📋 部署xiaomusic到OpenWrt Docker："
echo "  ./quick_deploy_xiaomusic.sh -h $OPENWRT_IP -u $OPENWRT_USER -P $OPENWRT_PORT"
echo
echo "🔧 如需自定义配置，可使用以下参数："
echo "  -a ACCOUNT  小米账号"
echo "  -w PASSWORD 小米密码"
echo "  -c COOKIE   小米Cookie"
echo "  -v VERSION  xiaomusic版本 (默认: latest)"
echo "  -p PORT     服务端口 (默认: 8090)"