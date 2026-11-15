# Attention web

The website and the shared-list service, as one Cloudflare Worker at https://attentioncard.com. Static files in `public/` (home, `/privacy`, `/support`, with headers from `public/_headers`) are served as is; the Worker handles `/api/*` and `/l/*`. The design is in [`docs/list-sharing.md`](../docs/list-sharing.md).

```sh
npm install
npm run dev          # http://127.0.0.1:8787, with a local R2 bucket in .wrangler/
npm test             # Vitest inside the Workers runtime
npm run typecheck
npm run types        # regenerate worker-configuration.d.ts after changing wrangler.jsonc
```

## API

| Route | |
|---|---|
| `POST /api/lists` | `multipart/form-data`. Part `list` is the snapshot JSON; a link item's `thumb` names the part holding its JPEG (≤ 100 KB). Optional part `preview`: the list's link preview image, a 16:9 JPEG 600–1200 px wide, ≤ 150 KB (see docs/list-sharing.md). 201 `{ id, url, deleteToken }` |
| `GET /api/lists/:id` | The whole list as JSON, for the app; thumbnails as absolute URLs. 410 `revoked`/`removed`, 404 `not_found` |
| `GET /.well-known/apple-app-site-association` | Universal links for `/l/*`, on attentioncard.com and open.attentioncard.com |
| `GET /l/:id/og.jpg` | The list's link preview image, when the app sent one; otherwise the page points at `/img/og-list-<lang>.png` |
| `DELETE /api/lists/:id` | `Authorization: Bearer <deleteToken>`. 204, also when already revoked |
| `GET /l/:id` | The list page: the first 5 items and a "View in Attention" button to `https://open.attentioncard.com/l/:id`, which opens the app, or the App Store when it isn't installed. 404 if it never existed, 410 once revoked |
| `GET /l/:id/:n.jpg` | Thumbnail of item `n` |

Errors are JSON `{ error, message? }`: `invalid_form`, `invalid_list`, `invalid_thumb` (400), `missing_token` (401), `wrong_token` (403), `not_found` (404), `too_large`, `thumb_too_large` (413), `rate_limited` (429, 3 uploads per IP per minute), `invalid_preview` (400 or 413), `daily_limit` (429, site-wide uploads per UTC day reached), `uploads_disabled` (503). Thumbnails after the first 20 items are ignored.

```sh
curl -X POST http://127.0.0.1:8787/api/lists \
  -F 'list={"v":1,"title":"Weekend","lang":"en","items":[{"kind":"link","url":"https://youtu.be/abc","title":"A video","site":"YouTube","thumb":"t0"}]}' \
  -F 't0=@cover.jpg;type=image/jpeg'
```

## Removing a reported list

```sh
npm run takedown -- https://attentioncard.com/l/<id>   # or just the id
```

It deletes the list and its thumbnails from R2 with your `wrangler login` session, and the page then says the list was removed (410). Reports arrive at report@attentioncard.com.

## Reading mail

Mail to support@ and report@attentioncard.com isn't forwarded: Email Routing hands it to this Worker (`email` handler in `src/mail.ts`), which stores each message as an `.eml` file in the private `attention-mail` bucket. Up to 200 messages a day and 10 MB each; more are bounced.

```sh
npm run mail              # newest 30: date, address, sender, subject
npm run mail -- all       # every message
npm run mail -- 3         # save message 3 to ~/Downloads/attention-mail/; double-click it to open in Mail
```

Answer from your own mailbox. Delete old messages in the dashboard's R2 page.

## Cost limits

Workers stays on the free plan, where going over the limits fails requests rather than billing. R2 bills by use with no cap, so uploads are bounded in `wrangler.jsonc`:

- `DAILY_UPLOAD_LIMIT` (default 500): uploads per UTC day across the whole site, counted by the `UploadQuota` Durable Object.
- `UPLOADS_ENABLED`: set to `"false"` and `npm run deploy` to stop new uploads at once. Shared lists stay readable.
- `ATTEST_MODE`: App Attest on uploads (`src/attest.ts`). `"log"` records whether each upload's assertion checks out (`wrangler tail` shows `{"attest":"upload",...}`), `"require"` refuses uploads without a valid one, `"off"` skips the check. Switch to `"require"` once builds with App Attest are out and real-device uploads log `valid`. `node scripts/attest-fixture.mjs` remakes the test chain in `test/fixtures/attest.json`.

## Deploying

The Worker serves only `attentioncard.com` (no `workers.dev` or preview URLs). R2 has to be enabled on the account in the dashboard first.

```sh
npx wrangler r2 bucket create attention-lists
npm run deploy
```

Deploying attaches the custom domain and creates its DNS record and certificate.
