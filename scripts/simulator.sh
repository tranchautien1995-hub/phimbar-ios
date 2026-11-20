#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
APP=build/Simulator/XemPhim.app
mkdir -p "$APP"
xcrun swiftc -swift-version 5 -parse-as-library -D UI_PREVIEW -target "$ARCH-apple-ios15.0-simulator" -sdk "$SDK" Sources/*.swift -o "$APP/XemPhim" -framework SwiftUI -framework AVKit -framework Security -framework SafariServices
cp Info.plist "$APP/Info.plist"
plutil -replace CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$APP/Info.plist"
# Simulator binaries run under macOS/CoreSimulator, not TrollStore's iOS signer.
# Do not apply the device-only application/keychain identity to this executable.
DEVICE="$(xcrun simctl list devices available -j | ruby -rjson -e 'j=JSON.parse(STDIN.read); d=j["devices"].values.flatten.find{|x| x["name"].start_with?("iPhone")}; abort "No iPhone simulator" unless d; puts d["udid"]')"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl launch "$DEVICE" vn.onnstream.phimbar.ios | tee build/simulator-launch.txt
sleep 8
xcrun simctl io "$DEVICE" screenshot build/simulator-login.png
xcrun simctl terminate "$DEVICE" vn.onnstream.phimbar.ios
xcrun simctl launch "$DEVICE" vn.onnstream.phimbar.ios --fixture-keychain
sleep 3
DATA="$(xcrun simctl get_app_container "$DEVICE" vn.onnstream.phimbar.ios data)"
cp "$DATA/Documents/keychain-verification.json" build/keychain-verification.json
ruby -rjson -e 'v=JSON.parse(File.read(ARGV[0])); abort "Keychain check failed" unless v["savedAndRead"] && v["deleted"]; puts "Keychain save/read/delete passed"' build/keychain-verification.json
xcrun simctl terminate "$DEVICE" vn.onnstream.phimbar.ios
for PAGE in home details; do
  xcrun simctl launch "$DEVICE" vn.onnstream.phimbar.ios "--fixture-$PAGE"
  sleep 5
  xcrun simctl io "$DEVICE" screenshot "build/simulator-$PAGE.png"
  xcrun simctl terminate "$DEVICE" vn.onnstream.phimbar.ios
done
xcrun simctl launch "$DEVICE" vn.onnstream.phimbar.ios --fixture-player
sleep 30
xcrun simctl io "$DEVICE" screenshot build/simulator-player.png
DATA="$(xcrun simctl get_app_container "$DEVICE" vn.onnstream.phimbar.ios data)"
cp "$DATA/Documents/player-verification.json" build/player-verification.json
cat build/player-verification.json
xcrun simctl terminate "$DEVICE" vn.onnstream.phimbar.ios
