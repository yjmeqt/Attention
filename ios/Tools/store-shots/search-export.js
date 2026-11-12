// node ios/Tools/store-shots/search-export.js
// Uses each card locale's raw/<locale>/card.png (from export.js); exports opaque 3840×2560 search creatives.
// node ios/Tools/store-shots/search-export.js zh-Hant   # one locale
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { chromium } = require('playwright-core');

(async () => {
  const out = path.resolve(__dirname, '../../fastlane/search-results');
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({
    executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--allow-file-access-from-files'],
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 3.2 });
    const locales = process.argv.slice(2).length ? process.argv.slice(2) : ['en-US', 'zh-Hans', 'zh-Hant'];
    for (const locale of locales) {
      const url = pathToFileURL(path.join(__dirname, 'search-result.html'));
      url.searchParams.set('locale', locale);
      await page.goto(url.href);
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map(image => image.decode()));
        const copy = document.querySelector('.copy').getBoundingClientRect();
        if (document.querySelector('h1').scrollWidth > copy.width) throw new Error('Headline overflows');
        // The text column must stay clear of the bubble and the card.
        for (const sel of ['.bubble', '.card']) {
          const r = document.querySelector(sel).getBoundingClientRect();
          for (const el of document.querySelectorAll('.copy h1, .copy p')) {
            const t = el.getBoundingClientRect();
            if (t.right > r.left && t.left < r.right && t.bottom > r.top && t.top < r.bottom) throw new Error(`Text overlaps ${sel}`);
          }
        }
      });
      const file = path.join(out, `search-${locale}.png`);
      await page.locator('#art').screenshot({ path: file, omitBackground: false });
      console.log(file);
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
