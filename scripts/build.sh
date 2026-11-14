#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p build/Payload/Phimbar.app
APP=build/Payload/Phimbar.app
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fmodules -O2 -framework UIKit -framework WebKit -framework Foundation App.m -o "$APP/Phimbar"
cp Info.plist "$APP/Info.plist"
cp Resources/* "$APP/"
plutil -lint "$APP/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
otool -l "$APP/Phimbar" > build/macho-info.txt
cd build
zip -qr Phimbar-iOS15-TrollStore.ipa Payload
shasum -a 256 Phimbar-iOS15-TrollStore.ipa > SHA256.txt
