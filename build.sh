#!/bin/zsh
# Compile ClaudeUsageBar.app and install it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="ClaudeUsageBar.app"
BUNDLE_ID="com.stephane.ClaudeUsageBar"

echo "▸ Tests"
swiftc -O -o "${TMPDIR:-/tmp}/claudeusagebar-tests" Sources/UsageModel.swift Sources/BarRenderer.swift Sources/Keychain.swift Tests/main.swift
"${TMPDIR:-/tmp}/claudeusagebar-tests"

echo "▸ Build"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/ClaudeUsageBar" Sources/*.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClaudeUsageBar</string>
  <key>CFBundleDisplayName</key><string>Claude Usage</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>ClaudeUsageBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"

echo "▸ Installing into ~/Applications"
mkdir -p ~/Applications
pkill -x ClaudeUsageBar 2>/dev/null || true
rm -rf ~/Applications/"$APP"
cp -R "$APP" ~/Applications/
open ~/Applications/"$APP"
echo "✓ Running: ~/Applications/$APP"
