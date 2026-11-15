// Renders the home page's link preview images, public/img/og-<lang>.jpg, with headless Chrome.
//   npm run og       (then bump ogImageVersion in src/home.ts, since previews cache images by URL)
// 1200 × 675 (16:9), so Attention's card shows the whole image. Its bottom eighth is solid ink:
// the app colors a card's text band from the image's bottom edge, so the band comes out clean.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import qrcode from "qrcode-generator";

const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const root = fileURLToPath(new URL("..", import.meta.url));
const glyph = `data:image/svg+xml;base64,${readFileSync(join(root, "public/glyph.svg")).toString("base64")}`;

const languages = {
  en: {
    htmlLang: "en",
    heading: "Send links people<br>can actually see.",
    sub: "Any link becomes an image card with its title, cover and QR code.",
    bare: "https://youtu.be/jNQXAC9IVRw",
    eyebrow: "YouTube",
    title: "Your link, as a card anyone in the chat can read",
    made: "Made with Attention",
    strip: ["attentioncard.com", "iPhone, iPad and Mac"],
  },
  zh: {
    htmlLang: "zh-Hans",
    heading: "让链接在微信里<br>一眼看懂。",
    sub: "任何链接都能变成一张带标题、封面和二维码的图片卡片。",
    bare: "https://youtu.be/jNQXAC9IVRw",
    eyebrow: "YouTube",
    title: "你分享的链接，变成一张谁都看得懂的卡片",
    made: "由 Attention 生成",
    strip: ["attentioncard.com", "iPhone、iPad 和 Mac"],
  },
  "zh-hant": {
    htmlLang: "zh-Hant",
    heading: "讓連結在微信裡<br>一眼看懂。",
    sub: "任何連結都能變成一張帶標題、封面和 QR Code 的圖片卡片。",
    bare: "https://youtu.be/jNQXAC9IVRw",
    eyebrow: "YouTube",
    title: "你分享的連結，變成一張誰都看得懂的卡片",
    made: "由 Attention 生成",
    strip: ["attentioncard.com", "iPhone、iPad 和 Mac"],
  },
};

function qrSVG(text) {
  const code = qrcode(0, "M");
  code.addData(text, "Byte");
  code.make();
  const size = code.getModuleCount();
  let path = "";
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (code.isDark(r, c)) path += `M${c} ${r}h1v1h-1z`;
  return `<svg viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges"><path d="${path}"/></svg>`;
}

function page(t) {
  return `<!doctype html><html lang="${t.htmlLang}"><head><meta charset="utf-8"><style>
* { box-sizing: border-box; margin: 0; }
html, body { width: 1200px; height: 675px; overflow: hidden; }
body { background: #F6F3ED; color: #15151A; font-family: -apple-system, "SF Pro Display", "PingFang SC", "PingFang TC", sans-serif; position: relative; }
.copy { position: absolute; left: 72px; top: 64px; width: 600px; }
.brand { display: flex; align-items: center; gap: 14px; font-size: 30px; font-weight: 700; }
.brand img { width: 48px; height: 48px; }
h1 { font-size: 66px; line-height: 1.08; letter-spacing: -0.03em; font-weight: 800; margin-top: 64px; }
.sub { font-size: 26px; line-height: 1.45; color: #66625B; margin-top: 28px; width: 540px; }
.chat { position: absolute; right: 64px; top: 40px; width: 420px; display: flex; flex-direction: column; align-items: flex-end; gap: 16px; }
.bare { background: #95EC69; color: #111; font-size: 19px; padding: 11px 15px; border-radius: 7px; }
.card { width: 380px; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 6px rgba(0,0,0,.14), 0 18px 40px rgba(21,21,26,.14); background: #15151A; color: #fff; }
.cover { height: 170px; background: #E8402A; position: relative; overflow: hidden; }
.cover::before { content: ""; position: absolute; left: 0; top: 0; width: 50%; height: 100%; background: #F6F3ED; }
.cover::after { content: ""; position: absolute; left: 34px; bottom: 34px; width: 92px; height: 12px; background: #15151A; }
.play { position: absolute; left: 50%; top: 50%; width: 64px; height: 64px; margin: -32px 0 0 -32px; border-radius: 50%; background: rgba(0,0,0,.55); z-index: 1; }
.play::after { content: ""; position: absolute; left: 25px; top: 19px; border-left: 22px solid #fff; border-top: 13px solid transparent; border-bottom: 13px solid transparent; }
.info { padding: 18px 20px 20px; }
.eyebrow { font-size: 13px; font-weight: 600; text-transform: uppercase; opacity: .72; display: flex; align-items: center; gap: 7px; }
.eyebrow i { width: 16px; height: 16px; background: #fff; border-radius: 4px; display: inline-block; }
.title { font-size: 25px; line-height: 1.25; font-weight: 700; margin-top: 8px; }
.foot { display: flex; align-items: flex-end; justify-content: space-between; margin-top: 18px; }
.meta { font-size: 13px; opacity: .72; display: flex; flex-direction: column; gap: 6px; }
.meta span { display: flex; align-items: center; gap: 7px; font-weight: 600; }
.meta img { width: 18px; height: 18px; }
.qr { width: 74px; height: 74px; background: #fff; padding: 6px; border-radius: 9px; }
.strip { position: absolute; left: 0; right: 0; bottom: 0; height: 85px; background: #15151A; color: #F6F3ED; display: flex; align-items: center; justify-content: space-between; padding: 0 72px; font-size: 24px; font-weight: 600; }
.strip span:last-child { opacity: .7; font-weight: 500; }
</style></head><body>
<div class="copy">
  <div class="brand"><img src="${glyph}">Attention</div>
  <h1>${t.heading}</h1>
  <p class="sub">${t.sub}</p>
</div>
<div class="chat">
  <div class="bare">${t.bare}</div>
  <div class="card">
    <div class="cover"><div class="play"></div></div>
    <div class="info">
      <div class="eyebrow"><i></i>${t.eyebrow}</div>
      <div class="title">${t.title}</div>
      <div class="foot">
        <div class="meta">youtu.be/jNQXAC9IVRw<span><img src="${glyph}">${t.made}</span></div>
        <div class="qr">${qrSVG("https://attentioncard.com")}</div>
      </div>
    </div>
  </div>
</div>
<div class="strip"><span>${t.strip[0]}</span><span>${t.strip[1]}</span></div>
</body></html>`;
}

// Shared lists without an app-made preview use this template (src/listPreview.ts).
const thumbArea = { left: 560, top: 56, width: 576, height: 470 };
const listLanguages = {
  en: { htmlLang: "en", heading: "A list of links", sub: "Shared with Attention. Open it to see every link.", strip: languages.en.strip },
  zh: { htmlLang: "zh-Hans", heading: "一份链接清单", sub: "用 Attention 分享，打开看全部链接。", strip: languages.zh.strip },
  "zh-hant": { htmlLang: "zh-Hant", heading: "一份連結清單", sub: "用 Attention 分享，打開看全部連結。", strip: languages["zh-hant"].strip },
};

function listTemplate(t) {
  const { left, top, width, height } = thumbArea;
  // Ghost rows in the thumbnail area, for lists without pictures; thumbnails cover them otherwise.
  const rows = [0, 1, 2].map((i) => `<div class="row" style="top:${top + 24 + i * 150}px"><i></i><b></b><b class="short"></b></div>`).join("");
  return `<!doctype html><html lang="${t.htmlLang}"><head><meta charset="utf-8"><style>
* { box-sizing: border-box; margin: 0; }
html, body { width: 1200px; height: 675px; overflow: hidden; }
body { background: #F6F3ED; color: #15151A; font-family: -apple-system, "SF Pro Display", "PingFang SC", "PingFang TC", sans-serif; position: relative; }
.copy { position: absolute; left: 72px; top: 64px; width: 440px; }
.brand { display: flex; align-items: center; gap: 14px; font-size: 30px; font-weight: 700; }
.brand img { width: 48px; height: 48px; }
h1 { font-size: 64px; line-height: 1.1; letter-spacing: -0.03em; font-weight: 800; margin-top: 96px; }
.sub { font-size: 26px; line-height: 1.45; color: #66625B; margin-top: 24px; }
.area { position: absolute; left: ${left}px; top: ${top}px; width: ${width}px; height: ${height}px; background: #EAE4D8; }
.row { position: absolute; left: ${left + 24}px; width: ${width - 48}px; height: 126px; background: #fff; border-radius: 14px; }
.row i { position: absolute; left: 18px; top: 18px; width: 120px; height: 90px; border-radius: 8px; background: #E8402A; opacity: .9; }
.row b { position: absolute; left: 158px; top: 30px; width: 330px; height: 22px; border-radius: 6px; background: #15151A; opacity: .85; }
.row b.short { top: 70px; width: 180px; opacity: .25; }
.strip { position: absolute; left: 0; right: 0; bottom: 0; height: 85px; background: #15151A; color: #F6F3ED; display: flex; align-items: center; justify-content: space-between; padding: 0 72px; font-size: 24px; font-weight: 600; }
.strip span:last-child { opacity: .7; font-weight: 500; }
</style></head><body>
<div class="copy">
  <div class="brand"><img src="${glyph}">Attention</div>
  <h1>${t.heading}</h1>
  <p class="sub">${t.sub}</p>
</div>
<div class="area"></div>${rows}
<div class="strip"><span>${t.strip[0]}</span><span>${t.strip[1]}</span></div>
</body></html>`;
}

const work = mkdtempSync(join(tmpdir(), "attention-og-"));
function render(name, html, format) {
  const source = join(work, `${name}.html`);
  const png = join(work, `${name}.png`);
  writeFileSync(source, html);
  execFileSync(chrome, [
    "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
    "--window-size=1200,675", `--screenshot=${png}`, `file://${source}`,
  ], { stdio: "ignore" });
  const out = join(root, `public/img/${name}.${format === "jpeg" ? "jpg" : "png"}`);
  execFileSync("sips", ["-s", "format", format, ...(format === "jpeg" ? ["-s", "formatOptions", "88"] : []), png, "--out", out], { stdio: "ignore" });
  console.log(out);
}
for (const [lang, t] of Object.entries(languages)) render(`og-${lang}`, page(t), "jpeg");
for (const [lang, t] of Object.entries(listLanguages)) render(`og-list-${lang}`, listTemplate(t), "png");
