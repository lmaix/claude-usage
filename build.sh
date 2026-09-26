#!/bin/zsh
# Compile ClaudeUsage.app and install it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="ClaudeUsage.app"

echo "▸ Tests"
swiftc -O -o "${TMPDIR:-/tmp}/claudeusage-tests" Sources/UsageModel.swift Sources/BarRenderer.swift Sources/Keychain.swift Tests/main.swift
"${TMPDIR:-/tmp}/claudeusage-tests"

echo "▸ Build"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/ClaudeUsage" Sources/*.swift
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources" && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "▸ Installing into ~/Applications"
mkdir -p ~/Applications
pkill -x ClaudeUsage 2>/dev/null || true
# Before the rename the app was ClaudeUsageBar.app.
pkill -x ClaudeUsageBar 2>/dev/null || true
rm -rf ~/Applications/ClaudeUsageBar.app
rm -rf ~/Applications/"$APP"
cp -R "$APP" ~/Applications/
open ~/Applications/"$APP"
echo "✓ Running: ~/Applications/$APP"
