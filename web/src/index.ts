import { listIDPattern, newDeleteToken, newListID, sameHash, sha256 } from "./ids";
import { goneResponse, listPage, notFoundResponse, platformOf, readerLang, removedResponse, type Lang } from "./page";
import { receiveMail } from "./mail";
import { checkTarget, unfurl, UnfurlError } from "./unfurl";
import { homeLang, homePage, homePaths, type HomeLang } from "./home";
import { checkPreview, jpegSize } from "./listPreview";
import { appAttestRootPEM } from "./appAttestRoot";
import { AttestError, checkChallenge, fromBase64, newChallenge, uploadClientDataHash, verifyAssertion, verifyAttestation, type AttestedKey } from "./attest";
export { UploadQuota } from "./quota";
import { InvalidSnapshot, isJPEG, limits, parseSnapshot, type Snapshot } from "./snapshot";

/*
 R2 layout:
   lists/<id>/list.json   the snapshot; custom metadata `tokenHash` is the SHA-256 of the delete token
   lists/<id>/<n>.jpg     thumbnail of item n
   lists/<id>/og.jpg      link preview image the app rendered, when it sent one (src/listPreview.ts)
   attest/<key id>        an App Attest key's public key and counter (src/attest.ts), base64url key ID
   revoked/<id>           left behind by a delete, so the page can say "revoked" instead of "not found".
                          JSON `{ reason, at }`: reason "owner" for the sharer's delete, "takedown" for
                          the developer's removal (scripts/takedown.sh).
*/
const listKey = (id: string) => `lists/${id}/list.json`;
const thumbKey = (id: string, index: number) => `lists/${id}/${index}.jpg`;
const previewKey = (id: string) => `lists/${id}/og.jpg`;
const revokedKey = (id: string) => `revoked/${id}`;

/** Added to every response the Worker makes; public/_headers covers the static pages. */
const securityHeaders: Record<string, string> = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
};

export default {
  async fetch(request, env): Promise<Response> {
    // A copy, because responses from the cache have read-only headers.
    const routed = await route(request, env);
    const response = new Response(routed.body, routed);
    for (const [name, value] of Object.entries(securityHeaders)) {
      if (!response.headers.has(name)) response.headers.set(name, value);
    }
    return response;
  },

  email(message, env) {
    return receiveMail(message, env);
  },
} satisfies ExportedHandler<Env>;

/**
 Universal links: shared lists open in the app when it's installed. Both hosts serve this file;
 the app's Associated Domains entitlement names them (ios/App/Attention.entitlements).
 Thumbnails and preview images under /l/<id>/ stay on the web.
*/
const appSiteAssociation = {
  applinks: {
    details: [
      {
        appIDs: ["M3V5P234X3.com.yjmeqt.attn", "M3V5P234X3.com.yjmeqt.attn.dev"],
        components: [
          { "/": "/l/*/*", exclude: true, comment: "List images" },
          { "/": "/l/*", comment: "Shared lists" },
        ],
      },
    ],
  },
};

const appStoreURL = "https://apps.apple.com/app/id6827156660";

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;

  if (path === "/.well-known/apple-app-site-association") {
    return Response.json(appSiteAssociation, { headers: { "Cache-Control": "public, max-age=3600" } });
  }
  // open.<host> exists only to be a universal link from list pages. Reaching it in a browser means
  // the app isn't installed (or the browser doesn't hand links to apps, like WeChat's).
  if (url.hostname === env.OPEN_HOST) {
    if (/^\/l\/[0-9A-Za-z]{10}\/?$/.test(path)) {
      // Only Apple devices can install Attention; anyone else goes back to the list page.
      const apple = platformOf(request.headers.get("User-Agent") ?? "") === "apple";
      return Response.redirect(apple ? appStoreURL : `https://${url.hostname.replace(/^open\./, "")}${path.replace(/\/$/, "")}`, 302);
    }
    return Response.redirect(`https://${url.hostname.replace(/^open\./, "")}${path}`, 302);
  }

  if (path === "/api/lists") {
    if (request.method !== "POST") return methodNotAllowed("POST");
    return createList(request, env, url);
  }
  if (path === "/api/attest/challenge") {
    if (request.method !== "GET") return methodNotAllowed("GET");
    return Response.json({ challenge: await newChallenge(env.IMAGE_KEY) }, { headers: { "Cache-Control": "no-store" } });
  }
  if (path === "/api/attest") {
    if (request.method !== "POST") return methodNotAllowed("POST");
    return attestKey(request, env);
  }
  let match = path.match(/^\/api\/lists\/([^/]+)$/);
  if (match) {
    if (request.method === "GET") return listJSON(env, url, match[1]!);
    if (request.method !== "DELETE") return methodNotAllowed("GET, DELETE");
    return deleteList(request, env, match[1]!);
  }
  if (path === "/api/unfurl" || path === "/api/image") {
    if (request.method !== "GET") return methodNotAllowed("GET");
    return path === "/api/unfurl" ? previewLink(request, env, url) : proxyImage(request, env, url);
  }
  if (path.startsWith("/api/")) return error(404, "not_found");

  if (request.method !== "GET" && request.method !== "HEAD") return methodNotAllowed("GET, HEAD");
  if (path === "/") {
    const country = (request.cf as { country?: string } | undefined)?.country;
    return homePage(homeLang(request.headers.get("Accept-Language"), country), url.origin);
  }
  const home = (Object.entries(homePaths) as [HomeLang, string][]).find(([, homePath]) => path === homePath || path === `${homePath}/`);
  if (home) return homePage(home[0], url.origin);
  match = path.match(/^\/l\/([^/]+)\/?$/);
  if (match) return showList(request, env, url, match[1]!, readerLang(request.headers.get("Accept-Language")));
  match = path.match(/^\/l\/([^/]+)\/(\d{1,3}|og)\.jpg$/);
  if (match) return showImage(env, match[1]!, match[2] === "og" ? previewKey(match[1]!) : thumbKey(match[1]!, Number(match[2])));
  return notFoundResponse(readerLang(request.headers.get("Accept-Language")));
}

async function createList(request: Request, env: Env, url: URL): Promise<Response> {
  if (env.UPLOADS_ENABLED !== "true") return error(503, "uploads_disabled");
  const ip = request.headers.get("CF-Connecting-IP") ?? "local";
  if (env.UPLOAD_LIMITER && !(await env.UPLOAD_LIMITER.limit({ key: ip })).success) {
    return error(429, "rate_limited");
  }
  const declared = Number(request.headers.get("Content-Length") ?? 0);
  if (declared > limits.requestBytes) return error(413, "too_large");
  const body = await request.arrayBuffer();
  if (body.byteLength > limits.requestBytes) return error(413, "too_large");

  let form: FormData;
  try {
    form = await new Response(body, { headers: request.headers }).formData();
  } catch {
    return error(400, "invalid_form", "Send multipart/form-data with a `list` part.");
  }
  const listPart = form.get("list");
  if (listPart === null) return error(400, "invalid_list", "The `list` part is missing.");

  let snapshot: Snapshot;
  const json = typeof listPart === "string" ? listPart : await listPart.text();
  try {
    snapshot = parseSnapshot(JSON.parse(json), new Date());
  } catch (e) {
    if (e instanceof InvalidSnapshot) return error(400, "invalid_list", e.message);
    if (e instanceof SyntaxError) return error(400, "invalid_list", "The `list` part is not JSON.");
    throw e;
  }

  // Check every thumbnail before writing anything.
  const thumbs: { index: number; bytes: Uint8Array }[] = [];
  for (const [index, item] of snapshot.items.entries()) {
    if (item.kind !== "link") continue;
    if (typeof item.thumb !== "string" || index >= limits.thumbItems) {
      delete item.thumb;
      delete item.tint;
      continue;
    }
    const part = form.get(item.thumb);
    if (part === null || typeof part === "string") {
      return error(400, "invalid_thumb", `Part \`${item.thumb}\` for items[${index}] is missing.`);
    }
    const bytes = new Uint8Array(await part.arrayBuffer());
    if (bytes.byteLength > limits.thumbBytes) return error(413, "thumb_too_large", `items[${index}]`);
    if (!isJPEG(bytes)) return error(400, "invalid_thumb", `items[${index}] is not a JPEG.`);
    thumbs.push({ index, bytes });
    item.thumb = true;
  }

  // Optional: the app's rendering of the list for link previews.
  const previewPart = form.get("preview");
  let preview: Uint8Array | undefined;
  if (previewPart !== null) {
    if (typeof previewPart === "string") return error(400, "invalid_preview", "The `preview` part must be a file.");
    preview = new Uint8Array(await previewPart.arrayBuffer());
    const problem = checkPreview(preview);
    if (problem) return error(problem.status, "invalid_preview", problem.message);
    snapshot.og = jpegSize(preview)!;
  }

  const attested = await checkUploadAttestation(request, env, new TextEncoder().encode(json));
  if (attested) return attested;

  // Counted only once the upload is valid, right before anything is written.
  const quota = env.UPLOAD_QUOTA.get(env.UPLOAD_QUOTA.idFromName("global"));
  if (!(await quota.take(Number(env.DAILY_UPLOAD_LIMIT) || 0))) return error(429, "daily_limit");

  const id = newListID();
  const deleteToken = newDeleteToken();
  await Promise.all([
    ...thumbs.map(({ index, bytes }) =>
      env.LISTS.put(thumbKey(id, index), bytes, { httpMetadata: { contentType: "image/jpeg" } }),
    ),
    ...(preview ? [env.LISTS.put(previewKey(id), preview, { httpMetadata: { contentType: "image/jpeg" } })] : []),
  ]);
  // Written last: a list exists once its list.json does.
  await env.LISTS.put(listKey(id), JSON.stringify(snapshot), {
    httpMetadata: { contentType: "application/json" },
    customMetadata: { tokenHash: await sha256(deleteToken) },
  });

  return Response.json({ id, url: `${url.origin}/l/${id}`, deleteToken }, { status: 201 });
}

async function deleteList(request: Request, env: Env, id: string): Promise<Response> {
  if (!listIDPattern.test(id)) return error(404, "not_found");
  const token = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!token) return error(401, "missing_token");

  const head = await env.LISTS.head(listKey(id));
  if (!head) {
    // Deleting twice is fine; deleting something that never existed isn't.
    return (await env.LISTS.head(revokedKey(id))) ? new Response(null, { status: 204 }) : error(404, "not_found");
  }
  if (!sameHash(await sha256(token), head.customMetadata?.tokenHash ?? "")) return error(403, "wrong_token");

  await env.LISTS.put(revokedKey(id), JSON.stringify({ reason: "owner", at: new Date().toISOString() }));
  let cursor: string | undefined;
  do {
    const page = await env.LISTS.list({ prefix: `lists/${id}/`, cursor });
    if (page.objects.length > 0) await env.LISTS.delete(page.objects.map((object) => object.key));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return new Response(null, { status: 204 });
}

async function showList(request: Request, env: Env, url: URL, id: string, lang: Lang): Promise<Response> {
  if (!listIDPattern.test(id)) return notFoundResponse(lang);
  const object = await env.LISTS.get(listKey(id));
  if (!object) {
    const revoked = await env.LISTS.get(revokedKey(id));
    if (!revoked) return notFoundResponse(lang);
    const reason = await revoked.json<{ reason?: string }>().then((value) => value.reason, () => "owner");
    return reason === "takedown" ? removedResponse(lang) : goneResponse(lang);
  }
  const snapshot = await object.json<Snapshot>();
  return listPage(snapshot, {
    id,
    origin: url.origin,
    reportURL: env.REPORT_URL,
    openURL: `https://${env.OPEN_HOST}/l/${id}`,
    inWeChat: /MicroMessenger/i.test(request.headers.get("User-Agent") ?? ""),
    platform: platformOf(request.headers.get("User-Agent") ?? ""),
  });
}

/** The whole list for the app, with absolute image URLs. */
async function listJSON(env: Env, url: URL, id: string): Promise<Response> {
  if (!listIDPattern.test(id)) return error(404, "not_found");
  const object = await env.LISTS.get(listKey(id));
  if (!object) {
    const revoked = await env.LISTS.get(revokedKey(id));
    if (!revoked) return error(404, "not_found");
    const reason = await revoked.json<{ reason?: string }>().then((value) => value.reason, () => "owner");
    return error(410, reason === "takedown" ? "removed" : "revoked");
  }
  const snapshot = await object.json<Snapshot>();
  const base = `${url.origin}/l/${id}`;
  return Response.json(
    {
      id,
      url: base,
      title: snapshot.title,
      lang: snapshot.lang,
      createdAt: snapshot.createdAt,
      items: snapshot.items.map((item, index) =>
        item.kind === "link" && item.thumb ? { ...item, thumb: `${base}/${index}.jpg` } : item,
      ),
    },
    { headers: { "Cache-Control": "public, max-age=60" } },
  );
}

async function showImage(env: Env, id: string, key: string): Promise<Response> {
  if (!listIDPattern.test(id)) return new Response(null, { status: 404 });
  const object = await env.LISTS.get(key);
  if (!object) return new Response(null, { status: 404 });
  return new Response(object.body, {
    headers: {
      "Content-Type": "image/jpeg",
      // Not immutable: a revoked list's images should leave caches within the hour.
      "Cache-Control": "public, max-age=3600",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

// MARK: - Live link preview for the home page

async function sign(env: Env, value: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.IMAGE_KEY), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value)));
  return btoa(String.fromCharCode(...mac.subarray(0, 16))).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function signedImageURL(env: Env, imageURL: string): Promise<string> {
  return `/api/image?u=${encodeURIComponent(imageURL)}&s=${await sign(env, imageURL)}`;
}

async function previewLink(request: Request, env: Env, url: URL): Promise<Response> {
  let target: URL;
  try {
    target = checkTarget(url.searchParams.get("url") ?? "");
  } catch {
    return error(400, "not_a_url", "Enter a web address that starts with https://.");
  }
  const cacheKey = new Request(`https://cache.attentioncard.com/unfurl?url=${encodeURIComponent(target.href)}`);
  const cached = await caches.default.match(cacheKey);
  if (cached) return cached;

  const ip = request.headers.get("CF-Connecting-IP") ?? "local";
  if (env.UNFURL_LIMITER && !(await env.UNFURL_LIMITER.limit({ key: ip })).success) return error(429, "rate_limited");

  try {
    const result = await unfurl(target, (imageURL) => signedImageURL(env, imageURL));
    const response = Response.json(result, { headers: { "Cache-Control": "public, max-age=3600" } });
    await caches.default.put(cacheKey, response.clone());
    return response;
  } catch (e) {
    if (e instanceof UnfurlError) return error(400, e.message);
    throw e;
  }
}

const maxImageBytes = 5 * 1024 * 1024;

async function proxyImage(request: Request, env: Env, url: URL): Promise<Response> {
  const imageURL = url.searchParams.get("u") ?? "";
  const signature = url.searchParams.get("s") ?? "";
  if (!imageURL || !sameHash(signature, await sign(env, imageURL))) return error(403, "bad_signature");
  const cached = await caches.default.match(request);
  if (cached) return cached;

  let upstream: Response;
  try {
    upstream = await fetch(imageURL, {
      signal: AbortSignal.timeout(8000),
      headers: { "User-Agent": "Mozilla/5.0 (compatible; AttentionCard/1.0; +https://attentioncard.com)", Accept: "image/*" },
    });
  } catch {
    return error(502, "image_unavailable");
  }
  const type = upstream.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase() ?? "";
  // SVG can carry script, so it's never passed through.
  if (!upstream.ok || !type.startsWith("image/") || type.includes("svg")) return error(502, "image_unavailable");
  if (Number(upstream.headers.get("Content-Length") ?? 0) > maxImageBytes) return error(502, "image_too_large");
  const bytes = await upstream.arrayBuffer();
  if (bytes.byteLength > maxImageBytes) return error(502, "image_too_large");

  const response = new Response(bytes, {
    headers: { "Content-Type": type, "Cache-Control": "public, max-age=86400", "Content-Security-Policy": "default-src 'none'" },
  });
  await caches.default.put(request, response.clone());
  return response;
}

function error(status: number, code: string, message?: string): Response {
  return Response.json({ error: code, ...(message ? { message } : {}) }, { status });
}

function methodNotAllowed(allow: string): Response {
  return new Response(JSON.stringify({ error: "method_not_allowed" }), {
    status: 405,
    headers: { Allow: allow, "Content-Type": "application/json" },
  });
}

// MARK: - App Attest

const attestKeyPath = (keyID: string) => `attest/${keyID.replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "")}`;

/** POST /api/attest { keyId, attestation, challenge } (base64): checks a new key's attestation and keeps it. */
async function attestKey(request: Request, env: Env): Promise<Response> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "local";
  if (env.UPLOAD_LIMITER && !(await env.UPLOAD_LIMITER.limit({ key: `attest:${ip}` })).success) {
    return error(429, "rate_limited");
  }
  let input: { keyId?: unknown; attestation?: unknown; challenge?: unknown };
  try {
    input = await request.json();
  } catch {
    return error(400, "invalid_attestation", "Send JSON.");
  }
  const { keyId, attestation, challenge } = input;
  if (typeof keyId !== "string" || typeof attestation !== "string" || typeof challenge !== "string" || attestation.length > 16_384) {
    return error(400, "invalid_attestation", "keyId, attestation and challenge are required.");
  }
  if (!(await checkChallenge(env.IMAGE_KEY, challenge))) return error(400, "invalid_challenge");
  try {
    const key = await verifyAttestation({
      attestation: fromBase64(attestation),
      keyID: fromBase64(keyId),
      clientDataHash: new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(challenge))),
      rootPEM: appAttestRootPEM,
      now: new Date(),
    });
    await env.LISTS.put(attestKeyPath(key.keyID), JSON.stringify(key), { httpMetadata: { contentType: "application/json" } });
    return new Response(null, { status: 204 });
  } catch (e) {
    if (e instanceof AttestError) {
      console.log(JSON.stringify({ attest: "attestation rejected", reason: e.message }));
      return error(400, "invalid_attestation", e.message);
    }
    throw e;
  }
}

/**
 Checks an upload's assertion. Returns a response to send back when ATTEST_MODE is "require" and it's missing
 or bad; otherwise null, after logging the outcome so "log" mode shows how many uploads would pass.
*/
async function checkUploadAttestation(request: Request, env: Env, listJSON: Uint8Array): Promise<Response | null> {
  const mode = env.ATTEST_MODE as string;
  if (mode === "off") return null;
  const keyID = request.headers.get("X-Attest-Key");
  const challenge = request.headers.get("X-Attest-Challenge");
  const assertion = request.headers.get("X-Attest-Assertion");
  let problem: string | undefined;
  if (!keyID || !challenge || !assertion) {
    problem = "missing";
  } else if (!(await checkChallenge(env.IMAGE_KEY, challenge))) {
    problem = "bad challenge";
  } else {
    const stored = await env.LISTS.get(attestKeyPath(keyID));
    if (!stored) {
      problem = "unknown key";
    } else {
      const key = await stored.json<AttestedKey>();
      try {
        key.counter = await verifyAssertion({
          assertion: fromBase64(assertion),
          key,
          clientDataHash: await uploadClientDataHash(challenge, listJSON),
        });
        await env.LISTS.put(attestKeyPath(keyID), JSON.stringify(key), { httpMetadata: { contentType: "application/json" } });
      } catch (e) {
        if (!(e instanceof AttestError)) throw e;
        problem = e.message;
      }
    }
  }
  console.log(JSON.stringify({ attest: "upload", mode, result: problem ?? "valid" }));
  if (!problem || mode !== "require") return null;
  return problem === "unknown key" ? error(401, "unknown_attest_key") : error(401, "attestation_required", problem);
}
