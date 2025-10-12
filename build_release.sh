#!/bin/bash

# HMusic - 完整打包脚本
# 自动从 pubspec.yaml 读取版本号
# 构建Android APK(签名+混淆) 和 iOS IPA(无签名)

set -e

echo "🚀 HMusic 打包脚本"
echo "======================================"
echo ""

# 自动读取版本号
VERSION=$(grep "^version:" pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
BUILD_NUMBER=$(grep "^version:" pubspec.yaml | awk '{print $2}' | cut -d'+' -f2)

echo "📋 当前版本信息："
echo "  版本号: $VERSION"
echo "  构建号: $BUILD_NUMBER"
echo ""

# 询问是否需要更新版本号
read -p "是否需要修改版本号? (y/N): " update_version
if [[ "$update_version" =~ ^[Yy]$ ]]; then
    read -p "请输入新版本号 (例如 2.0.3): " new_version
    read -p "请输入新构建号 (例如 2025101301): " new_build

    # 更新 pubspec.yaml
    sed -i '' "s/^version: .*/version: $new_version+$new_build/" pubspec.yaml

    VERSION=$new_version
    BUILD_NUMBER=$new_build

    echo "✅ 版本号已更新为: $VERSION ($BUILD_NUMBER)"
    echo ""
fi

# 询问构建选项
echo "📱 构建选项："
echo "  1. 仅构建 Android APK (推荐，兼容所有设备)"
echo "  2. 仅构建 Android APK (仅arm64，体积小)"
echo "  3. 仅构建 iOS IPA"
echo "  4. 构建 Android + iOS"
echo ""
read -p "请选择 (1-4, 默认4): " build_choice
build_choice=${build_choice:-4}

echo ""
echo "======================================"
echo "开始构建..."
echo "======================================"
echo ""

# 清理构建
echo "🧹 清理之前的构建..."
flutter clean
flutter pub get

# 创建输出目录
mkdir -p build/release
mkdir -p build/symbols

# 构建 Android
if [[ "$build_choice" == "1" || "$build_choice" == "4" ]]; then
    echo ""
    echo "📱 构建 Android APK (全架构)..."
    echo "  - 包含架构: arm64-v8a, armeabi-v7a, x86_64"
    echo "  - 混淆: ✅"
    echo "  - 签名: ✅"
    echo ""

    flutter build apk --release \
      --obfuscate \
      --split-debug-info=build/symbols

    # 复制到release目录并重命名
    cp build/app/outputs/flutter-apk/app-release.apk \
       build/release/HMusic-v${VERSION}-android-signed.apk

    echo "✅ Android APK 构建完成"
    echo "  文件: build/release/HMusic-v${VERSION}-android-signed.apk"
    echo "  大小: $(du -h build/release/HMusic-v${VERSION}-android-signed.apk | cut -f1)"
    echo ""
fi

if [[ "$build_choice" == "2" ]]; then
    echo ""
    echo "📱 构建 Android APK (仅arm64)..."
    echo "  - 包含架构: arm64-v8a (现代设备)"
    echo "  - 混淆: ✅"
    echo "  - 签名: ✅"
    echo ""

    flutter build apk --release \
      --obfuscate \
      --split-debug-info=build/symbols \
      --target-platform android-arm64

    # 复制到release目录并重命名
    cp build/app/outputs/flutter-apk/app-release.apk \
       build/release/HMusic-v${VERSION}-android-arm64-signed.apk

    echo "✅ Android APK (arm64) 构建完成"
    echo "  文件: build/release/HMusic-v${VERSION}-android-arm64-signed.apk"
    echo "  大小: $(du -h build/release/HMusic-v${VERSION}-android-arm64-signed.apk | cut -f1)"
    echo ""
fi

# 构建 iOS
if [[ "$build_choice" == "3" || "$build_choice" == "4" ]]; then
    echo ""
    echo "🍎 构建 iOS IPA..."
    echo "  - 架构: arm64"
    echo "  - 混淆: ✅"
    echo "  - 签名: ❌ (用户可自签)"
    echo ""

    flutter build ios --release \
      --no-codesign \
      --obfuscate \
      --split-debug-info=build/symbols

    # 打包成 IPA
    cd build/ios/iphoneos
    mkdir -p Payload
    rm -rf Payload/Runner.app
    cp -r Runner.app Payload/
    zip -r ../../release/HMusic-v${VERSION}-ios-unsigned.ipa Payload
    rm -rf Payload
    cd - > /dev/null

    echo "✅ iOS IPA 构建完成"
    echo "  文件: build/release/HMusic-v${VERSION}-ios-unsigned.ipa"
    echo "  大小: $(du -h build/release/HMusic-v${VERSION}-ios-unsigned.ipa | cut -f1)"
    echo ""
fi

# 生成校验和
echo ""
echo "🔐 生成文件校验和..."
cd build/release
shasum -a 256 HMusic-*.* > checksums.txt
cat checksums.txt
cd - > /dev/null

# 总结
echo ""
echo "======================================"
echo "✅ 构建完成！"
echo "======================================"
echo ""
echo "📦 构建产物目录: build/release/"
ls -lh build/release/
echo ""
echo "🔐 调试符号表目录: build/symbols/"
echo "   (用于崩溃分析，不要删除也不要公开)"
echo ""
echo "📝 版本信息:"
echo "   版本: $VERSION"
echo "   构建: $BUILD_NUMBER"
echo ""
echo "🎯 下一步操作:"
echo "   1. 测试安装包"
echo "   2. 发布到 GitHub Release"
echo "   3. 保存 build/symbols/ 用于崩溃分析"
echo ""
