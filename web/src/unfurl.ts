/**
 Link previews for the home page's live demo: a port of the iOS app's `Unfurler`, `OpenGraph`,
 `LinkKind` and `cleanedForSharing` (ios/Shared/Unfurler.swift, Model.swift). Keep them in step.

 Images aren't hotlinked: the result points at /api/image with a signature, so the page can read
 their pixels for the card color and the proxy can't be used for arbitrary URLs.
*/
import qrcode from "qrcode-generator";

export type LinkKind = "youtube" | "bilibili" | "x" | "web";

export type Unfurled = {
  url: string;
  shareURL: string;
  displayURL: string;
  kind: LinkKind;
  site: string;
  /** Empty when no preview could be read; the page then shows the QR template, like the app. */
  title: string;
  author?: string;
  handle?: string;
  /** Proxied, signed image URLs. */
  image?: string;
  icon?: string;
  /** The share URL as a QR code: an SVG path in a `size` × `size` grid. */
  qr: { size: number; path: string };
};

export class UnfurlError extends Error {}

const trackingParameters = new Set([
  "fbclid", "gclid", "igsh", "igshid", "si", "ref_src", "ref_url",
  "spm_id_from", "from_spmid", "vd_source", "unique_k",
  "share_source", "share_medium", "share_plat", "share_session_id", "share_tag", "share_times",
]);

export function linkKind(url: URL): LinkKind {
  const host = url.hostname.toLowerCase();
  const matches = (domain: string) => host === domain || host.endsWith(`.${domain}`);
  if (matches("youtube.com") || host === "youtu.be") return "youtube";
  if (matches("bilibili.com") || host === "b23.tv") return "bilibili";
  if (matches("x.com") || matches("twitter.com")) return "x";
  return "web";
}

function youTubeID(url: URL): string | undefined {
  const parts = url.pathname.split("/").filter(Boolean);
  if (url.hostname.toLowerCase() === "youtu.be") return parts[0];
  if (parts.length > 1 && ["shorts", "live", "embed"].includes(parts[0]!)) return parts[1];
  return url.searchParams.get("v") ?? undefined;
}

export function cleanedForSharing(url: URL): URL {
  const clean = new URL(url);
  switch (linkKind(url)) {
    case "youtube": {
      const id = youTubeID(url);
      return id ? new URL(`https://youtu.be/${id}`) : clean;
    }
    case "x":
      clean.search = "";
      clean.hash = "";
      return clean;
    default:
      for (const name of [...clean.searchParams.keys()]) {
        const lower = name.toLowerCase();
        if (lower.startsWith("utm_") || trackingParameters.has(lower)) clean.searchParams.delete(name);
      }
      return clean;
  }
}

export function displayURL(url: URL): string {
  const host = url.hostname.replace(/^www\./, "");
  const path = decodeURIComponent(url.pathname);
  return path === "/" ? host : host + path;
}

export function siteName(url: URL): string {
  switch (linkKind(url)) {
    case "youtube": return "YouTube";
    case "bilibili": return "哔哩哔哩";
    case "x": return "X";
    case "web": return url.hostname.toLowerCase().replace(/^www\./, "");
  }
}

/** Only public web addresses: no IPs, local names, odd ports or credentials. */
export function checkTarget(raw: string): URL {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    throw new UnfurlError("not_a_url");
  }
  if (url.protocol === "http:") url.protocol = "https:";
  const host = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" || url.username || url.password || url.port ||
    !host.includes(".") || /^[\d.]+$/.test(host) || host.startsWith("[") ||
    /(^|\.)(localhost|local|internal|lan|home|arpa)$/.test(host)
  ) {
    throw new UnfurlError("not_a_url");
  }
  return url;
}

const browserAgent =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
const blockedTitles = ["安全验证", "验证码", "Sina Visitor System", "出错啦", "Just a moment", "Access Denied", "Attention Required"];
const blockedHosts = ["sec.", "passport.", "captcha", "verify", "login."];

async function get(url: string, init: RequestInit = {}): Promise<Response> {
  const response = await fetch(url, {
    ...init,
    redirect: "follow",
    signal: AbortSignal.timeout(8000),
    headers: { "User-Agent": browserAgent, "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8", ...init.headers },
  });
  if (!response.ok) throw new UnfurlError("fetch_failed");
  return response;
}

async function json(url: string): Promise<Record<string, unknown>> {
  // Like the app's URLSession default: Bilibili's API answers a browser user agent with "request was banned".
  return (await (await get(url, { headers: { Accept: "application/json", "User-Agent": "Attention/1.0" } })).json()) as Record<string, unknown>;
}

/** At most `limit` bytes of a body, so a huge page can't run the Worker out of memory. */
async function readPrefix(response: Response, limit: number): Promise<Uint8Array> {
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (total < limit) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.byteLength;
  }
  await reader.cancel().catch(() => {});
  const bytes = new Uint8Array(Math.min(total, limit));
  let offset = 0;
  for (const chunk of chunks) {
    const part = chunk.subarray(0, bytes.length - offset);
    bytes.set(part, offset);
    offset += part.length;
    if (offset >= bytes.length) break;
  }
  return bytes;
}

// MARK: - Open Graph, as in OpenGraph (Unfurler.swift)

const attributePattern = /([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;

function attributes(tag: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const match of tag.matchAll(attributePattern)) result[match[1]!.toLowerCase()] = match[2] ?? match[3] ?? "";
  return result;
}

export function decodeEntities(value: string): string {
  if (!value.includes("&")) return value;
  return value
    .replace(/&#(x?)([0-9a-fA-F]+);/g, (_, hex: string, digits: string) => {
      const code = parseInt(digits, hex ? 16 : 10);
      return Number.isFinite(code) && code <= 0x10ffff ? String.fromCodePoint(code) : "";
    })
    .replaceAll("&quot;", '"').replaceAll("&#39;", "'").replaceAll("&lt;", "<").replaceAll("&gt;", ">")
    .replaceAll("&nbsp;", " ").replaceAll("&amp;", "&");
}

export function metaTags(html: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [tag] of html.matchAll(/<meta\b[^>]*>/gi)) {
    const a = attributes(tag);
    const key = (a.property ?? a.name)?.toLowerCase();
    if (key && a.content && !(key in result)) result[key] = decodeEntities(a.content);
  }
  return result;
}

/** apple-touch-icon first, then the largest rel=icon; SVGs are skipped. */
export function declaredIcon(html: string): string | undefined {
  let best: { score: number; href: string } | undefined;
  for (const [tag] of html.matchAll(/<link\b[^>]*>/gi)) {
    const a = attributes(tag);
    const rel = a.rel?.toLowerCase();
    const href = a.href;
    if (!rel || !href || href.toLowerCase().endsWith(".svg")) continue;
    const size = Number.parseInt(a.sizes?.toLowerCase().split("x")[0] ?? "", 10) || 0;
    let score: number;
    if (rel.includes("apple-touch-icon")) score = 10_000 + size;
    else if (rel.split(/\s+/).includes("icon")) score = size;
    else continue;
    if (score > (best?.score ?? -1)) best = { score, href: decodeEntities(href) };
  }
  return best?.href;
}

export function removingSiteSuffix(site: string, title: string): string {
  for (const separator of [" - ", " | ", " – ", " — ", "_"]) {
    if (title.endsWith(separator + site)) {
      const trimmed = title.slice(0, -(separator.length + site.length)).trim();
      return trimmed || title;
    }
  }
  return title;
}

function decodeHTML(bytes: Uint8Array, contentType: string): string {
  const head = new TextDecoder("utf-8").decode(bytes.subarray(0, 4096));
  const charset = (contentType.match(/charset=([\w-]+)/i)?.[1] ?? head.match(/<meta[^>]+charset=["']?([\w-]+)/i)?.[1] ?? "utf-8").toLowerCase();
  try {
    return new TextDecoder(charset).decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

// MARK: - Sources

type Found = { site: string; title: string; author?: string; handle?: string; image?: string; icon?: string };

async function youtube(url: URL): Promise<Found> {
  const api = new URL("https://www.youtube.com/oembed");
  api.searchParams.set("url", url.href);
  api.searchParams.set("format", "json");
  const j = await json(api.href);
  const title = typeof j.title === "string" ? j.title : "";
  if (!title) throw new UnfurlError("no_preview");
  const id = youTubeID(url);
  // maxresdefault is 1280 × 720 but missing for some videos; hqdefault is 4:3 with black bars.
  let image = j.thumbnail_url as string | undefined;
  if (id) {
    const maxres = `https://i.ytimg.com/vi/${id}/maxresdefault.jpg`;
    image = await get(maxres, { method: "HEAD" }).then(() => maxres, () => image);
  }
  return {
    site: "YouTube",
    title,
    author: typeof j.author_name === "string" ? j.author_name : undefined,
    image,
  };
}

async function twitter(url: URL): Promise<Found> {
  const tweet = (await json(`https://api.fxtwitter.com${url.pathname}`)).tweet as Record<string, any> | undefined;
  if (!tweet) throw new UnfurlError("no_preview");
  const author = (tweet.author ?? {}) as Record<string, any>;
  const photo = tweet.media?.photos?.[0]?.url as string | undefined;
  const video = tweet.media?.videos?.[0]?.thumbnail_url as string | undefined;
  const name = author.name as string | undefined;
  const handle = author.screen_name as string | undefined;
  const text = (tweet.text as string | undefined) ?? "";
  return {
    site: "X",
    title: text || `Post by ${name ?? handle ?? "X"}`,
    author: name,
    handle,
    image: photo ?? video,
  };
}

async function bilibili(url: URL): Promise<Found> {
  let resolved = url;
  if (url.hostname === "b23.tv") resolved = new URL((await get(url.href, { method: "HEAD" })).url);
  const id = resolved.pathname.split("/").find((part) => part.startsWith("BV") || part.toLowerCase().startsWith("av"));
  if (!id) throw new UnfurlError("no_preview");
  const query = id.startsWith("BV") ? `bvid=${id}` : `aid=${id.slice(2)}`;
  const j = await json(`https://api.bilibili.com/x/web-interface/view?${query}`);
  const data = j.data as Record<string, any> | undefined;
  if (j.code !== 0 || !data?.title) throw new UnfurlError("no_preview");
  return {
    site: "哔哩哔哩",
    title: data.title,
    author: data.owner?.name,
    image: (data.pic as string | undefined)?.replace(/^http:\/\//, "https://"),
  };
}

async function page(url: URL): Promise<Found> {
  const response = await get(url.href);
  const type = response.headers.get("Content-Type") ?? "";
  if (type && !type.includes("html")) throw new UnfurlError("no_preview");
  const finalURL = new URL(response.url || url.href);
  if (blockedHosts.some((part) => finalURL.hostname.toLowerCase().includes(part))) throw new UnfurlError("blocked");
  const html = decodeHTML(await readPrefix(response, 512 * 1024), type);
  const tags = metaTags(html);
  const rawTitle = (tags["og:title"] ?? tags["twitter:title"] ?? decodeEntities(html.match(/<title[^>]*>([^<]*)<\/title>/i)?.[1] ?? "")).trim();
  if (!rawTitle || blockedTitles.some((blocked) => rawTitle.includes(blocked))) throw new UnfurlError("no_preview");
  const og = tags["og:site_name"];
  const site = og && [...og].length <= 12 ? og : siteName(url);
  const resolve = (value?: string) => {
    if (!value) return undefined;
    try {
      return new URL(value, finalURL).href;
    } catch {
      return undefined;
    }
  };
  return {
    site,
    title: removingSiteSuffix(site, rawTitle),
    image: resolve(tags["og:image:secure_url"] ?? tags["og:image"] ?? tags["twitter:image"] ?? tags["twitter:image:src"]),
    icon: resolve(declaredIcon(html)),
  };
}

function iconHost(url: URL): string {
  switch (linkKind(url)) {
    case "youtube": return "www.youtube.com";
    case "bilibili": return "www.bilibili.com";
    case "x": return "x.com";
    case "web": return url.hostname;
  }
}

export function qrPath(text: string): { size: number; path: string } {
  const code = qrcode(0, "M");
  code.addData(text, "Byte");
  code.make();
  const size = code.getModuleCount();
  let path = "";
  for (let row = 0; row < size; row++) {
    for (let col = 0; col < size; col++) {
      if (code.isDark(row, col)) path += `M${col} ${row}h1v1h-1z`;
    }
  }
  return { size, path };
}

/** Never throws for an unreadable page: like the app, it returns an empty title and the QR template. */
export async function unfurl(url: URL, signImage: (url: string) => Promise<string>): Promise<Unfurled> {
  const kind = linkKind(url);
  let found: Found | undefined;
  const sources: ((url: URL) => Promise<Found>)[] =
    kind === "youtube" ? [youtube, page] : kind === "x" ? [twitter] : kind === "bilibili" ? [bilibili, page] : [page];
  for (const source of sources) {
    try {
      found = await source(url);
      break;
    } catch {
      // Try the next source.
    }
  }
  const share = cleanedForSharing(url);
  const icon = found?.icon ?? `https://www.google.com/s2/favicons?domain=${iconHost(url)}&sz=128`;
  return {
    url: url.href,
    shareURL: share.href,
    displayURL: displayURL(share),
    kind,
    site: found?.site ?? siteName(url),
    title: found?.title ?? "",
    ...(found?.author ? { author: found.author } : {}),
    ...(found?.handle ? { handle: found.handle } : {}),
    ...(found?.image ? { image: await signImage(found.image) } : {}),
    icon: await signImage(icon),
    qr: qrPath(share.href),
  };
}
