#!/bin/bash

# 小爱音乐盒 - Android混淆构建脚本
# 专门用于构建安全的Android APK

set -e

echo "🚀 开始构建Android混淆版本..."

# 清理之前的构建
echo "🧹 清理之前的构建产物..."
flutter clean
flutter pub get

# 创建调试信息目录
mkdir -p ./build/debug-info

echo "📱 构建Android APK (混淆版本)..."
flutter build apk --release \
  --obfuscate \
  --split-debug-info=./build/debug-info \
  --build-name=1.0.2-public \
  --build-number=2

echo "✅ Android混淆构建完成！"
echo ""
echo "📦 构建产物："
echo "  APK文件: build/app/outputs/flutter-apk/app-release.apk"
echo "  文件大小: $(du -h build/app/outputs/flutter-apk/app-release.apk | cut -f1)"
echo ""
echo "🔐 调试信息保存在: build/debug-info/"
echo ""
echo "⚠️  安全提醒："
echo "  1. 这是混淆版本，逆向工程难度大大增加"
echo "  2. 请妥善保管 debug-info/ 目录用于调试"
echo "  3. 发布时不要泄露 debug-info/ 内容"
echo "  4. 建议在发布前进行病毒扫描"
echo ""
echo "🎯 现在可以安全地将APK发给其他人使用了！"

