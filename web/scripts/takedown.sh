#!/bin/sh
# Removes a shared list from production, for reports of abuse.
#   npm run takedown -- <list id or https://attentioncard.com/l/<id>>
# The page then answers 410 "removed" instead of the sharer's "revoked".
# Uses your `wrangler login` session; nothing to configure.
set -eu

id=$(printf '%s' "${1:-}" | sed -E 's#^https?://[^/]+/l/##; s#[/?].*$##')
if ! printf '%s' "$id" | grep -Eq '^[0-9A-Za-z]{10}$'; then
  echo "usage: npm run takedown -- <list id or URL>" >&2
  exit 64
fi

cd "$(dirname "$0")/.."
bucket=attention-lists
r2() { npx wrangler r2 object "$@" --remote >/dev/null; }

if ! list=$(npx wrangler r2 object get "$bucket/lists/$id/list.json" --remote --pipe 2>/dev/null); then
  echo "No list $id (already revoked or removed?)" >&2
  exit 1
fi

# Mark it first, so the page never shows "not found" in between.
printf '{"reason":"takedown","at":"%s"}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" |
  npx wrangler r2 object put "$bucket/revoked/$id" --remote --pipe --content-type application/json >/dev/null

# Thumbnails exist only for items stored with "thumb": true.
for index in $(printf '%s' "$list" | node -e '
  const list = JSON.parse(require("fs").readFileSync(0, "utf8"));
  list.items.forEach((item, i) => { if (item.thumb) console.log(i); });'); do
  r2 delete "$bucket/lists/$id/$index.jpg"
done
r2 delete "$bucket/lists/$id/og.jpg"
r2 delete "$bucket/lists/$id/list.json"

echo "Removed https://attentioncard.com/l/$id"
echo "Cached copies expire within an hour (thumbnails) or a minute (the page)."
