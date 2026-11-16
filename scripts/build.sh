#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
APP=build/Payload/MessengerRestart.app
mkdir -p "$APP"
cc -std=c11 -Wall -Wextra -Werror tests/schedule.c -o build/schedule-test
./build/schedule-test
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fmodules -O2 -Wall -Wextra -Wno-unused-parameter -framework UIKit -framework Foundation -framework CallKit App.m -o "$APP/MessengerRestart"
cp Info.plist "$APP/Info.plist"
swift scripts/icon.swift "$APP"
plutil -lint "$APP/Info.plist" Entitlements.plist
codesign --force --sign - --entitlements Entitlements.plist "$APP"
codesign --verify --strict "$APP"
codesign -d --entitlements :- "$APP" > build/signed-entitlements.plist
plutil -lint build/signed-entitlements.plist
otool -l "$APP/MessengerRestart" > build/macho-info.txt
cd build
zip -qr MessengerRestart-iOS15-TrollStore.ipa Payload
shasum -a 256 MessengerRestart-iOS15-TrollStore.ipa > SHA256.txt
