#!/bin/zsh
# Downloads MobileCLIP-S0 from Hugging Face, compiles the Core ML packages, packs them with
# the CLIP tokenizer vocab into an Apple Archive, prints the SHA-256, and optionally uploads
# the archive to the GitHub release `mobileclip-s0-v1` on yjmeqt/Attention.
#
# Usage:
#   ios/Tools/mobileclip/package.zsh           # build into /tmp/mobileclip-s0
#   ios/Tools/mobileclip/package.zsh --upload  # also create/upload the release asset
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${MOBILECLIP_OUT:-/tmp/mobileclip-s0}
STAGE=$OUT/stage
ARCHIVE=$OUT/mobileclip-s0.aar
HF=https://huggingface.co/apple/coreml-mobileclip/resolve/main
REPO=yjmeqt/Attention
TAG=mobileclip-s0-v1

mkdir -p "$OUT" "$STAGE"
cd "$OUT"

download_mlpackage() {
  local name=$1
  local dest=$OUT/$name.mlpackage
  if [ -d "$dest" ]; then
    echo "Already have $name.mlpackage"
    return
  fi
  echo "Downloading $name.mlpackage…"
  # mlpackage is a directory; fetch the file list then each blob.
  python3 - "$HF" "$name" "$dest" <<'PY'
import json, os, sys, urllib.request
hf, name, dest = sys.argv[1], sys.argv[2], sys.argv[3]
api = f"https://huggingface.co/api/models/apple/coreml-mobileclip/tree/main/{name}.mlpackage?recursive=1"
with urllib.request.urlopen(api) as r:
    entries = json.load(r)
for e in entries:
    if e["type"] != "file":
        continue
    rel = e["path"][len(name)+10:]  # strip "<name>.mlpackage/"
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    url = f"{hf}/{e['path']}"
    print(" ", rel)
    urllib.request.urlretrieve(url, path)
PY
}

download_mlpackage mobileclip_s0_image
download_mlpackage mobileclip_s0_text

echo "Compiling Core ML models…"
xcrun coremlcompiler compile "$OUT/mobileclip_s0_image.mlpackage" "$STAGE"
xcrun coremlcompiler compile "$OUT/mobileclip_s0_text.mlpackage" "$STAGE"

echo "Copying tokenizer vocab…"
cp /tmp/mobileclip/clip-vocab.json "$STAGE/" 2>/dev/null \
  || curl -fsSL https://raw.githubusercontent.com/apple/ml-mobileclip/main/ios_app/MobileCLIPExplore/Resources/clip-vocab.json -o "$STAGE/clip-vocab.json"
cp /tmp/mobileclip/clip-merges.txt "$STAGE/" 2>/dev/null \
  || curl -fsSL https://raw.githubusercontent.com/apple/ml-mobileclip/main/ios_app/MobileCLIPExplore/Resources/clip-merges.txt -o "$STAGE/clip-merges.txt"
cp "$ROOT/ios/Shared/Search/ACKNOWLEDGEMENTS" "$STAGE/ACKNOWLEDGEMENTS" 2>/dev/null || true

echo "Archiving…"
rm -f "$ARCHIVE"
(
  cd "$STAGE"
  aa archive -d . -o "$ARCHIVE" -enable_dedup -enable_compression
)

SHA=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
SIZE=$(du -h "$ARCHIVE" | awk '{print $1}')
echo "Archive: $ARCHIVE ($SIZE)"
echo "SHA-256: $SHA"

SWIFT="$ROOT/ios/Shared/Search/ClipModel.swift"
if grep -q 'REPLACE_AFTER_PACKAGING\|archiveSHA256 =' "$SWIFT"; then
  # Keep REPLACE only until we have a real hash; then write it in.
  perl -pi -e "s/static let archiveSHA256 = \".*\"/static let archiveSHA256 = \"$SHA\"/" "$SWIFT"
  echo "Updated ClipModel.archiveSHA256"
fi

if [ "${1:-}" = "--upload" ]; then
  command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
  if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "$TAG" --repo "$REPO" --title "MobileCLIP-S0" --notes "Compiled MobileCLIP-S0 image and text encoders plus CLIP tokenizer vocab for Attention's on-device visual search. Apple license: see ACKNOWLEDGEMENTS inside the archive."
  fi
  gh release upload "$TAG" "$ARCHIVE" --repo "$REPO" --clobber
  echo "Uploaded to https://github.com/$REPO/releases/tag/$TAG"
fi
