#!/bin/zsh
# Build a signed, notarized, universal ClaudeUsageBar.app and zip it for a GitHub release.
#
#   ./release.sh 1.1
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your login Keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarization credentials stored in the Keychain under the profile name below:
#        xcrun notarytool store-credentials claude-usage-bar --apple-id <you@example.com> --team-id <TEAMID>
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>, e.g. ./release.sh 1.1}"
PROFILE="${NOTARY_PROFILE:-claude-usage-bar}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
[[ -n "$IDENTITY" ]] || { echo "✗ No 'Developer ID Application' certificate in the Keychain (see the header of this script)."; exit 1; }

OUT="dist"
APP="$OUT/ClaudeUsageBar.app"
ZIP="$OUT/ClaudeUsageBar-$VERSION.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Tests"
swiftc -O -o "$TMP/tests" Sources/UsageModel.swift Sources/BarRenderer.swift Sources/Keychain.swift Tests/main.swift
"$TMP/tests" > /dev/null

echo "▸ Universal build $VERSION"
rm -rf "$OUT" && mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "$TMP/ClaudeUsageBar-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/ClaudeUsageBar" "$TMP"/ClaudeUsageBar-{arm64,x86_64}
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" "$APP/Contents/Info.plist"

echo "▸ Signing with $IDENTITY"
codesign --force --options runtime --timestamp --entitlements Resources/ClaudeUsageBar.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ Notarizing (a few minutes)"
ditto -c -k --keepParent "$APP" "$TMP/upload.zip"
xcrun notarytool submit "$TMP/upload.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "✓ $ZIP — attach it to a GitHub release tagged v$VERSION"
