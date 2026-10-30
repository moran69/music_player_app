#!/bin/bash
set -e

echo "=========================================="
echo "  Flutter 音乐播放器 APK 构建脚本"
echo "=========================================="

# 安装依赖
echo "[1/6] 安装系统依赖..."
sudo apt-get update -qq
sudo apt-get install -y -qq clang cmake git wget unzip curl libglu1-mesa > /dev/null 2>&1

# 检查 Flutter
FLUTTER_DIR="$HOME/flutter"
if [ ! -d "$FLUTTER_DIR" ]; then
    echo "[2/6] 下载 Flutter SDK (arm64)..."
    cd $HOME
    wget -q "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz" -O flutter.tar.xz
    tar xf flutter.tar.xz
    rm flutter.tar.xz
    echo "Flutter SDK 下载完成"
else
    echo "[2/6] Flutter SDK 已存在，跳过下载"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# 检查 Android SDK
ANDROID_DIR="$HOME/android-sdk"
if [ ! -d "$ANDROID_DIR" ]; then
    echo "[3/6] 下载 Android Command-line Tools..."
    mkdir -p "$ANDROID_DIR/cmdline-tools"
    cd /tmp
    wget -q "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -O cmdtools.zip
    unzip -q cmdtools.zip -d "$ANDROID_DIR/cmdline-tools"
    mv "$ANDROID_DIR/cmdline-tools/cmdline-tools" "$ANDROID_DIR/cmdline-tools/latest"
    rm cmdtools.zip
    echo "Android Tools 下载完成"
else
    echo "[3/6] Android SDK 已存在，跳过"
fi

export ANDROID_HOME="$ANDROID_DIR"
export ANDROID_SDK_ROOT="$ANDROID_DIR"

echo "[4/6] 安装 Android SDK 组件..."
yes | $ANDROID_DIR/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null 2>&1 || true
$ANDROID_DIR/cmdline-tools/latest/bin/sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" > /dev/null 2>&1 || true

# 接受 Flutter 许可
echo "[5/6] 配置 Flutter..."
flutter config --android-sdk "$ANDROID_DIR" > /dev/null 2>&1
yes | flutter doctor --android-licenses > /dev/null 2>&1 || true

# 构建项目
echo "[6/6] 开始构建 APK..."
cd /tmp/music_player_app
flutter pub get
flutter build apk --release 2>&1

echo ""
echo "=========================================="
echo "  构建完成!"
echo "=========================================="
APK_PATH="/tmp/music_player_app/build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
    echo "APK 路径: $APK_PATH"
    echo "APK 大小: $APK_SIZE"
else
    echo "ERROR: APK 文件未生成"
    exit 1
fi
