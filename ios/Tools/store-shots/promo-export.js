// Renders the promo video and posters in Google Chrome, into fastlane/promo/ (git-ignored):
//   node Tools/store-shots/promo-export.js video [story|square|xhs]   → promo-zh-Hans-<format>.mp4 (30 fps, H.264)
//   node Tools/store-shots/promo-export.js frames 0,2.7,… [format]    → review/frame-<t>.png, single frames for checking
//   node Tools/store-shots/promo-export.js posters                    → poster-<concept>-<format>.png
//   node Tools/store-shots/promo-export.js xhs                        → xhs/1.png…8.png, a 3:4 Xiaohongshu carousel
//   node Tools/store-shots/promo-export.js log <name> '<query>'       → log/<name>.png, a 3:4 series card: log, bars or rules (see poster.html)
// Video formats: story 1080×1920, square 1080×1080, xhs 1080×1440.
// promo.html exposes renderAt(t), so each frame is drawn at an exact time rather than recorded in real time.
// Needs ffmpeg on PATH and `npm install` here once; CHROME overrides the Chrome binary.
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const { chromium } = require("playwright-core");

const OUT = path.resolve(__dirname, "../../fastlane/promo");
const page = (file, q = "") => `file://${path.join(__dirname, file)}${q}`;
const what = process.argv[2] || "video";

const VIDEO = { story: [1080, 1920], square: [1080, 1080], xhs: [1080, 1440] };
const format = f => { if (!VIDEO[f]) throw new Error(`Unknown format: ${f}`); return f; };

async function open(browser, file, size, q) {
  const tab = await browser.newPage({ viewport: size, deviceScaleFactor: 1 });
  const errors = [];
  tab.on("pageerror", e => errors.push(e.message));
  tab.on("console", m => m.type() === "error" && errors.push(m.text()));
  await tab.goto(page(file, q));
  await tab.evaluate(() => window.ready);
  if (errors.length) throw new Error(`${file}${q}: ${errors.join("; ")}`);
  return tab;
}

// Fails when a caption, chip or end-card line is wider than the canvas or runs off it.
async function checkBounds(tab, t) {
  const bad = await tab.evaluate(() => {
    const W = innerWidth, H = innerHeight, out = [];
    for (const el of document.querySelectorAll(".cap .l1, .cap .l2, .chip, #end .word, #end .slogan, #end .cta, #end .fine")) {
      const cs = getComputedStyle(el), host = el.closest(".cap, .chip, #end");
      if (+getComputedStyle(host).opacity < .99 || +cs.opacity < .99) continue;
      const r = el.getBoundingClientRect();
      if (r.left < 20 || r.right > W - 20 || r.top < 0 || r.bottom > H) out.push(`${el.className || el.tagName} "${el.textContent.trim().slice(0, 20)}" at ${r.left | 0},${r.top | 0}–${r.right | 0},${r.bottom | 0}`);
    }
    // The end card's tilted card must not cover its text.
    const end = document.querySelector("#end");
    if (+getComputedStyle(end).opacity > .99) {
      const P = end.querySelector(".peek").getBoundingClientRect();
      for (const el of end.querySelectorAll(".word, .slogan, .cta, .fine")) {
        const r = el.getBoundingClientRect();
        if (+getComputedStyle(el).opacity > .99 && r.left < P.right && P.left < r.right && r.top < P.bottom && P.top < r.bottom) out.push(`end card ${[P.left, P.top, P.right, P.bottom].map(Math.round)} covers .${el.className} ${[r.left, r.top, r.right, r.bottom].map(Math.round)}`);
      }
    }
    return out;
  });
  if (bad.length) throw new Error(`t=${t}: ${bad.join("; ")}`);
}

const promo = (browser, f) => open(browser, "promo.html", { width: VIDEO[f][0], height: VIDEO[f][1] }, `?t=0&format=${f}`);

async function video(browser, f) {
  const tab = await promo(browser, f);
  const { duration, fps, holds } = await tab.evaluate(() => window.ready);
  const checks = new Set(holds.map(h => Math.round(h * fps)));
  const file = path.join(OUT, `promo-zh-Hans-${f}.mp4`);
  const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(fps), "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", file], { stdio: ["pipe", "inherit", "inherit"] });
  const done = new Promise((res, rej) => ff.on("close", c => c ? rej(new Error(`ffmpeg exited ${c}`)) : res()));
  const n = Math.round(duration * fps);
  for (let f = 0; f < n; f++) {
    const t = f / fps;
    await tab.evaluate(t => renderAt(t), t);
    if (checks.has(f)) await checkBounds(tab, t.toFixed(2));
    const png = await tab.screenshot({ type: "png" });
    if (!ff.stdin.write(png)) await new Promise(r => ff.stdin.once("drain", r));
    if (f % 60 === 0) process.stdout.write(`\r  frame ${f}/${n}`);
  }
  ff.stdin.end();
  await done;
  console.log(`\r  ${path.relative(process.cwd(), file)} (${n} frames)`);
}

async function frames(browser, times, f) {
  const dir = path.join(OUT, "review");
  fs.mkdirSync(dir, { recursive: true });
  const tab = await promo(browser, f);
  for (const t of times) {
    await tab.evaluate(t => renderAt(t), t);
    await checkBounds(tab, t).catch(e => console.warn(`  warning: ${e.message}`)); // mid-animation frames may run off on purpose
    await tab.screenshot({ path: path.join(dir, `frame-${t.toFixed(2).padStart(5, "0")}.png`) });
  }
  console.log(`  ${times.length} frames in ${path.relative(process.cwd(), dir)}`);
}

// Poster formats: CSS size = pixel size.
const FORMATS = { story: [1080, 1920], feed: [1080, 1350], square: [1080, 1080] };

// Xiaohongshu carousel: a 3:4 cover poster, then the video's story beats as stills, at times when each beat has settled.
const XHS_BEATS = [2.2, 3.2, 4.75, 6.6, 10.6, 12.85, 15.5];
async function xhs(browser) {
  const dir = path.join(OUT, "xhs");
  fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
  const cover = await open(browser, "poster.html", { width: 1080, height: 1440 }, "?concept=cover&format=xhs");
  const bad = await cover.evaluate(() => window.overlaps());
  await cover.screenshot({ path: path.join(dir, "1.png") });
  if (bad.length) throw new Error(`xhs cover: ${bad.join("; ")}`);
  const tab = await promo(browser, "xhs");
  for (const [i, t] of XHS_BEATS.entries()) {
    await tab.evaluate(t => renderAt(t), t);
    await checkBounds(tab, t);
    await tab.screenshot({ path: path.join(dir, `${i + 2}.png`) });
  }
  console.log(`  ${XHS_BEATS.length + 1} images in ${path.relative(process.cwd(), dir)}`);
}
// Writes every poster, then fails if any had overlapping or off-canvas boxes.
async function posters(browser) {
  const problems = [];
  for (const concept of ["compare", "steps"]) for (const [format, [w, h]] of Object.entries(FORMATS)) {
    const tab = await open(browser, "poster.html", { width: w, height: h }, `?concept=${concept}&format=${format}`);
    const bad = await tab.evaluate(() => window.overlaps());
    if (bad.length) problems.push(`${concept}/${format}: ${bad.join("; ")}`);
    const file = path.join(OUT, `poster-${concept}-${format}.png`);
    await tab.screenshot({ path: file });
    console.log(`  ${path.relative(process.cwd(), file)}`);
    await tab.close();
  }
  if (problems.length) throw new Error(problems.join("\n"));
}

// One build-in-public board; the query is poster.html's log, bars or rules parameters (log when it names no concept).
async function log(browser, name, query) {
  const dir = path.join(OUT, "log");
  fs.mkdirSync(dir, { recursive: true });
  const tab = await open(browser, "poster.html", { width: 1080, height: 1440 }, `?format=xhs&${/(^|&)concept=/.test(query) ? "" : "concept=log&"}${query}`);
  const bad = await tab.evaluate(() => window.overlaps());
  const file = path.join(dir, `${name}.png`);
  await tab.screenshot({ path: file });
  console.log(`  ${path.relative(process.cwd(), file)}`);
  if (bad.length) throw new Error(`log ${name}: ${bad.join("; ")}`);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({
    executablePath: process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    args: ["--allow-file-access-from-files", "--use-angle=metal", "--enable-gpu-rasterization", "--ignore-gpu-blocklist"],
  });
  try {
    if (what === "video") await video(browser, format(process.argv[3] || "story"));
    else if (what === "frames") await frames(browser, (process.argv[3] || "0").split(",").map(Number), format(process.argv[4] || "story"));
    else if (what === "posters") await posters(browser);
    else if (what === "xhs") await xhs(browser);
    else if (what === "log") await log(browser, process.argv[3] || "day", process.argv[4] || "");
    else throw new Error(`Unknown target: ${what}`);
  } finally { await browser.close(); }
})().catch(e => { console.error(e.message); process.exit(1); });
