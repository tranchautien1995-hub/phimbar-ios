#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
APP=build/Simulator/XemPhim.app
mkdir -p "$APP"
xcrun swiftc -swift-version 5 -parse-as-library -target "$ARCH-apple-ios15.0-simulator" -sdk "$SDK" Sources/*.swift -o "$APP/XemPhim" -framework SwiftUI -framework AVKit -framework Security -framework SafariServices
cp Info.plist "$APP/Info.plist"
plutil -replace CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$APP/Info.plist"
DEVICE="$(xcrun simctl list devices available -j | ruby -rjson -e 'j=JSON.parse(STDIN.read); d=j["devices"].values.flatten.find{|x| x["name"].start_with?("iPhone")}; abort "No iPhone simulator" unless d; puts d["udid"]')"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl launch "$DEVICE" vn.onnstream.phimbar.ios | tee build/simulator-launch.txt
sleep 8
xcrun simctl io "$DEVICE" screenshot build/simulator-login.png
xcrun simctl terminate "$DEVICE" vn.onnstream.phimbar.ios
