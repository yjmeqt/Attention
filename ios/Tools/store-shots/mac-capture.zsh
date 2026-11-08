#!/bin/zsh
# xc-dev build-mac-store-shots first. Pass the built .app path, then optional locale codes.
set -euo pipefail
APP=${1:?Pass the Debug Attention.app path}; shift
cd "${0:A:h}/../.."
locales=("$@")
(( ${#locales} )) || locales=(en-US zh-Hans ja ko ru vi ar-SA fr-FR de-DE es-ES es-MX)
ROOT="$HOME/Library/Containers/com.yjmeqt.attn.dev/Data/Documents/MacStoreShots"
for locale in $locales; do
  case $locale in
    en-US) language=en ;; ar-SA) language=ar ;; fr-FR) language=fr ;; de-DE) language=de ;; es-*) language=es ;; *) language=$locale ;;
  esac
  rm -f "$ROOT/$locale/complete" "$ROOT/error.txt"
  "$APP/Contents/MacOS/Attention" -macStoreShots YES -shotLocale "$locale" -AppleLanguages "($language)"
  [[ -f "$ROOT/$locale/complete" ]] || { cat "$ROOT/error.txt" >&2; exit 1; }
  mkdir -p "fastlane/raw/$locale"
  cp "$ROOT/$locale"/mac-*.png "fastlane/raw/$locale/"
  print "Captured $locale"
done
