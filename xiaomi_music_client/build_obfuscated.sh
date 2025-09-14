#!/bin/bash

# 小爱音乐盒 - 混淆构建脚本
# 用于生成安全的发布版本

set -e

echo "🚀 开始构建混淆版本..."

# 创建调试信息目录
mkdir -p ./build/debug-info

echo "📱 构建Android APK (混淆版本)..."
flutter build apk --release \
  --obfuscate \
  --split-debug-info=./build/debug-info \
  --target-platform=android-arm64 \
  --build-name=1.0.2-public \
  --build-number=2

echo "🍎 构建iOS IPA (混淆版本)..."
flutter build ios --release \
  --obfuscate \
  --split-debug-info=./build/debug-info \
  --build-name=1.0.2-public \
  --build-number=2

echo "🖥️ 构建macOS应用 (混淆版本)..."
flutter build macos --release \
  --obfuscate \
  --split-debug-info=./build/debug-info \
  --build-name=1.0.2-public \
  --build-number=2

echo "🐧 构建Linux应用 (混淆版本)..."
flutter build linux --release \
  --obfuscate \
  --split-debug-info=./build/debug-info \
  --build-name=1.0.2-public \
  --build-number=2

echo "🪟 构建Windows应用 (混淆版本)..."
flutter build windows --release \
  --obfuscate \
  --split-debug-info=./build/debug-info \
  --build-name=1.0.2-public \
  --build-number=2

echo "✅ 混淆构建完成！"
echo "📦 构建产物位置："
echo "  - Android APK: build/app/outputs/flutter-apk/app-release.apk"
echo "  - iOS IPA: build/ios/ipa/"
echo "  - macOS: build/macos/Build/Products/Release/"
echo "  - Linux: build/linux/x64/release/bundle/"
echo "  - Windows: build/windows/x64/runner/Release/"
echo "🔐 调试信息已保存到: build/debug-info/"
echo ""
echo "⚠️  重要提醒："
echo "  1. 请妥善保管 debug-info/ 目录，用于日后调试"
echo "  2. 发布时不要包含 debug-info/ 目录"
echo "  3. 建议对构建产物进行病毒扫描"

