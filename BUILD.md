# HMusic 打包指南

## 📦 快速打包

### 一键打包（推荐）

```bash
./build_release.sh
```

脚本会：
1. 自动读取 `pubspec.yaml` 中的版本号
2. 询问是否需要更新版本号
3. 选择构建平台 (Android/iOS/全部)
4. 自动构建、签名、混淆、打包
5. 生成文件校验和

### 构建产物

所有构建产物在 `build/release/` 目录：

```
build/release/
├── HMusic-v2.0.2-android-signed.apk        # Android包 (已签名)
├── HMusic-v2.0.2-ios-unsigned.ipa          # iOS包 (未签名)
└── checksums.txt                            # 文件校验和
```

---

## 🔧 手动打包

### 1. 修改版本号

编辑 `pubspec.yaml`：

```yaml
version: 2.0.3+2025101301
#       ^^^^^ ^^^^^^^^^^
#       版本号  构建号
```

**版本号规则**：
- 格式：`主版本.次版本.修订号+构建号`
- 例如：`2.0.3+2025101301`
  - `2.0.3` = 版本号（语义化版本）
  - `2025101301` = 构建号（年月日时）

### 2. 构建 Android

#### 方式1：全架构版本（60MB，兼容所有设备）

```bash
flutter clean
flutter pub get
flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/symbols
```

#### 方式2：仅arm64版本（20MB，现代设备）

```bash
flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/symbols \
  --target-platform android-arm64
```

#### 方式3：多架构分离（推荐分发）

```bash
flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/symbols \
  --split-per-abi
```

会生成3个APK：
- `app-armeabi-v7a-release.apk` (32位设备)
- `app-arm64-v8a-release.apk` (64位设备)
- `app-x86_64-release.apk` (模拟器/x86设备)

**Android 构建产物位置**：
```
build/app/outputs/flutter-apk/app-release.apk
```

### 3. 构建 iOS

```bash
flutter build ios --release \
  --no-codesign \
  --obfuscate \
  --split-debug-info=build/symbols
```

**打包成 IPA**：

```bash
cd build/ios/iphoneos
mkdir -p Payload
cp -r Runner.app Payload/
zip -r ../HMusic-unsigned.ipa Payload
rm -rf Payload
cd -
```

**iOS 构建产物位置**：
```
build/ios/iphoneos/Runner.app
```

---

## 🔐 Android 签名配置

### 签名文件位置

```
android/app/hmusic-release.jks          # 签名密钥文件
android/key.properties                   # 签名配置
```

### 签名配置内容 (`android/key.properties`)

```properties
storePassword=hmusic2025
keyPassword=hmusic2025
keyAlias=hmusic
storeFile=app/hmusic-release.jks
```

### 混淆配置

混淆规则在：
```
android/app/proguard-rules.pro
```

**已配置的混淆规则：**
- ✅ Flutter/Dart 保留规则
- ✅ 网络请求库保留规则 (Dio/Gson)
- ✅ 第三方库保留规则
- ✅ 移除日志输出
- ✅ 优化字节码

---

## 📝 版本号管理

### 版本号在哪里？

**唯一来源**：`pubspec.yaml` 第19行

```yaml
version: 2.0.2+2025101201
```

### 版本号如何同步？

Flutter 构建时会自动同步到：

**Android**：
- `versionName` = `2.0.2` (显示给用户)
- `versionCode` = `2025101201` (内部版本号)
- 在 `android/app/build.gradle.kts` 中自动读取

**iOS**：
- `CFBundleShortVersionString` = `2.0.2`
- `CFBundleVersion` = `2025101201`
- 在 `ios/Runner/Info.plist` 中自动读取

### 如何更新版本号？

**方法1：直接编辑文件**

```bash
vim pubspec.yaml
# 修改第19行: version: 2.0.3+2025101401
```

**方法2：使用脚本（推荐）**

```bash
./build_release.sh
# 脚本会提示你输入新版本号
```

**方法3：命令行覆盖（临时）**

```bash
flutter build apk --build-name=2.0.3 --build-number=2025101401
```

注意：此方法**不会**修改 `pubspec.yaml`

---

## 🎯 完整构建流程

### 发布新版本的完整步骤

1. **更新版本号**
   ```bash
   vim pubspec.yaml
   # 修改 version: 2.0.3+2025101401
   ```

2. **运行打包脚本**
   ```bash
   ./build_release.sh
   ```

3. **测试安装包**
   - Android: 安装 `build/release/HMusic-v2.0.3-android-signed.apk`
   - iOS: 安装 `build/release/HMusic-v2.0.3-ios-unsigned.ipa`

4. **提交代码**
   ```bash
   git add pubspec.yaml
   git commit -m "chore: bump version to 2.0.3"
   git tag v2.0.3
   git push origin release/v2.0.3
   git push origin v2.0.3
   ```

5. **创建 GitHub Release**
   ```bash
   gh release create v2.0.3 \
     build/release/HMusic-v2.0.3-android-signed.apk \
     build/release/HMusic-v2.0.3-ios-unsigned.ipa \
     build/release/checksums.txt \
     --title "Release v2.0.3" \
     --notes "发布说明..."
   ```

6. **保存调试符号**
   ```bash
   # 压缩并备份 symbols 目录
   tar -czf symbols-v2.0.3.tar.gz build/symbols/
   # 上传到安全位置（不要公开）
   ```

---

## 📂 目录结构

```
HMusic/
├── pubspec.yaml                          # 📍 版本号在这里
├── build_release.sh                      # 🚀 一键打包脚本
├── build_android_obfuscated.sh           # Android专用脚本
├── build_obfuscated.sh                   # 全平台脚本（旧）
│
├── android/
│   ├── app/
│   │   ├── build.gradle.kts              # Android构建配置
│   │   ├── proguard-rules.pro            # 混淆规则
│   │   └── hmusic-release.jks            # 🔐 签名密钥
│   └── key.properties                    # 签名配置
│
├── ios/
│   └── Runner/
│       └── Info.plist                    # iOS版本信息
│
└── build/                                # 构建输出目录
    ├── release/                          # 📦 发布包
    │   ├── HMusic-v2.0.2-android-signed.apk
    │   ├── HMusic-v2.0.2-ios-unsigned.ipa
    │   └── checksums.txt
    │
    └── symbols/                          # 🔐 调试符号（不要删除）
        └── app.android-arm64.symbols
```

---

## ⚠️ 重要提醒

### 不要泄露的文件

- ❌ `android/app/hmusic-release.jks` (签名密钥)
- ❌ `android/key.properties` (签名配置)
- ❌ `build/symbols/` (调试符号)

### 需要保存的文件

- ✅ `build/symbols/` - 用于崩溃分析
- ✅ `android/app/hmusic-release.jks` - 重要！丢失后无法更新应用

### Git 忽略

已在 `.gitignore` 中配置：
```gitignore
android/key.properties
android/app/*.jks
build/
```

---

## 🐛 常见问题

### Q1: 签名失败 "Keystore file not found"

**原因**：签名密钥文件路径不对

**解决**：检查 `android/key.properties` 中的 `storeFile` 路径
```properties
storeFile=app/hmusic-release.jks
```

### Q2: iOS 构建成功但没有 IPA

**原因**：`flutter build ios` 只生成 `.app`，需要手动打包

**解决**：使用 `build_release.sh` 脚本会自动打包

### Q3: 版本号没有更新

**原因**：修改了 `pubspec.yaml` 但没有重新 `flutter pub get`

**解决**：
```bash
flutter clean
flutter pub get
```

### Q4: Android包太大 (60MB)

**原因**：包含了3个架构

**解决**：使用 `--target-platform android-arm64` 只打包arm64（约20MB）

### Q5: iOS 安装提示"未信任的开发者"

**原因**：IPA 未签名

**解决**：
- 方法1: 使用 Xcode 重签名
- 方法2: 使用 iOS App Signer
- 方法3: 使用 AltStore/SideStore 侧载

---

## 📚 参考资料

- [Flutter 构建文档](https://docs.flutter.dev/deployment)
- [Android 签名指南](https://developer.android.com/studio/publish/app-signing)
- [iOS 分发指南](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
