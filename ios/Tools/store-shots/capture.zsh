#!/bin/zsh
# Captures the raw app screens for the App Store screenshots from dedicated simulators, using the Debug-only
# demo launch arguments (demoLinks, demoPrivate, demoOpen, demoSearch, demoUnlockPrivate; see DemoLibrary.swift).
# The share scene is Safari's own share sheet, with Attention in its app row. Rotating, folding, tapping and the
# Duo's screenshots need the argent CLI (npm i -g @swmansion/argent).
#   zsh Tools/store-shots/capture.zsh
#   DEVICES="ipad duo" ONLY="en-US ko" SCENES="share search" limit the run; NO_BUILD=1 reuses the last build.
# Output: fastlane/raw/<locale>/<device>-<scene>.png, plus fastlane/raw/zh-Hans/iphone-detail.json, the frame of
# the card that export.js lifts out of the detail screen for the Chinese comparison screenshot.
# Every locale but zh-Hans: feed, share, private, search, detail. zh-Hans: detail, share, template, search.
set -uo pipefail
cd "$(dirname "$0")/../.."

DERIVED=../build/store-shots
APP=$DERIVED/Build/Products/Debug-iphonesimulator/Attention.app
BUNDLE=com.yjmeqt.attn.dev
OUT=fastlane/raw

# The Debug build is named Attention Dev; the share sheet should say Attention.
if [[ -z ${NO_BUILD:-} ]]; then
  xcodebuild -project Attention.xcodeproj -scheme Attention -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath $DERIVED APP_DISPLAY_NAME=Attention build -quiet || exit 1
fi

# name|device type|slug|orientation. iPad is shot in landscape, where the detail page puts the card beside its
# controls. Duo is unfolded, where LandscapeLeft gives a portrait UI on the inner display; duo-cover is the same
# simulator folded shut, on its outer display.
devices=(
  "Attention-Shots-iPhone|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max|iphone|Portrait"
  "Attention-Shots-iPad|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB|ipad|LandscapeLeft"
  "Attention-Shots-Duo|com.apple.CoreSimulator.SimDeviceType.iPhone-Duo|duo|LandscapeLeft"
  "Attention-Shots-Duo|com.apple.CoreSimulator.SimDeviceType.iPhone-Duo|duo-cover|Portrait"
)
# fastlane locale|app language|region|Wikipedia language|Bauhaus article title|apple.com region path|App Store storefront.
# Russian uses the US storefront: Apple Music and App Store pages for ru don't preview. es-MX reuses es-ES.
locales=(
  "en-US|en|en_US|en|Bauhaus||us"
  "zh-Hans|zh-Hans|zh_CN|zh|%E5%8C%85%E8%B1%AA%E6%96%AF|cn/|cn"
  "zh-Hant|zh-Hant|zh_TW|zh|%E5%8C%85%E8%B1%AA%E6%96%AF|tw/|tw"
  "ko|ko|ko_KR|ko|%EB%B0%94%EC%9A%B0%ED%95%98%EC%9A%B0%EC%8A%A4|kr/|kr"
  "ja|ja|ja_JP|ja|%E3%83%90%E3%82%A6%E3%83%8F%E3%82%A6%E3%82%B9|jp/|jp"
  "ru|ru|ru_RU|ru|%D0%91%D0%B0%D1%83%D1%85%D0%B0%D1%83%D1%81||us"
  "vi|vi|vi_VN|vi|Bauhaus||vn"
  "ar-SA|ar|ar_SA|ar|%D8%A8%D8%A7%D9%88%D9%87%D8%A7%D9%88%D8%B3||sa"
  "fr-FR|fr|fr_FR|fr|Bauhaus|fr/|fr"
  "de-DE|de|de_DE|de|Bauhaus|de/|de"
  "es-ES|es|es_ES|es|Bauhaus|es/|es"
)
DEVICES=${DEVICES:-}
ONLY=${ONLY:-}
SCENES=${SCENES:-}
want() { [[ -z $SCENES || " $SCENES " == *" $1 "* ]] }
log() { print "[$slug] $*" }

# Boots the simulator in that language: the share sheet is drawn by the system, so the whole device has to switch,
# not just the app.
prepare() {
  local language=$1 region=$2
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null
  xcrun simctl spawn $udid defaults write -g AppleLanguages -array "$language"
  xcrun simctl spawn $udid defaults write -g AppleLocale "$region"
  xcrun simctl shutdown $udid
  xcrun simctl boot $udid
  xcrun simctl bootstatus $udid -b >/dev/null
  xcrun simctl ui $udid appearance light
  # Right after a boot, rotating and enrolling Face ID can be ignored.
  sleep 8
  # An enrolled face, so the Private scene's Face ID request can be matched.
  xcrun simctl spawn $udid notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
  xcrun simctl spawn $udid notifyutil -p com.apple.BiometricKit.enrollmentChanged
  # A link on the clipboard would show the home screen's "You copied a link" banner.
  print -n "" | xcrun simctl pbcopy $udid
  [[ $slug == duo ]] && argent run fold --udid $udid --posture open >/dev/null
  [[ $slug == duo-cover ]] && argent run fold --udid $udid --posture closed >/dev/null
  argent run rotate --udid $udid --orientation $orientation >/dev/null
  sleep 2
  # The rotate can be dropped; check the iPad really turned, its screenshot wider than tall.
  if [[ $slug == ipad ]]; then
    local probe=$(mktemp -t rotate).png size
    for _ in {1..5}; do
      xcrun simctl io $udid screenshot --type=png $probe >/dev/null 2>&1
      size=($(sips -g pixelWidth -g pixelHeight $probe | awk '/pixel/ { print $2 }'))
      (( size[1] > size[2] )) && break
      log "not landscape yet, rotating again"
      sleep 3; argent run rotate --udid $udid --orientation $orientation >/dev/null; sleep 2
    done
    rm -f $probe
  fi
  xcrun simctl status_bar $udid override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode active --cellularBars 4 --dataNetwork wifi
}

# The describe tree, one element per line.
tree() { argent run describe --udid $udid 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["description"])' }

# The normalized frame "x y w h" of the first element whose id or label is $1.
frame_of() {
  tree | python3 -c '
import re, sys
for line in sys.stdin:
    m = re.search(r"\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)", line)
    if m and (f"id=\"{sys.argv[1]}\"" in line or f" \"{sys.argv[1]}\"" in line):
        print(*m.groups()); break' "$1"
}

tap() {
  local f=($(frame_of "$1"))
  [[ -n $f ]] || return 1
  argent run gesture-tap --udid $udid --x $(( f[1] + f[3] / 2 )) --y $(( f[2] + f[4] / 2 )) >/dev/null
}

# The Duo's active panel, which simctl doesn't capture once the device has been folded.
shoot() {
  if [[ $slug == duo* ]]; then
    local saved=$(argent run screenshot --udid $udid --scale 1 --includeImageInContext false 2>/dev/null | sed -n 's/^Saved screenshot: //p')
    cp "$saved" "$1"
  else
    xcrun simctl io $udid screenshot --type=png "$1" >/dev/null 2>&1
  fi
}

# A fresh install filled with the demo library, so each scene starts from the same one. The app writes demo-ready
# once the library has unfurled; one retry when it doesn't, which happens on the first launch after a boot.
launch() {
  local try docs
  for try in 1 2; do
    xcrun simctl terminate $udid com.apple.mobilesafari 2>/dev/null
    xcrun simctl uninstall $udid $BUNDLE 2>/dev/null
    xcrun simctl install $udid $APP
    xcrun simctl launch $udid $BUNDLE -AppleLanguages "($language)" -AppleLocale $region -seenShareGuide YES \
      -demoLinks "$library" "$@" >/dev/null
    docs="$(xcrun simctl get_app_container $udid $BUNDLE data)/Documents"
    for _ in {1..90}; do [[ -f $docs/demo-ready ]] && break; sleep 1; done
    [[ -f $docs/demo-ready ]] && break
    log "library not ready ($lang, try $try)"
  done
  sleep 5
}

# Safari on a page in that locale, with its share sheet open. Safari keeps the button in its page menu on iPhone and
# in the toolbar on iPad.
share_sheet() {
  # Other locales share their Wikipedia page (banner=none keeps fundraising and app banners off it). Chinese
  # Wikipedia shows a sitenotice about a mainland Telegram group, so Traditional Chinese shares Apple's Swift page
  # (Apple Taiwan's store pages show prices and a country banner). Simplified Chinese shares the YouTube video, its
  # pitch, except on large screens, whose desktop YouTube page has a sidebar full of faces.
  local page="https://$wl.wikipedia.org/$wp/$wt?banner=none" try
  [[ $lang == zh-Hant ]] && page="https://developer.apple.com/swift/"
  if [[ $lang == zh-Hans ]]; then
    page="https://m.youtube.com/watch?v=aircAruvnKk"
    [[ $slug == ipad || $slug == duo ]] && page="https://developer.apple.com/cn/swift/"
  fi
  # Safari sometimes opens its page menu or start page instead; start over until Attention's cell is in the sheet.
  for try in 1 2 3; do
    xcrun simctl terminate $udid $BUNDLE 2>/dev/null
    xcrun simctl terminate $udid com.apple.mobilesafari 2>/dev/null
    # One tab, not every page earlier runs opened.
    rm -f ~/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Safari/SafariTabs.db*
    sleep 1
    xcrun simctl launch $udid com.apple.mobilesafari >/dev/null
    sleep 4
    # Opening a URL right after a boot can time out; one retry is enough.
    xcrun simctl openurl $udid "$page" 2>/dev/null || { sleep 5; xcrun simctl openurl $udid "$page"; }
    sleep 12
    if [[ -n $(frame_of ShareButton) ]]; then tap ShareButton; else tap MoreMenuButton && sleep 1.5 && tap ShareButton; fi
    for _ in {1..10}; do tree | grep -q 'id="shareCell"' && break; sleep 1; done
    tree | grep -q 'AXButton "Attention" id="shareCell"' && break
    log "no share sheet ($lang, try $try)"
  done
  # The page thumbnail in the sheet's header loads last.
  sleep 8
}

for device in $devices; do
  IFS='|' read -r name type slug orientation <<< "$device"
  [[ -n $DEVICES && " $DEVICES " != *" $slug "* ]] && continue
  udid=$(xcrun simctl list devices | sed -n "s/^ *$name (\([0-9A-F-]*\)).*/\1/p" | head -1)
  [[ -z $udid ]] && udid=$(xcrun simctl create "$name" "$type")

  for entry in $locales; do
    IFS='|' read -r lang language region wl wt ar cc <<< "$entry"
    [[ -n $ONLY && " $ONLY " != *" $lang "* ]] && continue
    dev=""; [[ $ar == (cn|jp|kr)/ ]] && dev=$ar
    # Chinese Wikipedia picks its script from the path: zh-tw is Traditional.
    wp=wiki; [[ $lang == zh-Hant ]] && wp=zh-tw
    log "locale $lang"
    prepare $language $region
    mkdir -p $OUT/$lang
    if [[ $lang == zh-Hans ]]; then
      # The Chinese set shows the YouTube card (its pitch) and search results; the rest are Apple's Chinese pages.
      library="https://www.youtube.com/watch?v=aircAruvnKk https://www.apple.com/cn/newsroom/ https://developer.apple.com/cn/swift/ https://apps.apple.com/cn/app/keynote/id361285480 https://www.apple.com.cn/iphone/ https://developer.apple.com/cn/design/human-interface-guidelines/"
    else
      # Apple and Wikipedia pages only, so no third-party content shows outside the Chinese set.
      library="https://$wl.wikipedia.org/$wp/$wt https://www.apple.com/${ar}iphone/ https://music.apple.com/$cc/station/apple-music-1/ra.978194965 https://maps.apple.com/place?address=Apple%20Park&coordinate=37.334922,-122.009033&name=Apple%20Park https://apps.apple.com/$cc/app/keynote/id361285480 https://developer.apple.com/${dev}swift/ https://podcasts.apple.com/$cc/browse https://developer.apple.com/design/human-interface-guidelines/"
    fi
    if [[ $lang != zh-Hans ]] && want feed; then
      launch; shoot $OUT/$lang/$slug-feed.png; log "feed"
    fi
    want search && { launch -demoSearch Apple; shoot $OUT/$lang/$slug-search.png; log "search"; }
    if want detail || want template; then
      launch -demoOpen 0; shoot $OUT/$lang/$slug-detail.png; log "detail"
      if [[ $lang == zh-Hans && $slug == iphone ]]; then
        f=($(frame_of CardPreview))
        [[ -n $f ]] && printf '{"x": %.4f, "y": %.4f, "width": %.4f, "height": %.4f}\n' $f > $OUT/$lang/$slug-detail.json \
          || log "no CardPreview"
      fi
    fi
    if [[ $lang == zh-Hans ]] && want template; then
      tap "文字" && sleep 3 && shoot $OUT/$lang/$slug-template.png && log "template" || log "no Text template"
    elif [[ $lang != zh-Hans ]] && want private; then
      launch -demoPrivate "0 1 2 3 4 5 6 7" -demoUnlockPrivate YES
      for _ in {1..15}; do [[ -n $(frame_of "Face ID") ]] && break; sleep 1; done
      for _ in {1..6}; do xcrun simctl spawn $udid notifyutil -p com.apple.BiometricKit_Sim.pearl.match; sleep 1; done
      sleep 3
      # Unlocked cards carry a lock icon too, so look for the prompt instead.
      [[ -n $(frame_of "Face ID") ]] && log "Face ID prompt still up ($lang)"
      shoot $OUT/$lang/$slug-private.png; log "private"
    fi
    # Last, so no app launch after it shows a "◂ Safari" back link in the status bar.
    want share && { share_sheet; shoot $OUT/$lang/$slug-share.png; log "share"; }
  done
  xcrun simctl terminate $udid $BUNDLE 2>/dev/null
  xcrun simctl terminate $udid com.apple.mobilesafari 2>/dev/null
done
