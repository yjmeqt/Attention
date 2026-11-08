#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h:h}"
cd "$repo_root"

# Every URL is a real page with an OG image, checked on 2026-11-08.
links=(
  'https://science.nasa.gov/earth/earth-observatory/taking-a-gander-at-utahs-goosenecks/'
  'https://science.nasa.gov/blog/mars-has-its-charmes/'
  'https://science.nasa.gov/missions/maven/nasas-maven-illuminates-new-understanding-of-auroras-at-mars/'
  'https://science.nasa.gov/earth/earth-observatory/image-of-the-day/'
  'https://github.com/swiftlang/swift'
  'https://github.com/pointfreeco/swift-composable-architecture'
  'https://github.com/apple/swift-argument-parser'
  'https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/'
)

xc-dev run
sim_id="$(xc-dev :get sim_id)"
bundle_id="$(xc-dev :get bundle_id)"
xcrun simctl launch --terminate-running-process "$sim_id" "$bundle_id" \
  -demoRealLinks YES -demoLinks "${(j: :)links}" \
  -demoSearch '我一共有多少 NASA 链接？' -seenShareGuide YES
