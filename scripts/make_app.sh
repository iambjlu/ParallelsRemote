#!/bin/bash
# 把 SwiftPM 編出來的執行檔包成 ParallelsRemote.app。
# 「登入時自動啟動」(SMAppService)需要正式的 .app 才能使用。
# 用法:scripts/make_app.sh [輸出資料夾,預設為 build]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build}"
APP="$OUT/ParallelsRemote.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ParallelsRemote"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ParallelsRemote"

mkdir -p "$APP/Contents/Resources"
swift scripts/make_icon.swift "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Parallels Remote</string>
    <key>CFBundleDisplayName</key><string>Parallels Remote</string>
    <key>CFBundleIdentifier</key><string>com.iambjlu.ParallelsRemote</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>ParallelsRemote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <!-- 啟動時不顯示 Dock 圖示,只在選單列;主視窗開啟時由程式切成一般 App -->
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>提供區網內的網頁控制介面。</string>
</dict>
</plist>
PLIST

# ad-hoc 簽章(不需要開發者帳號;只在這台 Mac 上使用)
codesign --force --sign - "$APP"
echo "已建立 $APP"
