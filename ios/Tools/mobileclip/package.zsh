#!/bin/zsh
# Downloads MobileCLIP-S0 from Hugging Face, compiles the Core ML packages, packs them with
# the CLIP tokenizer vocab into an Apple Archive, prints the SHA-256, and optionally uploads
# the archive to the GitHub release `mobileclip-s0-v1` on yjmeqt/Attention.
#
# Usage:
#   ios/Tools/mobileclip/package.zsh           # build into /tmp/mobileclip-s0
#   ios/Tools/mobileclip/package.zsh --upload  # also create/upload the release asset
#
# If local DNS hijacks huggingface.co, set HF_IP to a real address (Cloudflare DoH is used
# automatically when HF_IP is unset). Or point HF_ENDPOINT at a working mirror.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${MOBILECLIP_OUT:-/tmp/mobileclip-s0}
STAGE=$OUT/stage
ARCHIVE=$OUT/mobileclip-s0.aar
HF_ENDPOINT=${HF_ENDPOINT:-https://huggingface.co}
HF=$HF_ENDPOINT/apple/coreml-mobileclip/resolve/main
HF_API=$HF_ENDPOINT/api/models/apple/coreml-mobileclip
REPO=yjmeqt/Attention
TAG=mobileclip-s0-v1

mkdir -p "$OUT" "$STAGE"
cd "$OUT"

# curl flags that pin huggingface.co to a real IP when DNS is wrong.
hf_curl() {
  local extra=()
  if [[ "$HF_ENDPOINT" == https://huggingface.co* ]]; then
    if [ -z "${HF_IP:-}" ]; then
      HF_IP=$(curl -fsSL --max-time 15 "https://cloudflare-dns.com/dns-query?name=huggingface.co&type=A" \
        -H "accept: application/dns-json" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['Answer'][0]['data'])")
      export HF_IP
      echo "Using huggingface.co → $HF_IP (DoH)"
    fi
    extra=(--resolve "huggingface.co:443:$HF_IP")
  fi
  curl -fsSL --retry 5 --retry-delay 2 "${extra[@]}" "$@"
}

download_mlpackage() {
  local name=$1
  local dest="${OUT}/${name}.mlpackage"
  if [ -d "${dest}/Data" ]; then
    echo "Already have ${name}.mlpackage"
    return
  fi
  echo "Downloading ${name}.mlpackage → ${dest}"
  local tree
  tree=$(mktemp)
  hf_curl "${HF_API}/tree/main/${name}.mlpackage?recursive=1" -o "$tree"
  HF_IP="${HF_IP:-}" python3 - "$HF" "$name" "$dest" "$tree" <<'PY'
import json, os, sys, subprocess
from pathlib import Path
hf, name, dest, tree = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
ip = os.environ.get("HF_IP", "")
prefix = f"{name}.mlpackage/"
dest_root = Path(dest)
entries = json.load(open(tree))
for e in entries:
    if e["type"] != "file":
        continue
    full = e["path"]
    rel = full[len(prefix):] if full.startswith(prefix) else full.split("/", 1)[-1]
    path = dest_root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    url = f"{hf}/{full}"
    print(" ", rel, flush=True)
    cmd = ["curl", "-fsSL", "--retry", "5", "--retry-delay", "2"]
    if ip and "huggingface.co" in url:
        cmd += ["--resolve", f"huggingface.co:443:{ip}"]
    cmd += [url, "-o", str(path)]
    subprocess.check_call(cmd)
PY
  rm -f "$tree"
}

download_mlpackage mobileclip_s0_image
download_mlpackage mobileclip_s0_text

echo "Compiling Core ML models…"
rm -rf "${STAGE}/mobileclip_s0_image.mlmodelc" "${STAGE}/mobileclip_s0_text.mlmodelc"
xcrun coremlcompiler compile "${OUT}/mobileclip_s0_image.mlpackage" "$STAGE"
xcrun coremlcompiler compile "${OUT}/mobileclip_s0_text.mlpackage" "$STAGE"
ls -la "$STAGE"

echo "Copying tokenizer vocab…"
if [ -f /tmp/mobileclip/clip-vocab.json ]; then
  cp /tmp/mobileclip/clip-vocab.json /tmp/mobileclip/clip-merges.txt "$STAGE/"
else
  curl -fsSL https://raw.githubusercontent.com/apple/ml-mobileclip/main/ios_app/MobileCLIPExplore/Resources/clip-vocab.json -o "$STAGE/clip-vocab.json"
  curl -fsSL https://raw.githubusercontent.com/apple/ml-mobileclip/main/ios_app/MobileCLIPExplore/Resources/clip-merges.txt -o "$STAGE/clip-merges.txt"
fi
cp "$ROOT/ios/Shared/Search/ACKNOWLEDGEMENTS" "$STAGE/ACKNOWLEDGEMENTS" 2>/dev/null || true

echo "Archiving…"
rm -f "$ARCHIVE"
(
  cd "$STAGE"
  aa archive -d . -o "$ARCHIVE" -a lzfse -enable-dedup
)

SHA=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
SIZE=$(du -h "$ARCHIVE" | awk '{print $1}')
echo "Archive: $ARCHIVE ($SIZE)"
echo "SHA-256: $SHA"

SWIFT="$ROOT/ios/Shared/Search/ClipModel.swift"
if grep -q 'archiveSHA256 =' "$SWIFT"; then
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
