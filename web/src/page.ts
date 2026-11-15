import { qrPath } from "./unfurl";
import { previewLang, templatePath } from "./listPreview";
import type { Item, Snapshot } from "./snapshot";

export type Lang = "zh-Hans" | "zh-Hant" | "en";

/** Where the visitor is: Apple devices can get the app; Android can't; other computers can pass it to a phone. */
export type Platform = "apple" | "android" | "other";

/** iPadOS Safari asks for desktop sites as a Mac, so a Mac user agent may be an iPad: both have the app. */
export function platformOf(userAgent: string): Platform {
  if (/Android/i.test(userAgent)) return "android";
  if (/iPhone|iPad|iPod|Macintosh/i.test(userAgent)) return "apple";
  return "other";
}

const ogLocales: Record<Lang, string> = { "zh-Hans": "zh_CN", "zh-Hant": "zh_TW", en: "en_US" };

const strings = {
  "zh-Hans": {
    moreItems: (n: number) => `还有 ${n} 条，在 Attention 里查看全部`,
    openInApp: "在 Attention 里打开，保存到你的收藏",
    openButton: "在 Attention 中查看",
    installHint: "还没有安装 Attention？会先打开 App Store，装好后回到这里再点一次。",
    appleOnly: "Attention 目前只有 iPhone、iPad 和 Mac 版。在这些设备上打开这个链接，就能看到完整的列表。",
    scanHint: "用 iPhone 的相机扫一扫，在手机上打开这个列表。",
    wechatHint: "在微信里看不到“打开 App”？点右上角的 ··· ，选择“在浏览器中打开”。",
    count: (n: number) => `${n} 条`,
    sharedOn: (date: string) => `分享于 ${date}`,
    madeWith: "用 Attention 分享",
    report: "举报",
    notFound: "没有找到这个列表",
    notFoundDetail: "链接可能不完整，请向分享者确认。",
    gone: "这个列表已被撤回",
    goneDetail: "分享者已经撤回了它。",
    removed: "这个列表已被移除",
    removedDetail: "Attention 已根据举报移除了它。",
    more: "展开全文",
    text: "文字",
  },
  "zh-Hant": {
    moreItems: (n: number) => `還有 ${n} 則，在 Attention 裡查看全部`,
    openInApp: "在 Attention 裡開啟，儲存到你的收藏",
    openButton: "在 Attention 中查看",
    installHint: "還沒有安裝 Attention？會先開啟 App Store，裝好後回到這裡再點一次。",
    appleOnly: "Attention 目前只有 iPhone、iPad 和 Mac 版。在這些裝置上開啟這個連結，就能看到完整的列表。",
    scanHint: "用 iPhone 的相機掃一掃，在手機上開啟這個列表。",
    wechatHint: "在微信裡無法開啟 App？點右上角的 ··· ，選擇「在瀏覽器中開啟」。",
    count: (n: number) => `${n} 則`,
    sharedOn: (date: string) => `分享於 ${date}`,
    madeWith: "用 Attention 分享",
    report: "檢舉",
    notFound: "找不到這個列表",
    notFoundDetail: "連結可能不完整，請向分享者確認。",
    gone: "這個列表已被撤回",
    goneDetail: "分享者已經撤回了它。",
    removed: "這個列表已被移除",
    removedDetail: "Attention 已根據檢舉移除了它。",
    more: "展開全文",
    text: "文字",
  },
  en: {
    moreItems: (n: number) => (n === 1 ? "1 more item. See the whole list in Attention." : `${n} more items. See the whole list in Attention.`),
    openInApp: "Open it in Attention to save it to your library.",
    openButton: "View in Attention",
    installHint: "Don't have Attention yet? This opens the App Store first; once it's installed, come back and tap again.",
    appleOnly: "Attention is on iPhone, iPad and Mac for now. Open this link on one of them to see the whole list.",
    scanHint: "Scan with your iPhone's camera to open the list there.",
    wechatHint: "In WeChat? Tap ··· at the top right and choose Open in Browser to jump to the app.",
    count: (n: number) => (n === 1 ? "1 item" : `${n} items`),
    sharedOn: (date: string) => `Shared ${date}`,
    madeWith: "Shared with Attention",
    report: "Report",
    notFound: "List not found",
    notFoundDetail: "The link may be incomplete. Check with the person who shared it.",
    gone: "This list was revoked",
    goneDetail: "The person who shared it has taken it down.",
    removed: "This list was removed",
    removedDetail: "Attention removed it after a report.",
    more: "Show all",
    text: "Text",
  },
} satisfies Record<Lang, unknown>;

export function pageLang(tag: string): Lang {
  const lower = tag.toLowerCase();
  if (lower.startsWith("zh")) {
    return /hant|-tw|-hk|-mo/.test(lower) ? "zh-Hant" : "zh-Hans";
  }
  return "en";
}

/** The reader's language from Accept-Language, for pages that have no list to take it from. */
export function readerLang(acceptLanguage: string | null): Lang {
  const first = acceptLanguage?.split(",")[0]?.split(";")[0]?.trim();
  return first ? pageLang(first) : "zh-Hans";
}

export function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

const css = `
:root {
  color-scheme: light dark;
  /* The app's colors: iOS system background, secondary background behind tiles, label colors, and the icon's red. */
  --bg: #ffffff; --card: #f2f2f7; --text: #000000; --muted: rgba(60, 60, 67, .6); --line: rgba(60, 60, 67, .12); --accent: #E8402A;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #000000; --card: #1c1c1e; --text: #ffffff; --muted: rgba(235, 235, 245, .6); --line: rgba(84, 84, 88, .4); }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--text);
  font: 16px/1.5 -apple-system, BlinkMacSystemFont, "PingFang SC", "PingFang TC", "Hiragino Sans GB", "Microsoft YaHei", system-ui, sans-serif;
  -webkit-text-size-adjust: 100%;
}
main { max-width: 640px; margin: 0 auto; padding: 32px 16px 48px; }
header { margin-bottom: 20px; }
h1 { font-size: 26px; line-height: 1.25; margin: 0 0 6px; overflow-wrap: anywhere; }
.meta { color: var(--muted); font-size: 14px; margin: 0; }
.feed { display: flex; gap: 12px; align-items: flex-start; }
.lane { flex: 1; min-width: 0; list-style: none; margin: 0; padding: 0; display: grid; gap: 12px; }
li { background: var(--card); border: .5px solid var(--line); border-radius: 16px; overflow: hidden; }
a.link { display: block; color: inherit; text-decoration: none; }
a.link:active { opacity: .7; }
.photo { display: block; width: 100%; object-fit: cover; background: var(--line); }
.body { padding: 10px; }
/* Under a photo, the band takes the photo's bottom-edge color (inline), with text that reads on it, as in the app. */
.body.light { color: #121214; --muted: rgba(18, 18, 20, .6); }
.body.dark { color: #ffffff; --muted: rgba(255, 255, 255, .72); }
.site { color: var(--muted); font-size: 11px; font-weight: 600; letter-spacing: .02em; text-transform: uppercase; margin: 0 0 4px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.title { font-size: 15px; line-height: 1.35; font-weight: 600; margin: 0; display: -webkit-box; -webkit-line-clamp: 6; -webkit-box-orient: vertical; overflow: hidden; overflow-wrap: anywhere; }
.photo + .body .title { -webkit-line-clamp: 3; }
.author { color: var(--muted); font-size: 12px; margin: 6px 0 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.text { padding: 0 10px 10px; margin: 0; font-size: 15px; line-height: 1.35; font-weight: 600; white-space: pre-wrap; overflow-wrap: anywhere; }
.text-site { padding: 10px 10px 0; }
details.text summary { list-style: none; cursor: pointer; }
details.text summary::-webkit-details-marker { display: none; }
details.text[open] summary { display: none; }
.more { color: var(--accent); font-weight: 600; }
footer { margin-top: 32px; display: flex; justify-content: space-between; gap: 16px; color: var(--muted); font-size: 13px; }
footer a { color: inherit; }
footer a.made { display: inline-flex; align-items: center; gap: 6px; }
.in-app { margin-top: 16px; padding: 24px 20px; border-radius: 16px; background: var(--card); color: var(--text); text-align: center; }
.in-app-title { margin: 0 0 16px; font-size: 18px; font-weight: 700; }
a.open { display: inline-flex; align-items: center; gap: 10px; padding: 13px 22px; border-radius: 12px; background: var(--accent); color: #fff; font-weight: 700; text-decoration: none; }
.in-app .hint { margin: 14px 0 0; font-size: 13px; color: var(--muted); }
.in-app .note { margin: 0; font-size: 15px; }
.qr { display: block; width: 148px; height: 148px; margin: 16px auto 0; padding: 10px; background: #fff; border-radius: 12px; }
.empty { text-align: center; padding-top: 25vh; }
`;

function document(lang: Lang, title: string, body: string, head = "", appArgument?: string): string {
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>${escapeHTML(title)}</title>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">
<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
<meta name="apple-itunes-app" content="app-id=6827156660${appArgument ? `, app-argument=${escapeHTML(appArgument)}` : ""}">
${head}<style>${css}</style>
</head>
<body>
${body}
</body>
</html>`;
}

function headers(status: number, cache: string): ResponseInit {
  return {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": cache,
      // Nothing on the page needs script; images come only from this origin.
      "Content-Security-Policy": "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "X-Content-Type-Options": "nosniff",
    },
  };
}

/** Short text items show in full; long ones fold after this many characters, about eight lines of a column. */
const foldAfter = 72;

function itemHTML(item: Item, index: number, id: string, t: { more: string; text: string }): string {
  if (item.kind === "text") {
    const site = `<p class="site text-site">${escapeHTML(t.text)}</p>`;
    const chars = [...item.text];
    if (chars.length <= foldAfter) return `<li>${site}<p class="text">${escapeHTML(item.text)}</p></li>`;
    const short = chars.slice(0, foldAfter).join("").trimEnd();
    return `<li>${site}<details class="text"><summary>${escapeHTML(short)}… <span class="more">${escapeHTML(t.more)}</span></summary>${escapeHTML(item.text)}</details></li>`;
  }
  const host = new URL(item.url).hostname.replace(/^www\./, "");
  const photo = item.thumb
    ? `<img class="photo" src="/l/${id}/${index}.jpg" alt="" loading="lazy" decoding="async" style="aspect-ratio:${photoAspect(item).toFixed(3)}">`
    : "";
  const author = item.author ? `<p class="author">${escapeHTML(item.author)}</p>` : "";
  const band = item.thumb && item.tint ? ` ${isDark(item.tint) ? "dark" : "light"}" style="background:${item.tint}` : "";
  return `<li><a class="link" href="${escapeHTML(item.url)}" rel="noopener noreferrer nofollow ugc">${photo}<div class="body${band}"><p class="site">${escapeHTML(item.site || host)}</p><p class="title">${escapeHTML(item.title || host)}</p>${author}</div></a></li>`;
}

/** Like the app's `CardTint`: dark when the color's luma is under 0.6. `tint` is checked to be #rrggbb. */
function isDark(tint: string): boolean {
  const [r, g, b] = [1, 3, 5].map((start) => parseInt(tint.slice(start, start + 2), 16) / 255);
  return 0.299 * r! + 0.587 * g! + 0.114 * b! < 0.6;
}

/** Width ÷ height the photo shows at; very tall ones are cropped, like the app's tiles. */
function photoAspect(item: Item): number {
  return item.kind === "link" && item.thumb ? Math.max(item.aspect ?? 1.33, 0.5) : 1;
}

/**
 Splits items into columns the way the app's feed does: each goes to the shorter column, by an
 estimated height (a photo by its aspect ratio, text by its length). No script needed on the page.
*/
export function lanes<T extends { item: Item }>(entries: T[], columns: number): T[][] {
  const result: T[][] = Array.from({ length: columns }, () => []);
  const heights = new Array<number>(columns).fill(0);
  for (const entry of entries) {
    const lane = heights.indexOf(Math.min(...heights));
    result[lane]!.push(entry);
    const { item } = entry;
    const photo = item.kind === "link" && item.thumb ? 1 / photoAspect(item) : 0;
    const words = item.kind === "text" ? item.text : item.title || "";
    heights[lane]! += photo + (Math.min([...words].length, 160) / 160) * 0.6 + 0.35;
  }
  return result;
}

/** The web page shows this many items; the whole list is in the app. */
export const previewItems = 5;

export function listPage(
  snapshot: Snapshot,
  context: { id: string; origin: string; reportURL: string; openURL: string; inWeChat: boolean; platform: Platform },
): Response {
  const lang = pageLang(snapshot.lang);
  const t = strings[lang];
  const { id, origin } = context;
  const pageURL = `${origin}/l/${id}`;
  const date = snapshot.createdAt.slice(0, 10);
  const summary = `${t.count(snapshot.items.length)} · Attention`;
  // The list's own preview image when the upload made one, else the template without thumbnails.
  const ogImage = snapshot.og ? `${pageURL}/og.jpg` : `${origin}${templatePath(previewLang(snapshot.lang))}`;
  const ogSize = typeof snapshot.og === "object" ? snapshot.og : { width: 1200, height: 675 };

  const head = [
    `<meta property="og:type" content="website">`,
    `<meta property="og:title" content="${escapeHTML(snapshot.title)}">`,
    `<meta property="og:description" content="${escapeHTML(summary)}">`,
    `<meta property="og:url" content="${escapeHTML(pageURL)}">`,
    `<meta property="og:site_name" content="Attention">`,
    `<meta property="og:locale" content="${ogLocales[lang]}">`,
    `<meta property="og:image" content="${escapeHTML(ogImage)}">`,
    `<meta property="og:image:width" content="${ogSize.width}">`,
    `<meta property="og:image:height" content="${ogSize.height}">`,
    `<meta property="og:image:alt" content="${escapeHTML(snapshot.title)}">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="description" content="${escapeHTML(summary)}">`,
  ]
    .filter(Boolean)
    .map((line) => `${line}\n`)
    .join("");

  const shown = snapshot.items.slice(0, previewItems).map((item, index) => ({ item, index }));
  const items = lanes(shown, 2)
    .map((lane) => `<ol class="lane">\n${lane.map(({ item, index }) => itemHTML(item, index, id, t)).join("\n")}\n</ol>`)
    .join("\n");
  const remaining = snapshot.items.length - previewItems;
  const title = `<p class="in-app-title">${escapeHTML(remaining > 0 ? t.moreItems(remaining) : t.openInApp)}</p>`;
  let action: string;
  if (context.platform === "apple") {
    // open.<host> is a different domain from this page, so iOS opens the app for it when it's installed;
    // otherwise the Worker sends the visitor on to the App Store.
    action = `<a class="open" href="${escapeHTML(context.openURL)}"><img src="/glyph.svg" alt="" width="22" height="22">${escapeHTML(t.openButton)}</a>
<p class="hint">${escapeHTML(context.inWeChat ? t.wechatHint : t.installHint)}</p>`;
  } else if (context.platform === "android") {
    // There's no app to send them to.
    action = `<p class="note">${escapeHTML(t.appleOnly)}</p>`;
  } else {
    // A computer: hand the list to a phone. The camera opens the app if it's there.
    const { size, path } = qrPath(pageURL);
    action = `<p class="note">${escapeHTML(t.appleOnly)}</p>
<svg class="qr" viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges" role="img" aria-label="${escapeHTML(t.scanHint)}"><path d="${path}" fill="#000"/></svg>
<p class="hint">${escapeHTML(t.scanHint)}</p>`;
  }
  const inApp = `<section class="in-app">
${title}
${action}
</section>`;
  const body = `<main>
<header>
<h1>${escapeHTML(snapshot.title)}</h1>
<p class="meta">${escapeHTML(t.count(snapshot.items.length))} · <time datetime="${escapeHTML(snapshot.createdAt)}">${escapeHTML(t.sharedOn(date))}</time></p>
</header>
<div class="feed">
${items}
</div>
${inApp}
<footer><a class="made" href="/"><img src="/glyph.svg" alt="" width="18" height="18">${escapeHTML(t.madeWith)}</a><a href="${escapeHTML(context.reportURL + encodeURIComponent(pageURL))}" rel="nofollow">${escapeHTML(t.report)}</a></footer>
</main>`;
  // Short, so a revoked list stops being served soon.
  // Varies with the visitor's device and WeChat's browser, so it isn't shared between visitors.
  return new Response(document(lang, snapshot.title, body, head, pageURL), headers(200, "private, max-age=60"));
}

function messagePage(lang: Lang, status: number, title: string, detail: string): Response {
  const body = `<main class="empty"><h1>${escapeHTML(title)}</h1><p class="meta">${escapeHTML(detail)}</p><footer style="justify-content:center"><a href="/">Attention</a></footer></main>`;
  return new Response(document(lang, title, body), headers(status, "no-store"));
}

export function notFoundResponse(lang: Lang): Response {
  return messagePage(lang, 404, strings[lang].notFound, strings[lang].notFoundDetail);
}

export function removedResponse(lang: Lang): Response {
  return messagePage(lang, 410, strings[lang].removed, strings[lang].removedDetail);
}

export function goneResponse(lang: Lang): Response {
  return messagePage(lang, 410, strings[lang].gone, strings[lang].goneDetail);
}
