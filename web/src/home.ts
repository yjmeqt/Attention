/**
 The home page at /, /en, /zh and /zh-hant. The live demo is public/home.js; styles are public/home.css.
 "/" picks a language: the browser's preference first, then the visitor's country, then English.
*/
import { escapeHTML } from "./page";
import { qrPath } from "./unfurl";

export type HomeLang = "en" | "zh-Hans" | "zh-Hant";

export const homePaths: Record<HomeLang, string> = { en: "/en", "zh-Hans": "/zh", "zh-Hant": "/zh-hant" };

const appStoreURL = "https://apps.apple.com/app/id6827156660";

/** Bump after `npm run og`: link previews cache images by URL. */
const ogImageVersion = 2;

function chineseVariant(tag: string, country?: string): HomeLang {
  return /hant|-tw|-hk|-mo/.test(tag) || (tag === "zh" && ["TW", "HK", "MO"].includes(country ?? "")) ? "zh-Hant" : "zh-Hans";
}

/** The first Chinese or English entry in Accept-Language wins; otherwise the country decides. */
export function homeLang(acceptLanguage: string | null, country?: string): HomeLang {
  const tags = (acceptLanguage ?? "")
    .split(",")
    .map((part, index) => {
      const [tag = "", ...params] = part.trim().toLowerCase().split(";");
      const q = Number(params.find((p) => p.trim().startsWith("q="))?.split("=")[1] ?? 1);
      return { tag, q: Number.isFinite(q) ? q : 0, index };
    })
    .filter((entry) => entry.tag && entry.q > 0)
    .sort((a, b) => b.q - a.q || a.index - b.index);
  for (const { tag } of tags) {
    if (tag === "zh" || tag.startsWith("zh-")) return chineseVariant(tag, country);
    if (tag === "en" || tag.startsWith("en-")) return "en";
  }
  if (country === "CN") return "zh-Hans";
  if (country === "TW" || country === "HK" || country === "MO") return "zh-Hant";
  return "en";
}

type Strings = {
  htmlLang: string;
  title: string;
  /** Without the brand: link previews show the site name ("Attention") on their own. */
  ogTitle: string;
  description: string;
  heading: string;
  lede: string;
  download: string;
  scanToGet: string;
  wechatTip: string;
  placeholder: string;
  make: string;
  tryLabel: string;
  samples: [label: string, url: string][];
  initial: string;
  wechatShows: string;
  attentionSends: string;
  featuresHeading: string;
  features: [image: string, heading: string, body: string][];
  closingHeading: string;
  closingBody: string;
  support: string;
  privacy: string;
  ogImage: string;
  demo: Record<string, unknown>;
};

const strings: Record<HomeLang, Strings> = {
  en: {
    htmlLang: "en",
    title: "Attention: link cards for WeChat and any chat",
    ogTitle: "Link cards for WeChat and any chat",
    description: "WeChat shows YouTube and X links as a bare URL. Attention turns any link into an image card with its title, cover and a QR code.",
    heading: "Send links people can actually see.",
    lede: "WeChat shows YouTube, X and many other links as a bare URL. Attention turns any link into an image card with its title, cover and a QR code, right on your iPhone.",
    download: "Download on the App Store",
    scanToGet: "Scan with your iPhone<br>to get Attention",
    wechatTip: "If the App Store doesn't open, tap ··· at the top right and choose Open in Browser.",
    placeholder: "Paste a link",
    make: "Make card",
    tryLabel: "Try",
    samples: [
      ["YouTube", "https://www.youtube.com/watch?v=jNQXAC9IVRw"],
      ["X", "https://x.com/jack/status/20"],
      ["Wikipedia", "https://en.wikipedia.org/wiki/Golden_Gate_Bridge"],
      ["GitHub", "https://github.com/"],
    ],
    initial: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
    wechatShows: "What WeChat shows",
    attentionSends: "What Attention sends",
    featuresHeading: "Save it from anywhere. Find it again. Share it so it reads.",
    features: [
      ["share", "Save from any app", "In X, YouTube, Safari or any app, tap Share and pick Attention. Or just paste a link."],
      ["detail", "Share it as a card", "Choose a card, text or QR template. The link is copied too, so it can go along with the image."],
      ["feed", "Find it again", "Filter by site and tag, and search titles and the text inside your images."],
      ["private", "Private when you need it", "Lock items behind Face ID. No account and no tracking: your library syncs only through your own iCloud."],
    ],
    closingHeading: "Get Attention for iPhone, iPad and Mac.",
    closingBody: "Free on the App Store. Your links stay on your devices.",
    support: "Support",
    privacy: "Privacy",
    ogImage: "/img/og-en.jpg",
    demo: {
      madeWith: "Made with Attention",
      reading: "Reading the page…",
      scanToOpen: "Scan the QR code to open",
      noPreview: "No preview available. Scan the QR code or paste the link to open it.",
      chips: { youtube: "YouTube · Video", bilibili: "Bilibili · Video", x: "X · Post" },
      errors: {
        not_a_url: "Enter a web address, like https://youtu.be/…",
        rate_limited: "Too many cards in a minute. Wait a moment and try again.",
        generic: "Couldn't make a card for that link. Try another one.",
      },
    },
  },
  "zh-Hans": {
    htmlLang: "zh-Hans",
    title: "Attention：让微信也能“预览”链接",
    ogTitle: "让微信也能“预览”链接",
    description: "YouTube、X 等链接发到微信里只剩一串网址。Attention 把任何链接变成带标题、封面和二维码的图片卡片。",
    heading: "让链接在微信里一眼看懂。",
    lede: "YouTube、X 和很多网站的链接发到微信里，只剩一串网址。Attention 在你的 iPhone 上把链接变成一张图片卡片，标题、封面、二维码都在上面。",
    download: "在 App Store 下载",
    scanToGet: "用 iPhone 扫码<br>下载 Attention",
    wechatTip: "如果没有跳转到 App Store，请点右上角的 ··· ，选择“在浏览器中打开”。",
    placeholder: "粘贴一个链接",
    make: "生成卡片",
    tryLabel: "试试",
    samples: [
      ["YouTube", "https://www.youtube.com/watch?v=jNQXAC9IVRw"],
      ["X", "https://x.com/jack/status/20"],
      ["维基百科", "https://zh.wikipedia.org/wiki/%E9%87%91%E9%97%A8%E5%A4%A7%E6%A1%A5"],
      ["GitHub", "https://github.com/"],
    ],
    initial: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
    wechatShows: "微信里只显示",
    attentionSends: "Attention 发出的卡片",
    featuresHeading: "随手收藏，找得回来，分享得清楚。",
    features: [
      ["share", "任何 App 都能存", "在 X、YouTube、Safari 等 App 里点分享，再点 Attention；也可以直接粘贴链接。"],
      ["detail", "分享成卡片", "卡片、文字、二维码三种模板随你选。分享图片时会同时复制链接，方便一起发送。"],
      ["feed", "找得回来", "按网站和标签筛选，搜索标题和图片里的文字。"],
      ["private", "需要时就私密", "用面容 ID 锁住私密收藏。没有账号，不追踪；收藏只通过你自己的 iCloud 同步。"],
    ],
    closingHeading: "iPhone、iPad 和 Mac 都能用。",
    closingBody: "在 App Store 免费下载。你的链接只保存在你自己的设备上。",
    support: "支持",
    privacy: "隐私",
    ogImage: "/img/og-zh.jpg",
    demo: {
      madeWith: "由 Attention 生成",
      reading: "正在读取网页…",
      scanToOpen: "扫描二维码打开",
      noPreview: "无法获取预览，扫码或粘贴链接即可打开。",
      chips: { youtube: "YouTube · 视频", bilibili: "哔哩哔哩 · 视频", x: "X · 帖子" },
      errors: {
        not_a_url: "请输入网址，例如 https://b23.tv/…",
        rate_limited: "一分钟内生成得太多了，请稍等再试。",
        generic: "这个链接生成不了卡片，换一个试试。",
      },
    },
  },
  "zh-Hant": {
    htmlLang: "zh-Hant",
    title: "Attention：讓微信也能「預覽」連結",
    ogTitle: "讓微信也能「預覽」連結",
    description: "YouTube、X 等連結傳到微信裡只剩一串網址。Attention 把任何連結變成帶標題、封面和 QR Code 的圖片卡片。",
    heading: "讓連結在微信裡一眼看懂。",
    lede: "YouTube、X 和很多網站的連結傳到微信裡，只剩一串網址。Attention 在你的 iPhone 上把連結變成一張圖片卡片，標題、封面、QR Code 都在上面。",
    download: "在 App Store 下載",
    scanToGet: "用 iPhone 掃描<br>下載 Attention",
    wechatTip: "如果沒有跳轉到 App Store，請點右上角的 ··· ，選擇「在瀏覽器中開啟」。",
    placeholder: "貼上一個連結",
    make: "產生卡片",
    tryLabel: "試試",
    samples: [
      ["YouTube", "https://www.youtube.com/watch?v=jNQXAC9IVRw"],
      ["X", "https://x.com/jack/status/20"],
      ["維基百科", "https://zh.wikipedia.org/zh-tw/%E9%87%91%E9%96%80%E5%A4%A7%E6%A9%8B"],
      ["GitHub", "https://github.com/"],
    ],
    initial: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
    wechatShows: "微信裡只顯示",
    attentionSends: "Attention 傳出的卡片",
    featuresHeading: "隨手收藏，找得回來，分享得清楚。",
    features: [
      ["share", "任何 App 都能存", "在 X、YouTube、Safari 等 App 裡點分享，再點 Attention；也可以直接貼上連結。"],
      ["detail", "分享成卡片", "卡片、文字、QR Code 三種範本隨你選。分享圖片時會同時複製連結，方便一起傳送。"],
      ["feed", "找得回來", "依網站和標籤篩選，搜尋標題和圖片裡的文字。"],
      ["private", "需要時就私密", "用 Face ID 鎖住私密收藏。沒有帳號，不追蹤；收藏只透過你自己的 iCloud 同步。"],
    ],
    closingHeading: "iPhone、iPad 和 Mac 都能用。",
    closingBody: "在 App Store 免費下載。你的連結只儲存在你自己的裝置上。",
    support: "支援",
    privacy: "隱私權",
    ogImage: "/img/og-zh-hant.jpg",
    demo: {
      madeWith: "由 Attention 生成",
      reading: "正在讀取網頁…",
      scanToOpen: "掃描 QR Code 開啟",
      noPreview: "無法取得預覽，掃描 QR Code 或貼上連結即可開啟。",
      chips: { youtube: "YouTube · 影片", bilibili: "嗶哩嗶哩 · 影片", x: "X · 貼文" },
      errors: {
        not_a_url: "請輸入網址，例如 https://youtu.be/…",
        rate_limited: "一分鐘內產生得太多了，請稍候再試。",
        generic: "這個連結產生不了卡片，換一個試試。",
      },
    },
  },
};

const languageNames: Record<HomeLang, string> = { en: "English", "zh-Hans": "简体中文", "zh-Hant": "繁體中文" };

function storeQR(): string {
  const qr = qrPath(appStoreURL);
  return `<svg viewBox="0 0 ${qr.size} ${qr.size}" shape-rendering="crispEdges" aria-hidden="true"><path d="${qr.path}" fill="#000"/></svg>`;
}

export function homePage(lang: HomeLang, origin: string): Response {
  const t = strings[lang];
  const pageURL = `${origin}${homePaths[lang]}`;
  const languageLinks = (Object.keys(homePaths) as HomeLang[])
    .map((other) => `<a class="lang" href="${homePaths[other]}" hreflang="${other}"${other === lang ? ' aria-current="page"' : ""}>${languageNames[other]}</a>`)
    .join("");
  const alternates = (Object.keys(homePaths) as HomeLang[])
    .map((other) => `<link rel="alternate" hreflang="${other}" href="${origin}${homePaths[other]}">`)
    .concat(`<link rel="alternate" hreflang="x-default" href="${origin}/">`)
    .join("\n");
  const features = t.features
    .map(([image, heading, body]) => `<section class="feature">
  <img src="/img/${image}-${lang === "en" ? "en" : "zh"}.webp" alt="" width="360" height="630" loading="lazy" decoding="async">
  <div><h3>${escapeHTML(heading)}</h3><p>${escapeHTML(body)}</p></div>
</section>`)
    .join("\n");
  const samples = t.samples
    .map(([label, url]) => `<button type="button" data-url="${escapeHTML(url)}">${escapeHTML(label)}</button>`)
    .join("");
  // Apple's badges, unmodified (public/img/badges, from Apple's marketing tools): black on light, white on dark.
  const badge = (light: "black" | "white", dark: "black" | "white") => {
    const file = (color: string) => `/img/badges/app-store-${color}-${lang === "en" ? "en" : lang.toLowerCase()}.svg`;
    return `<a class="store" href="${appStoreURL}"><picture><source srcset="${file(dark)}" media="(prefers-color-scheme: dark)"><img src="${file(light)}" alt="${escapeHTML(t.download)}" height="54"></picture></a>`;
  };
  const store = badge("black", "white");
  // The closing panel is ink on a light page and paper on a dark one, so it takes the opposite badge.
  const closingStore = badge("white", "black");

  const html = `<!doctype html>
<html lang="${t.htmlLang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHTML(t.title)}</title>
<meta name="description" content="${escapeHTML(t.description)}">
<link rel="canonical" href="${pageURL}">
${alternates}
<meta name="apple-itunes-app" content="app-id=6827156660">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Attention">
<meta property="og:title" content="${escapeHTML(t.ogTitle)}">
<meta property="og:description" content="${escapeHTML(t.description)}">
<meta property="og:url" content="${pageURL}">
<meta property="og:image" content="${origin}${t.ogImage}?v=${ogImageVersion}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="675">
<meta property="og:image:alt" content="${escapeHTML(t.ogTitle)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#F6F3ED" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#15151A" media="(prefers-color-scheme: dark)">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">
<link rel="stylesheet" href="/home.css">
<script type="application/json" id="strings">${JSON.stringify(t.demo).replaceAll("<", "\\u003c")}</script>
<script type="module" src="/home.js"></script>
</head>
<body>
<div class="wrap">
<header class="top">
  <a class="brand" href="${homePaths[lang]}"><img src="/favicon.svg" alt="" width="30" height="30">Attention</a>
  <nav aria-label="Language">${languageLinks}</nav>
</header>

<main>
<section class="hero">
  <div>
    <h1>${escapeHTML(t.heading)}</h1>
    <p class="lede">${escapeHTML(t.lede)}</p>
    <div class="get">
      ${store}
      <div class="store-qr">${storeQR()}<span>${t.scanToGet}</span></div>
    </div>
    <p class="wechat-tip">${escapeHTML(t.wechatTip)}</p>
  </div>

  <div class="demo">
    <form data-initial="${escapeHTML(t.initial)}">
      <label class="visually-hidden" for="link">${escapeHTML(t.placeholder)}</label>
      <input id="link" type="url" inputmode="url" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="${escapeHTML(t.placeholder)}">
      <button type="submit">${escapeHTML(t.make)}</button>
    </form>
    <p class="samples"><span>${escapeHTML(t.tryLabel)}:</span>${samples}</p>
    <div class="chat">
      <div class="msg"><span class="who">${escapeHTML(t.wechatShows)}</span><p class="bare"></p></div>
      <div class="msg"><span class="who">${escapeHTML(t.attentionSends)}</span><div class="card-frame" aria-live="polite"></div></div>
      <p class="status" role="status"></p>
    </div>
  </div>
</section>

<section class="features">
  <h2>${escapeHTML(t.featuresHeading)}</h2>
  ${features}
</section>

<section class="closing">
  <h2>${escapeHTML(t.closingHeading)}</h2>
  <p>${escapeHTML(t.closingBody)}</p>
  ${closingStore}
</section>
</main>

<footer class="bottom">
  <span>© 2026 Attention</span>
  <nav><a href="/support">${escapeHTML(t.support)}</a><a href="/privacy">${escapeHTML(t.privacy)}</a>${languageLinks.replaceAll(' class="lang"', "")}</nav>
</footer>
</div>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Language": lang,
      "Cache-Control": "public, max-age=300",
      Vary: "Accept-Language",
      "Content-Security-Policy":
        "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    },
  });
}
