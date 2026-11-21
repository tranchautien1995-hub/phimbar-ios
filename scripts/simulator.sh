#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate --spec simulator.yml
# Xcode creates the simulator's normal application identity and Keychain groups.
# Device/TrollStore entitlements remain separate in scripts/build.sh.
xcodebuild -project XemPhimQA.xcodeproj -scheme XemPhimQA -sdk iphonesimulator -configuration Debug -derivedDataPath build/QA-DerivedData CODE_SIGN_IDENTITY=- build > build/simulator-build.log 2>&1 || { tail -100 build/simulator-build.log; exit 1; }
APP=build/QA-DerivedData/Build/Products/Debug-iphonesimulator/XemPhim.app
codesign -d --entitlements :- "$APP" > build/simulator-entitlements.plist 2>/dev/null
DEVICE="$(xcrun simctl list devices available -j | ruby -rjson -e 'j=JSON.parse(STDIN.read); d=j["devices"].values.flatten.find{|x| x["name"].start_with?("iPhone")}; abort "No iPhone simulator" unless d; puts d["udid"]')"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
run_native_ui() {
  local ui_status=0
  xcodebuild -project XemPhimQA.xcodeproj -scheme XemPhimQA -sdk iphonesimulator -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/QA-DerivedData -resultBundlePath build/native-controls.xcresult CODE_SIGN_IDENTITY=- test > build/native-ui-test.log 2>&1 || ui_status=$?
  xcrun xcresulttool export attachments --path build/native-controls.xcresult --output-path build/native-ui-images || true
  if [ "$ui_status" -ne 0 ]; then tail -150 build/native-ui-test.log; return "$ui_status"; fi
}
if [ "${NATIVE_UI_ONLY:-0}" = 1 ]; then run_native_ui; exit $?; fi
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

rm -f "$DATA/Documents/player-verification.json"
xcrun simctl launch "$DEVICE" vn.onnstream.phimbar.ios --fixture-web-player
sleep 40
xcrun simctl io "$DEVICE" screenshot build/simulator-web-player.png
cp "$DATA/Documents/player-verification.json" build/web-player-verification.json
cat build/web-player-verification.json
xcrun simctl terminate "$DEVICE" vn.onnstream.phimbar.ios

xcrun simctl launch "$DEVICE" vn.onnstream.phimbar.ios --fixture-fullscreen
sleep 8
xcrun simctl io "$DEVICE" screenshot build/simulator-fullscreen.png
sleep 27
xcrun simctl io "$DEVICE" screenshot build/simulator-fullscreen-controls.png
cp "$DATA/Documents/native-fullscreen-verification.json" build/native-fullscreen-verification.json
ruby -rjson -e 'v=JSON.parse(File.read(ARGV[0])); abort "Native fullscreen failed" unless %w[nativeController nativeControls samePlayer pauseWorked seekWorked returnedToPlayer].all?{|k| v[k]}; puts "Native controls, pause, seek and return passed"' build/native-fullscreen-verification.json
xcrun simctl terminate "$DEVICE" vn.onnstream.phimbar.ios
run_native_ui
