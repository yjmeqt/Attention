#!/bin/zsh
# Release helper built on the asc CLI (https://github.com/rorkai/App-Store-Connect-CLI).
#
#   Tools/release.sh beta [--group NAME] [--notes TEXT] [--no-upload]
#       Bumps CURRENT_PROJECT_VERSION to the next free build number, archives Release,
#       exports an IPA and uploads it to TestFlight. --group adds the build to that beta
#       group once processed; --notes sets What to Test (en-US). --no-upload stops after
#       the IPA, keeping the local build number.
#
#   Tools/release.sh metadata [--apply]
#       Pushes fastlane/metadata (listing text) and fastlane/screenshots to the App Store
#       version matching MARKETING_VERSION. Without --apply it only prints the plan.
#
# Needs an App Store Connect API key stored once with `asc auth login`.
set -euo pipefail
SELF=${0:A}
cd "${SELF:h}/.."

APP_ID=6827156660
SCHEME=Attention
OUT=../build/release
FASTLANE=fastlane
# App Store Connect is sometimes slower than asc's default request timeout.
export ASC_TIMEOUT=${ASC_TIMEOUT:-90s}
# Screenshot file prefix|asc device type: iPhone 1320x2868 (6.9") and 1206x2622 (6.3"), iPad 2752x2064 (13"),
# and iPhone Duo, whose one set holds the inner (duo-*, 2007x2853) and then the outer (duo-cover-*,
# 1398x2034) display. IPHONE_DUO needs asc 5.12 or later.
SCREENSHOT_SETS=("iphone|IPHONE_69" "iphone63|IPHONE_61" "ipad|IPAD_PRO_3GEN_129" "duo|IPHONE_DUO")

die() { print -u2 "error: $*"; exit 1 }
step() { print -P "%F{cyan}==>%f $*" }

setting() { sed -nE "s/^ *$1: \"?([^\"]*)\"?$/\1/p" project.yml | head -1 }

require_auth() {
  command -v asc >/dev/null || die "asc not found; install with: brew install asc"
  asc auth status --output json 2>/dev/null | jq -e '(.credentials | length) > 0 or .environmentCredentialsComplete' >/dev/null \
    || die "no App Store Connect API key; run: asc auth login"
}

beta() {
  local group="" notes="" upload=1
  while (( $# )); do
    case $1 in
      --group) group=$2; shift 2 ;;
      --notes) notes=$2; shift 2 ;;
      --no-upload) upload=0; shift ;;
      *) die "unknown beta option: $1" ;;
    esac
  done
  (( upload )) && require_auth

  local version=$(setting MARKETING_VERSION) build=$(setting CURRENT_PROJECT_VERSION)
  if (( upload )); then
    # Next free build number on App Store Connect, never lower than the local one + 1.
    local remote=$(asc builds next-build-number --app $APP_ID --version $version --platform IOS --output json | jq -r '.nextBuildNumber')
    [[ $remote == <-> ]] || die "could not read next build number from App Store Connect"
    build=$(( remote > build + 1 ? remote : build + 1 ))
    step "Build $version ($build)"
    sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: ).*/\1\"$build\"/" project.yml
  fi
  xcodegen generate --quiet

  local name=$SCHEME-$version-$build
  local archive=$OUT/$name.xcarchive ipa=$OUT/$name.ipa
  mkdir -p $OUT

  step "Archive"
  asc xcode archive --project Attention.xcodeproj --scheme $SCHEME --configuration Release \
    --archive-path $archive --overwrite --output table \
    --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS \
    --xcodebuild-flag=-allowProvisioningUpdates

  step "Export IPA"
  asc xcode export --archive-path $archive --ipa-path $ipa --overwrite --output table \
    --xcodebuild-flag=-allowProvisioningUpdates

  if (( ! upload )); then
    step "IPA at ${ipa:A} (not uploaded)"
    return
  fi

  step "Upload to TestFlight (waits for processing)"
  local args=(--app $APP_ID --ipa $ipa --version $version --build-number $build --wait --output table)
  if [[ -n $group ]]; then args+=(--group $group --notify); else args+=(--upload-only); fi
  [[ -n $notes ]] && args+=(--test-notes $notes --locale en-US)
  asc publish testflight $args

  step "Done. Commit the build number bump:"
  print "  git commit -am \"Build $version ($build)\""
}

metadata() {
  local apply=0
  while (( $# )); do
    case $1 in
      --apply) apply=1; shift ;;
      *) die "unknown metadata option: $1" ;;
    esac
  done
  require_auth

  step "Validate fastlane metadata"
  asc migrate validate --fastlane-dir $FASTLANE --output json | jq -e '.valid' >/dev/null \
    || { asc migrate validate --fastlane-dir $FASTLANE --pretty; die "metadata is invalid" }
  local f empty=()
  for f in $FASTLANE/metadata/*/(support|privacy)_url.txt; do [[ -n ${"$(<$f)"//[[:space:]]/} ]] || empty+=(${f#$FASTLANE/metadata/}); done
  (( ${#empty} )) && print -P "%F{yellow}warning:%f empty URL files (App Review needs them): $empty"

  local version=$(setting MARKETING_VERSION)
  local version_id=$(asc versions list --app $APP_ID --platform IOS --version $version --output json | jq -r '.data[0].id // empty')
  [[ -n $version_id ]] || die "no App Store version $version in App Store Connect; create it there first"

  step "Listing text for $version"
  local mode=(--dry-run); (( apply )) && mode=(--confirm)
  asc migrate import --app $APP_ID --version-id $version_id --fastlane-dir $FASTLANE \
    --skip-screenshots $mode --output table

  step "Screenshots"
  local localizations=$(asc localizations list --version $version_id --paginate --output json)
  local dir locale loc_id set prefix type staging
  for dir in $FASTLANE/screenshots/*(/); do
    locale=${dir:t}
    loc_id=$(jq -r --arg l $locale '.data[] | select(.attributes.locale == $l) | .id' <<< $localizations)
    if [[ -z $loc_id ]]; then
      print -P "%F{yellow}skip $locale:%f no version localization yet (run with --apply to create it from the text)"
      continue
    fi
    for set in $SCREENSHOT_SETS; do
      prefix=${set%%|*} type=${set##*|}
      staging=$OUT/screenshots/$locale/$prefix
      rm -rf $staging && mkdir -p $staging
      cp $dir/$prefix-*.png $staging/ 2>/dev/null || continue
      print "  $locale $type: $(ls $staging | wc -l | tr -d ' ') files"
      if (( apply )); then
        asc screenshots upload --version-localization $loc_id --path $staging --device-type $type \
          --replace --confirm --output table
      else
        asc screenshots upload --version-localization $loc_id --path $staging --device-type $type \
          --replace --dry-run --output table
      fi
    done
  done

  (( apply )) || step "Plan only. Re-run with --apply to push."
}

case ${1:-} in
  beta) shift; beta "$@" ;;
  metadata) shift; metadata "$@" ;;
  *) sed -n '2,13p' $SELF | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
