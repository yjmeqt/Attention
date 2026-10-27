#!/bin/zsh
# Captures raw App Store screenshots from dedicated simulators using the Debug-only
# demo launch arguments (demoLinks, demoTags, demoPrivate, demoOpen, demoUnlockPrivate, see DemoLibrary.swift).
# The share scene is Safari's own share sheet, with Attention in its app row. Rotating, unfolding and
# tapping need the argent CLI (npm i -g @swmansion/argent).
# Output: ios/fastlane/raw/<locale>/<device>-<scene>.png, plus JSON frames for the elements the frame
# script lifts out: Attention's cell in the share sheet, the detail card and the Face ID prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=../build/ios
APP=$DERIVED/Build/Products/Debug-iphonesimulator/Attention.app
BUNDLE=com.yjmeqt.attn.dev
OUT=fastlane/raw

xcodebuild -project Attention.xcodeproj -scheme Attention -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath $DERIVED APP_DISPLAY_NAME=Attention build -quiet

# name|device type|slug|orientation. iPad is shot in landscape, where the detail page puts the
# card beside its controls. Duo is unfolded, where LandscapeLeft gives a portrait UI on the inner display;
# duo-cover is the same simulator folded shut, on its outer display.
devices=(
  "Attention-Shots-iPhone|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max|iphone|Portrait"
  "Attention-Shots-iPad|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB|ipad|LandscapeLeft"
  "Attention-Shots-Duo|com.apple.CoreSimulator.SimDeviceType.iPhone-Duo|duo|LandscapeLeft"
  "Attention-Shots-Duo|com.apple.CoreSimulator.SimDeviceType.iPhone-Duo|duo-cover|Portrait"
)
# DEVICES="ipad duo" and SCENES="3-detail" limit the run to those devices and scenes.
DEVICES=${DEVICES:-}
SCENES=${SCENES:-}
# fastlane locale|app language|region|App Store storefront|Wikipedia language|tags: music,travel,work.
# ko and ru Wikipedia have no English-titled redirect for the bridge, so those use their own titles.
# es-MX reuses the es-ES shots.
locales=(
  "en-US|en|en_US|us|en|Music,Travel,Work" "zh-Hans|zh-Hans|zh_CN|cn|zh|音乐,旅行,工作"
  "ko|ko|ko_KR|kr|ko|음악,여행,업무" "ja|ja|ja_JP|jp|ja|音楽,旅行,仕事" "ru|ru|ru_RU|ru|ru|Музыка,Поездки,Работа"
  "vi|vi|vi_VN|vn|vi|Nhạc,Du lịch,Công việc" "ar-SA|ar|ar_SA|sa|ar|موسيقى,سفر,عمل"
  "fr-FR|fr|fr_FR|fr|fr|Musique,Voyage,Travail" "de-DE|de|de_DE|de|de|Musik,Reisen,Arbeit"
  "es-ES|es|es_ES|es|es|Música,Viajes,Trabajo"
)
# ONLY="ko ja" limits the run to those fastlane locales.
ONLY=${ONLY:-}
# The library, newest first. {cc} becomes the storefront, {wl} the Wikipedia language.
# The last twelve go to Private. Enough of each to fill the iPad's landscape grid.
links=(
  "https://www.apple.com/iphone/"
  "https://music.apple.com/us/station/apple-music-1/ra.978194965"
  "https://maps.apple.com/place?address=Apple%20Park&coordinate=37.334922,-122.009033&name=Apple%20Park"
  "https://apps.apple.com/{cc}/app/keynote/id361285480"
  "https://{wl}.wikipedia.org/wiki/{wt}"
  "https://podcasts.apple.com/us/browse"
  "https://developer.apple.com/swift/"
  "https://apps.apple.com/{cc}/app/apple-store/id375380948"
  "https://www.apple.com/apple-vision-pro/"
  "https://www.apple.com/macbook-pro/"
  "https://apps.apple.com/{cc}/app/garageband/id408709785"
  "https://www.apple.com/airpods-max/"
  "https://www.apple.com/mac-studio/"
  "https://apps.apple.com/{cc}/app/freeform/id6443742539"
  "https://www.apple.com/apple-tv-4k/"
  "https://www.apple.com/imac/"
  "https://www.apple.com/apple-arcade/"
  "https://www.apple.com/ipad-air/"
  "https://www.apple.com/apple-card/"
  "https://maps.apple.com/place?address=1%20Infinite%20Loop&coordinate=37.33182,-122.03118&name=Infinite%20Loop"
  "https://www.apple.com/airpods-pro/"
  "https://apps.apple.com/{cc}/app/pages/id361309726"
  "https://www.apple.com/airtag/"
  "https://www.apple.com/watch/"
  "https://www.apple.com/homepod/"
  "https://www.apple.com/ipad-pro/"
  "https://www.apple.com/apple-pay/"
  "https://www.apple.com/icloud/"
  "https://www.apple.com/apple-one/"
  "https://www.apple.com/apple-fitness-plus/"
)
# label|extra launch arguments. 2-share isn't the app: it's Safari's share sheet (see share_sheet),
# shot last so no app launch after it shows a "◂ Safari" back link in the status bar.
scenes=(
  "1-feed|"
  "3-detail|-demoOpen 0"
  "4-private|-demoUnlockPrivate YES"
  "2-share|"
)

# Boots the simulator in that language: the share sheet is drawn by the system, so the whole device
# has to switch, not just the app.
prepare() {
  local language=$1 region=$2
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$language"
  xcrun simctl spawn "$udid" defaults write -g AppleLocale "$region"
  xcrun simctl shutdown "$udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance light
  # Right after a boot, rotating and enrolling Face ID can be ignored.
  sleep 8
  # An enrolled face, so the Private scene's Face ID request shows its scanning UI and waits there.
  xcrun simctl spawn "$udid" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
  xcrun simctl spawn "$udid" notifyutil -p com.apple.BiometricKit.enrollmentChanged
  [[ $slug == duo ]] && argent run fold --udid "$udid" --posture open >/dev/null
  [[ $slug == duo-cover ]] && argent run fold --udid "$udid" --posture closed >/dev/null
  [[ -n $orientation ]] && argent run rotate --udid "$udid" --orientation "$orientation" >/dev/null
  # Check the iPad really turned: its screenshot should be wider than tall.
  if [[ $slug == ipad ]]; then
    local probe=$(mktemp -t rotate).png
    for _ in {1..5}; do
      xcrun simctl io "$udid" screenshot --type=png "$probe" >/dev/null 2>&1
      local size=($(sips -g pixelWidth -g pixelHeight "$probe" | awk '/pixel/ { print $2 }'))
      (( size[1] > size[2] )) && break
      sleep 3
      argent run rotate --udid "$udid" --orientation "$orientation" >/dev/null
    done
    rm -f "$probe"
  fi
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode active --cellularBars 4 --dataNetwork wifi
}

# Prints the normalized frame "x y w h" of the first on-screen element whose id or label is $1
# (and, with $2, whose id is $2).
frame_of() {
  argent run describe --udid "$udid" 2>/dev/null | python3 -c '
import json, re, sys
for line in json.load(sys.stdin)["description"].splitlines():
    m = re.search(r"\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)", line)
    if m and (f"id=\"{sys.argv[1]}\"" in line or f" \"{sys.argv[1]}\"" in line) and (not sys.argv[2] or f"id=\"{sys.argv[2]}\"" in line):
        print(*m.groups()); break' "$1" "${2:-}"
}

tap() {
  local frame=($(frame_of "$1"))
  [[ -z $frame ]] && { echo "no $1 on screen" >&2; return 1; }
  argent run gesture-tap --udid "$udid" --x $(( frame[1] + frame[3] / 2 )) --y $(( frame[2] + frame[4] / 2 )) >/dev/null
}

# Safari on that locale's Wikipedia page (banner=none keeps fundraising and app banners off it),
# with its share sheet open. Safari keeps the button in
# its page menu on iPhone and in the toolbar on iPad.
share_sheet() {
  xcrun simctl terminate "$udid" com.apple.mobilesafari 2>/dev/null || true
  # One tab, not every page earlier runs opened.
  rm -f ~/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Safari/SafariTabs.db*
  xcrun simctl launch "$udid" com.apple.mobilesafari >/dev/null
  sleep 3
  # Opening a URL right after a boot can time out; one retry is enough.
  xcrun simctl openurl "$udid" "https://$wl.wikipedia.org/wiki/$wt?banner=none" 2>/dev/null ||
    { sleep 5; xcrun simctl openurl "$udid" "https://$wl.wikipedia.org/wiki/$wt?banner=none"; }
  sleep 10
  if [[ -n $(frame_of ShareButton) ]]; then tap ShareButton; else tap MoreMenuButton && sleep 1.5 && tap ShareButton; fi || true
  local cell=()
  for _ in {1..10}; do
    cell=($(frame_of Attention))
    [[ -n $cell ]] && break
    sleep 1
  done
  # Let the sheet finish appearing, then read where the cell came to rest.
  sleep 2
  save_frame Attention shareCell "$OUT/$lang/$slug-2-share.json"
}

# Writes the frame of element $1 (with id $2) to $3 as JSON, in the screenshot's axes.
save_frame() {
  local frame=($(frame_of "$1" "$2"))
  [[ -z $frame ]] && { echo "no $1 on $slug/$lang" >&2; frame=(0 0 0 0); }
  # The iPad's frames are in its portrait axes; its screenshot is rotated to landscape.
  [[ $slug == ipad ]] && frame=($frame[2] $(( 1 - frame[1] - frame[3] )) $frame[4] $frame[3])
  printf '{"x": %.4f, "y": %.4f, "width": %.4f, "height": %.4f}\n' $frame > "$3"
}

# The Duo's active panel, which simctl doesn't capture once the device has been folded.
screenshot() {
  if [[ $slug == duo* ]]; then
    local saved=$(argent run screenshot --udid "$udid" --scale 1 --includeImageInContext false 2>/dev/null | sed -n 's/^Saved screenshot: //p')
    cp "$saved" "$1"
  else
    xcrun simctl io "$udid" screenshot --type=png "$1" >/dev/null 2>&1
  fi
}

for device in $devices; do
  IFS='|' read -r name type slug orientation <<< "$device"
  [[ -n $DEVICES && " $DEVICES " != *" $slug "* ]] && continue
  udid=$(xcrun simctl list devices | sed -n "s/^ *$name (\([0-9A-F-]*\)).*/\1/p" | head -1)
  [[ -z $udid ]] && udid=$(xcrun simctl create "$name" "$type")

  for locale in $locales; do
    IFS='|' read -r lang language region cc wl tagnames <<< "$locale"
    [[ -n $ONLY && " $ONLY " != *" $lang "* ]] && continue
    prepare "$language" "$region"
    IFS=',' read -r music travel work <<< "$tagnames"
    library=${${(j: :)links}//\{cc\}/$cc}
    library=${library//\{wl\}/$wl}
    case $wl in
      ko) wt=%EA%B8%88%EB%AC%B8%EA%B5%90 ;;
      ru) wt="%D0%97%D0%BE%D0%BB%D0%BE%D1%82%D1%8B%D0%B5_%D0%92%D0%BE%D1%80%D0%BE%D1%82%D0%B0_(%D0%BC%D0%BE%D1%81%D1%82)" ;;
      *) wt=Golden_Gate_Bridge ;;
    esac
    library=${library//\{wt\}/$wt}
    tags="1=$music;2=$travel;4=$travel;3=$work;6=$work"
    hidden=$(seq -s ' ' 18 29)
    mkdir -p "$OUT/$lang"
    for scene in $scenes; do
      IFS='|' read -r label extra <<< "$scene"
      [[ -n $SCENES && " $SCENES " != *" $label "* ]] && continue
      # A fresh install per scene so each one starts from the same library.
      xcrun simctl uninstall "$udid" $BUNDLE 2>/dev/null || true
      xcrun simctl install "$udid" "$APP"
      args=(-AppleLanguages "($language)" -AppleLocale "$region" -seenShareGuide YES)
      args+=(-demoLinks "$library" -demoTags "$tags" -demoPrivate "$hidden")
      args+=(${(s: :)extra})
      if [[ $label == 2-share ]]; then
        share_sheet
      else
        # Private is shot in Dark Mode, to match its dark page.
        xcrun simctl ui "$udid" appearance $([[ $label == 4-private ]] && echo dark || echo light)
        xcrun simctl launch "$udid" $BUNDLE "${args[@]}" >/dev/null
        # Unfurling the whole library takes a while on a fresh install; the app writes demo-ready
        # once it's done. Then give the screen a moment to settle.
        documents="$(xcrun simctl get_app_container "$udid" $BUNDLE data)/Documents"
        for _ in {1..120}; do [[ -f $documents/demo-ready ]] && break; sleep 1; done
        [[ -f $documents/demo-ready ]] || echo "library not ready on $slug/$lang/$label" >&2
        sleep ${WAIT:-4}
        if [[ $label == 4-private ]]; then
          # Face ID is still scanning; the simulator leaves its glyph out, so the frame script draws
          # it above the "Face ID" label, whose frame goes next to the screenshot.
          for _ in {1..15}; do [[ -n $(frame_of "Face ID") ]] && break; sleep 1; done
          sleep 1
          save_frame "Face ID" "" "$OUT/$lang/$slug-4-private.json"
        fi
        # The card preview, which the frame script lifts out of the detail screen.
        if [[ $label == 3-detail ]]; then save_frame CardPreview CardPreview "$OUT/$lang/$slug-3-detail.json"; fi
      fi
      screenshot "$OUT/$lang/$slug-$label.png"
      echo "captured $lang/$slug-$label"
    done
  done
  xcrun simctl terminate "$udid" $BUNDLE 2>/dev/null || true
done
