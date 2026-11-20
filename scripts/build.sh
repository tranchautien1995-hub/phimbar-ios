#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Payload/XemPhim.app
APP=build/Payload/XemPhim.app
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-ios15.0 -sdk "$SDK" -O Sources/*.swift -o "$APP/XemPhim" -framework SwiftUI -framework AVKit -framework Security -framework SafariServices
cp Info.plist "$APP/Info.plist"
xcrun swift scripts/icon.swift "$APP"
plutil -lint "$APP/Info.plist"
codesign --force --sign - --entitlements Entitlements.plist "$APP"
codesign --verify --strict "$APP"
otool -l "$APP/XemPhim" > build/macho-info.txt
codesign -d --entitlements :- "$APP" > build/entitlements.plist 2>/dev/null || true
(cd build && zip -qr XemPhim-iOS15-TrollStore.ipa Payload && shasum -a 256 XemPhim-iOS15-TrollStore.ipa > SHA256.txt)
