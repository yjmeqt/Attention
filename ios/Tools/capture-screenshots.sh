#!/bin/zsh
# Captures raw App Store screenshots from dedicated simulators using the Debug-only
# demo launch arguments (demoURL, demoStyle, demoHistory, demoNoAutoShare). Output: ios/fastlane/raw/<locale>/<device>-<scene>.png
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=../build/ios
APP=$DERIVED/Build/Products/Debug-iphonesimulator/Attention.app
BUNDLE=com.yjmeqt.attention.dev
OUT=fastlane/raw

xcodebuild -project Attention.xcodeproj -scheme Attention -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath $DERIVED build -quiet

devices=(
  "Attention-Shots-iPhone|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max|iphone"
  "Attention-Shots-iPad|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB|ipad"
)
# fastlane locale|app language|region|App Store storefront. es-MX reuses the es-ES shots.
locales=(
  "zh-Hans|zh-Hans|zh_CN|cn" "en-US|en|en_US|us" "ko|ko|ko_KR|kr" "ja|ja|ja_JP|jp" "ru|ru|ru_RU|ru"
  "vi|vi|vi_VN|vn" "ar-SA|ar|ar_SA|sa" "fr-FR|fr|fr_FR|fr" "de-DE|de|de_DE|de" "es-ES|es|es_ES|es"
)
# ONLY="ko ja" limits the run to those fastlane locales.
ONLY=${ONLY:-}
# label|url|extra launch flag ({cc} becomes the storefront: cn or us). Labels starting with _
# are launched but not captured, so History has more to show. 2-extension is captured by hand
# from Safari's share sheet. Demo launches hide the paste banner; 7-empty shows it with a link copied.
APPSTORE="https://apps.apple.com/{cc}/app/keynote/id361285480"
MUSIC="https://music.apple.com/us/station/apple-music-1/ra.978194965"
MAPS="https://maps.apple.com/place?address=Apple%20Park&coordinate=37.334922,-122.009033&name=Apple%20Park"
scenes=(
  "_iphone|https://www.apple.com/iphone/|"
  "_podcasts|https://podcasts.apple.com/us/browse|"
  "_store|https://apps.apple.com/{cc}/app/apple-store/id375380948|"
  "1-appstore|$APPSTORE|"
  "3-music|$MUSIC|"
  "4-maps|$MAPS|"
  "5-history|$MAPS|demoHistory"
  "6-style|$APPSTORE|demoStyle"
  "7-empty||"
)

for device in $devices; do
  IFS='|' read -r name type slug <<< "$device"
  udid=$(xcrun simctl list devices | sed -n "s/^ *$name (\([0-9A-F-]*\)).*/\1/p" | head -1)
  [[ -z $udid ]] && udid=$(xcrun simctl create "$name" "$type")
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode active --cellularBars 4 --dataNetwork wifi

  for locale in $locales; do
    IFS='|' read -r lang language region cc <<< "$locale"
    [[ -n $ONLY && " $ONLY " != *" $lang "* ]] && continue
    # A fresh install per locale keeps History in that locale's language.
    xcrun simctl uninstall "$udid" $BUNDLE 2>/dev/null || true
    xcrun simctl install "$udid" "$APP"
    mkdir -p "$OUT/$lang"
    for scene in $scenes; do
      IFS='|' read -r label url flag <<< "$scene"
      args=(-AppleLanguages "($language)" -AppleLocale "$region" -seenShareGuide YES -demoNoAutoShare YES)
      [[ -n $url ]] && args+=(-demoURL "${url//\{cc\}/$cc}")
      [[ -n $flag ]] && args+=(-$flag YES)
      xcrun simctl terminate "$udid" $BUNDLE 2>/dev/null || true
      [[ $label == 7-empty ]] && printf '%s' "$MUSIC" | xcrun simctl pbcopy "$udid"
      xcrun simctl launch "$udid" $BUNDLE "${args[@]}" >/dev/null
      sleep 9
      [[ $label == _* ]] && continue
      xcrun simctl io "$udid" screenshot --type=png "$OUT/$lang/$slug-$label.png" >/dev/null 2>&1
      echo "captured $lang/$slug-$label"
    done
  done
  xcrun simctl terminate "$udid" $BUNDLE 2>/dev/null || true
done
