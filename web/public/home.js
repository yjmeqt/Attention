// The home page's live demo: asks /api/unfurl for a link's preview and draws the card the app would make.
// The card follows ios/Shared/Card (TileTemplate, QRTemplate, CardTint); keep them in step.
const strings = JSON.parse(document.getElementById("strings").textContent);
const form = document.querySelector(".demo form");
const input = form.querySelector("input");
const button = form.querySelector("button");
const bare = document.querySelector(".bare");
const frame = document.querySelector(".card-frame");
const status = document.querySelector(".status");

if (/MicroMessenger/i.test(navigator.userAgent)) document.documentElement.classList.add("in-wechat");

const accents = { youtube: "#FF0033", bilibili: "#FA7399", x: "#000000", web: "#2E6BFF" };
const svgNS = "http://www.w3.org/2000/svg";

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function qrSVG(qr, className) {
  const svg = document.createElementNS(svgNS, "svg");
  svg.setAttribute("viewBox", `0 0 ${qr.size} ${qr.size}`);
  svg.setAttribute("class", className);
  svg.setAttribute("shape-rendering", "crispEdges");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(svgNS, "path");
  path.setAttribute("d", qr.path);
  path.setAttribute("fill", "#000");
  svg.append(path);
  return svg;
}

function loadImage(src) {
  return new Promise((resolve) => {
    if (!src) return resolve(null);
    const image = new Image();
    image.decoding = "async";
    image.onload = () => resolve(image);
    image.onerror = () => resolve(null);
    image.src = src;
  });
}

/** Average color of a region, or of the whole image. */
function averageColor(image, fromY = 0) {
  try {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    const sourceY = Math.floor(image.naturalHeight * fromY);
    context.drawImage(image, 0, sourceY, image.naturalWidth, image.naturalHeight - sourceY, 0, 0, 1, 1);
    const [r, g, b] = context.getImageData(0, 0, 1, 1).data;
    return [r / 255, g / 255, b / 255];
  } catch {
    return null;
  }
}

function tint(rgb) {
  if (!rgb) return { color: "#F2F2F5", dark: false };
  const [r, g, b] = rgb;
  return { color: `rgb(${r * 255}, ${g * 255}, ${b * 255})`, dark: 0.299 * r + 0.587 * g + 0.114 * b < 0.6 };
}

/** From the photo's bottom eighth, like the feed (CardTint.init(_:)). */
const photoTint = (image) => tint(averageColor(image, 7 / 8));

/** Colorful favicons tint text-only cards; black, white and gray ones don't (CardTint.init(favicon:)). */
function faviconTint(icon) {
  const rgb = icon && averageColor(icon);
  if (!rgb) return tint(null);
  const high = Math.max(...rgb), low = Math.min(...rgb);
  return high > 0.15 && (high - low) / high > 0.35 ? tint(rgb) : tint(null);
}

/** Height ÷ width between 16:9 and 9:16, or null for icon-like images (TileTemplate.imageRatio). */
function imageRatio(image) {
  const w = image.naturalWidth, h = image.naturalHeight, ratio = w / h;
  const isIcon = Math.max(w, h) < 400 || (ratio >= 0.8 && ratio <= 1.25 && w < 640);
  return isIcon ? null : Math.min(Math.max(h / w, 9 / 16), 16 / 9);
}

function titleSize(title, textOnly) {
  let length = 0;
  for (const ch of title) length += ch.codePointAt(0) > 0x2e80 ? 2 : 1;
  const base = length <= 30 ? 26 : length <= 70 ? 22 : 19;
  return textOnly ? base + 1 : base;
}

function byline(data) {
  if (data.author && data.handle) return `${data.author} @${data.handle}`;
  return data.author ?? (data.handle ? `@${data.handle}` : null);
}

function info(data, colors, iconImage, textOnly) {
  const primary = colors.dark ? "#fff" : "#121214";
  const secondary = colors.dark ? "rgba(255,255,255,.72)" : "rgba(18,18,20,.6)";
  const box = el("div", textOnly ? "text-only" : "info");
  box.style.color = primary;
  const head = el("div");
  const eyebrow = el("div", "eyebrow");
  eyebrow.style.color = secondary;
  if (iconImage) {
    const fav = el("img", "fav");
    fav.src = iconImage.src;
    fav.alt = "";
    eyebrow.append(fav);
  }
  eyebrow.append(data.kind === "x" ? "X" : data.site);
  const title = el("p", "title", data.title);
  title.style.fontSize = `${titleSize(data.title, textOnly)}px`;
  title.style.webkitLineClamp = textOnly ? 12 : 4;
  if (textOnly) {
    title.style.marginTop = "10px";
    title.style.lineHeight = "1.3";
    if (data.kind === "x") title.style.fontWeight = "500";
  }
  head.append(eyebrow, title);
  const by = byline(data);
  if (by) {
    const line = el("p", "byline", by);
    line.style.color = secondary;
    head.append(line);
  }
  box.append(head);
  if (textOnly) box.append(el("div", "grow"));
  const foot = el("div", "foot");
  const meta = el("div", "meta");
  meta.style.color = secondary;
  meta.append(el("span", "url", data.displayURL));
  const made = el("span", "made");
  const glyph = el("img");
  glyph.src = "/glyph.svg";
  glyph.alt = "";
  made.append(glyph, strings.madeWith);
  meta.append(made);
  foot.append(meta, qrSVG(data.qr, "qr"));
  box.append(foot);
  return box;
}

async function tileCard(data) {
  const [photo, icon] = await Promise.all([loadImage(data.image), loadImage(data.icon)]);
  const card = el("div", "card");
  const ratio = photo && imageRatio(photo);
  if (photo && ratio) {
    const colors = photoTint(photo);
    const image = el("img", "photo");
    image.src = photo.src;
    image.alt = "";
    image.style.height = `${360 * ratio}px`;
    const body = info(data, colors, icon, false);
    if (ratio > 1) {
      // Tall photos carry the text over their lower part, on a scrim of the band color.
      const over = el("div", "over");
      body.style.paddingTop = "108px";
      body.style.background = `linear-gradient(to bottom, transparent, ${colors.color.replace("rgb(", "rgba(").replace(")", ", .75)")} 35%, ${colors.color} 70%)`;
      over.append(image, body);
      card.append(over);
    } else {
      body.style.background = colors.color;
      card.append(image, body);
    }
    if (data.kind === "youtube" || data.kind === "bilibili") {
      const play = el("div", "play");
      play.style.top = `${(360 * Math.min(ratio, 1)) / 2}px`;
      card.append(play);
    }
    card.style.position = "relative";
  } else {
    const colors = faviconTint(icon);
    const body = info(data, colors, icon, true);
    body.style.background = colors.color;
    card.append(body);
  }
  return card;
}

function qrCard(data) {
  const card = el("div", "card qr-card");
  const chip = el("span", "chip", strings.chips[data.kind] ?? data.site);
  chip.style.background = accents[data.kind];
  card.append(chip, qrSVG(data.qr, "big-qr"));
  card.append(el("p", "note", strings.scanToOpen));
  card.append(el("p", "qr-title", data.displayURL));
  card.append(el("p", "note", strings.noPreview));
  card.append(el("p", "mark", strings.madeWith));
  return card;
}

function fit() {
  const card = frame.querySelector(".card");
  if (!card) return;
  const scale = Math.min(1, frame.clientWidth / 360);
  card.style.transform = `scale(${scale})`;
  frame.style.height = `${card.offsetHeight * scale}px`;
}

let current = 0;
async function show(link) {
  const request = ++current;
  bare.textContent = link;
  button.disabled = true;
  status.className = "status";
  status.textContent = strings.reading;
  frame.querySelector(".card")?.classList.add("loading");
  try {
    const response = await fetch(`/api/unfurl?url=${encodeURIComponent(link)}`);
    const data = await response.json();
    if (request !== current) return;
    if (!response.ok) throw new Error(data.error);
    const card = data.title ? await tileCard(data) : qrCard(data);
    if (request !== current) return;
    bare.textContent = data.shareURL;
    frame.replaceChildren(card);
    fit();
    status.textContent = "";
  } catch (error) {
    if (request !== current) return;
    frame.querySelector(".card")?.classList.remove("loading");
    status.className = "status error";
    status.textContent = strings.errors[error.message] ?? strings.errors.generic;
  } finally {
    if (request === current) button.disabled = false;
  }
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  let link = input.value.trim();
  if (!link) return input.focus();
  if (!/^https?:\/\//i.test(link)) link = `https://${link}`;
  show(link);
});
for (const sample of document.querySelectorAll(".samples button")) {
  sample.addEventListener("click", () => {
    input.value = sample.dataset.url;
    show(sample.dataset.url);
  });
}
new ResizeObserver(fit).observe(frame);
show(form.dataset.initial);
