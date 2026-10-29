// Renders the App Store screenshots and product page headers from capture.zsh's raw screens, in Google Chrome:
//   node Tools/store-shots/export.js [screenshots|headers|all] [device,device] [locale,locale]
// Screenshots: frame.html for every device, locale and screen into fastlane/screenshots/<locale>/<device>-<n>-<scene>.png,
// the layout Tools/release.sh uploads, plus iphone63 (1206×2622) resized from iphone and es-MX copied from es-ES.
// Headers: header.html into fastlane/headers/header-<locale>.png at 3840×1646 (21:9); upload them in App Store Connect.
// Needs `npm install` here once; CHROME overrides the Chrome binary.
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { chromium } = require("playwright-core");
const COPY = require("./copy.js");

// CSS size and scale factor; they multiply to the App Store pixel size.
const SIZES = { "iphone": [330, 717, 4], "ipad": [688, 516, 4], "duo": [669, 951, 3], "duo-cover": [466, 678, 3] };
const FASTLANE = path.resolve(__dirname, "../../fastlane");
const RAW = path.join(FASTLANE, "raw");
const what = process.argv[2] || "all";
const devices = process.argv[3] ? process.argv[3].split(",") : Object.keys(SIZES);
const locales = process.argv[4] ? process.argv[4].split(",") : Object.keys(COPY);
const page = file => `file://${path.join(__dirname, file)}`;

// The Chinese comparison screen shows the app's card on its own, cut out of the iPhone detail screen.
function cropCard() {
  const shot = path.join(RAW, "zh-Hans", "iphone-detail.png"), frame = path.join(RAW, "zh-Hans", "iphone-detail.json");
  if (!fs.existsSync(shot) || !fs.existsSync(frame)) return false;
  const f = JSON.parse(fs.readFileSync(frame, "utf8"));
  const [w, h] = execFileSync("sips", ["-g", "pixelWidth", "-g", "pixelHeight", shot], { encoding: "utf8" })
    .match(/\d+$/gm).map(Number);
  execFileSync("sips", ["-c", String(Math.round(f.height * h)), String(Math.round(f.width * w)),
    "--cropOffset", String(Math.round(f.y * h)), String(Math.round(f.x * w)), shot, "--out", path.join(RAW, "zh-Hans", "card.png")], { stdio: "ignore" });
  return true;
}

async function screenshots(browser) {
  const OUT = path.join(FASTLANE, "screenshots");
  const missing = [];
  if (locales.includes("zh-Hans") && !cropCard()) missing.push("zh-Hans/iphone-detail (for the card)");
  for (const d of devices) {
    const [w, h, scale] = SIZES[d];
    const tab = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
    for (const l of locales) {
      const dir = path.join(OUT, l);
      fs.mkdirSync(dir, { recursive: true });
      // Earlier sets used other scene names; leave only this run's files for the device.
      const own = new RegExp(`^${d === "iphone" ? "iphone(63)?" : d}-\\d`);
      for (const f of fs.readdirSync(dir)) if (own.test(f)) fs.rmSync(path.join(dir, f));
      for (let k = 1; k <= 5; k++) {
        const scene = COPY[l][k - 1][2];
        if (scene !== "compare" && !fs.existsSync(path.join(RAW, l, `${d}-${scene}.png`))) { missing.push(`${l}/${d}-${scene}`); continue; }
        await tab.goto(`${page("frame.html")}?d=${d}&l=${l}&k=${k}`);
        await tab.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode().catch(() => {}))); });
        await tab.waitForTimeout(300);
        const file = path.join(dir, `${d}-${k}-${scene}.png`);
        await tab.locator("#f").screenshot({ path: file });
        if (d === "iphone") execFileSync("sips", ["-z", "2622", "1206", file, "--out", path.join(dir, `iphone63-${k}-${scene}.png`)], { stdio: "ignore" });
      }
      process.stdout.write(`${d} ${l}  `);
    }
    await tab.close();
  }
  if (locales.includes("es-ES")) {
    fs.mkdirSync(path.join(OUT, "es-MX"), { recursive: true });
    for (const f of fs.readdirSync(path.join(OUT, "es-ES"))) fs.copyFileSync(path.join(OUT, "es-ES", f), path.join(OUT, "es-MX", f));
  }
  console.log(missing.length ? `\nmissing raw: ${missing.join(" ")}` : "\nall raw present");
}

async function headers(browser) {
  const OUT = path.join(FASTLANE, "headers");
  fs.mkdirSync(OUT, { recursive: true });
  const tab = await browser.newPage({ viewport: { width: 1920, height: 823 }, deviceScaleFactor: 2 });
  for (const l of locales) {
    await tab.goto(`${page("header.html")}?l=${l}`);
    await tab.waitForSelector("body[data-ready]");
    await tab.waitForTimeout(1200);
    await tab.locator("#hd").screenshot({ path: path.join(OUT, `header-${l}.png`) });
  }
  console.log(`headers: ${locales.join(" ")}`);
}

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    args: ["--allow-file-access-from-files"] });
  if (what === "screenshots" || what === "all") await screenshots(browser);
  if (what === "headers" || what === "all") await headers(browser);
  await browser.close();
})();
