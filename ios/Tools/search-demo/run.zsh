#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h:h}"
cd "$repo_root"
xc-dev run
sim_id="$(xc-dev :get sim_id)"
bundle_id="$(xc-dev :get bundle_id)"
xcrun simctl launch --terminate-running-process "$sim_id" "$bundle_id" \
  -demoSearchCorpus YES -seenShareGuide YES
