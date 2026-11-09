// node ios/Tools/store-shots/search-export.js
// Uses existing raw captures; exports opaque 3840×2560 search creatives.
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
    for (const locale of ['en-US', 'zh-Hans']) {
      const url = pathToFileURL(path.join(__dirname, 'search-result.html'));
      url.searchParams.set('locale', locale);
      await page.goto(url.href);
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map(image => image.decode()));
        if (document.querySelector('h1').scrollWidth > document.querySelector('.copy').clientWidth)
          throw new Error('Headline overflows');
      });
      const file = path.join(out, `search-${locale}.png`);
      await page.locator('#art').screenshot({ path: file });
      console.log(file);
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
