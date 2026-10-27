#!/bin/zsh
# Xcode Cloud runs this before each xcodebuild action. Archives take Xcode Cloud's build
# number, so every upload is unique without committing a bump. Set the starting number in
# App Store Connect (Xcode Cloud → Settings → Build Number) above the last manual upload.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ${CI_XCODEBUILD_ACTION:-} == archive && -n ${CI_BUILD_NUMBER:-} ]]; then
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[^;]*;/\1$CI_BUILD_NUMBER;/" Attention.xcodeproj/project.pbxproj
  echo "Build number set to $CI_BUILD_NUMBER"
fi
