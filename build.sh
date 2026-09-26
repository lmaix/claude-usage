#!/bin/zsh
# Compile ClaudeUsageBar.app and install it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="ClaudeUsageBar.app"

echo "▸ Tests"
swiftc -O -o "${TMPDIR:-/tmp}/claudeusagebar-tests" Sources/UsageModel.swift Sources/BarRenderer.swift Sources/Keychain.swift Tests/main.swift
"${TMPDIR:-/tmp}/claudeusagebar-tests"

echo "▸ Build"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/ClaudeUsageBar" Sources/*.swift
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "▸ Installing into ~/Applications"
mkdir -p ~/Applications
pkill -x ClaudeUsageBar 2>/dev/null || true
rm -rf ~/Applications/"$APP"
cp -R "$APP" ~/Applications/
open ~/Applications/"$APP"
echo "✓ Running: ~/Applications/$APP"
