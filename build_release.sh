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
    # 读取新版本号,如果为空则保持当前版本
    read -p "请输入新版本号 (例如 2.0.3): " new_version
    if [ -z "$new_version" ]; then
        new_version=$VERSION
        echo "  保持当前版本号: $VERSION"
    fi

    # 自动生成构建号
    # 格式: YYYYMMDDhh (年月日时，10位数字)
    # 例如: 2025101411 表示 2025年10月14日11时
    auto_build=$(date +"%Y%m%d%H")

    # 检查新构建号是否大于当前构建号
    if [ "$auto_build" -le "$BUILD_NUMBER" ]; then
        # 如果自动生成的构建号不够大，则在当前基础上+1
        auto_build=$((BUILD_NUMBER + 1))
        echo "  ⚠️  自动生成的构建号不够大，使用递增值: $auto_build"
    fi

    read -p "请输入新构建号 (留空自动生成: $auto_build): " new_build
    new_build=${new_build:-$auto_build}

    # 再次验证新构建号是否大于当前构建号
    if [ "$new_build" -le "$BUILD_NUMBER" ]; then
        echo "  ❌ 错误：新构建号($new_build)必须大于当前构建号($BUILD_NUMBER)"
        exit 1
    fi

    # 更新 pubspec.yaml
    sed -i '' "s/^version: .*/version: $new_version+$new_build/" pubspec.yaml

    VERSION=$new_version
    BUILD_NUMBER=$new_build

    echo "✅ 版本号已更新为: $VERSION+$BUILD_NUMBER"
    echo ""
fi

# 询问构建选项
echo "📱 构建选项："
echo "  1. 仅构建 Android APK - 通用版 (推荐，单文件兼容所有设备)"
echo "  2. 仅构建 Android APK - 分架构版 (生成多个APK，体积更小)"
echo "  3. 仅构建 Android APK - 仅arm64 (现代设备，体积小)"
echo "  4. 仅构建 iOS IPA"
echo "  5. 构建 Android 通用版 + iOS"
echo "  6. 构建 Android 分架构版 + iOS"
echo ""
read -p "请选择 (1-6, 默认5): " build_choice
build_choice=${build_choice:-5}

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

# 构建 Android 通用版
if [[ "$build_choice" == "1" || "$build_choice" == "5" ]]; then
    echo ""
    echo "📱 构建 Android APK (通用版)..."
    echo "  - 包含架构: arm64-v8a, armeabi-v7a, x86_64"
    echo "  - 混淆: ✅"
    echo "  - 签名: ✅"
    echo ""

    flutter build apk --release \
      --obfuscate \
      --split-debug-info=build/symbols

    # 复制到release目录并重命名
    cp build/app/outputs/flutter-apk/app-release.apk \
       build/release/HMusic-v${VERSION}-android-universal.apk

    echo "✅ Android APK (通用版) 构建完成"
    echo "  文件: build/release/HMusic-v${VERSION}-android-universal.apk"
    echo "  大小: $(du -h build/release/HMusic-v${VERSION}-android-universal.apk | cut -f1)"
    echo ""
fi

# 构建 Android 分架构版
if [[ "$build_choice" == "2" || "$build_choice" == "6" ]]; then
    echo ""
    echo "📱 构建 Android APK (分架构版)..."
    echo "  - 为每个架构生成独立APK"
    echo "  - 架构: arm64-v8a, armeabi-v7a, x86_64"
    echo "  - 混淆: ✅"
    echo "  - 签名: ✅"
    echo ""

    flutter build apk --release \
      --split-per-abi \
      --obfuscate \
      --split-debug-info=build/symbols

    # 复制所有分架构APK到release目录
    echo "📦 复制分架构APK..."
    if [ -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]; then
        cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
           build/release/HMusic-v${VERSION}-android-arm64-v8a.apk
        echo "  ✅ arm64-v8a: $(du -h build/release/HMusic-v${VERSION}-android-arm64-v8a.apk | cut -f1)"
    fi

    if [ -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]; then
        cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk \
           build/release/HMusic-v${VERSION}-android-armeabi-v7a.apk
        echo "  ✅ armeabi-v7a: $(du -h build/release/HMusic-v${VERSION}-android-armeabi-v7a.apk | cut -f1)"
    fi

    if [ -f "build/app/outputs/flutter-apk/app-x86_64-release.apk" ]; then
        cp build/app/outputs/flutter-apk/app-x86_64-release.apk \
           build/release/HMusic-v${VERSION}-android-x86_64.apk
        echo "  ✅ x86_64: $(du -h build/release/HMusic-v${VERSION}-android-x86_64.apk | cut -f1)"
    fi

    echo ""
    echo "✅ Android APK (分架构版) 构建完成"
    echo ""
fi

# 构建 Android 单架构 (仅arm64)
if [[ "$build_choice" == "3" ]]; then
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
if [[ "$build_choice" == "4" || "$build_choice" == "5" || "$build_choice" == "6" ]]; then
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
