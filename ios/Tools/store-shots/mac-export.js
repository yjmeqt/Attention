// Frame native Mac window captures; no UI is drawn or replaced here.
// node Tools/store-shots/mac-export.js [locale,...]
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright-core');
const headings = {
  'en-US': ['All your links. One library.', 'Find the link you saved.', 'Turn links into cards.'],
  'zh-Hans': ['想留下的链接，都在这里。', '收藏过的链接，轻松找到。', '把链接，变成图片卡片。'],
  'ja': ['リンクを、ひとつの場所に。', '保存したリンクを、すぐに。', 'リンクを画像カードに。'],
  'ko': ['모든 링크를 한곳에.', '저장한 링크를 빠르게.', '링크를 이미지 카드로.'],
  'ru': ['Все ссылки в одной библиотеке.', 'Находите сохранённые ссылки.', 'Превратите ссылку в карточку.'],
  'vi': ['Mọi liên kết, một thư viện.', 'Tìm lại liên kết đã lưu.', 'Biến liên kết thành thẻ ảnh.'],
  'ar-SA': ['كل روابطك في مكتبة واحدة.', 'اعثر على الروابط المحفوظة.', 'حوّل الروابط إلى بطاقات.'],
  'fr-FR': ['Tous vos liens au même endroit.', 'Retrouvez vos liens enregistrés.', 'Des liens à partager en images.'],
  'de-DE': ['Alle Links. Eine Bibliothek.', 'Gespeicherte Links wiederfinden.', 'Aus Links werden Bildkarten.'],
  'es-ES': ['Todos tus enlaces en un lugar.', 'Encuentra los enlaces guardados.', 'Convierte enlaces en tarjetas.'],
  'es-MX': ['Todos tus enlaces en un lugar.', 'Encuentra los enlaces guardados.', 'Convierte enlaces en tarjetas.'],
};
const root = path.resolve(__dirname, '../../fastlane');
(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless:true});
  try {
    for (const locale of process.argv[2]?.split(',') || Object.keys(headings)) {
      const output = path.join(root, 'mac-screenshots', locale);
      fs.mkdirSync(output, {recursive:true});
      const page = await browser.newPage({viewport:{width:1440,height:900},deviceScaleFactor:2});
      for (const [index,scene] of ['library','search','detail'].entries()) {
        const image = fs.readFileSync(path.join(root,'raw',locale,`mac-${scene}.png`)).toString('base64');
        await page.setContent(`<!doctype html><html lang="${locale}" dir="${locale === 'ar-SA' ? 'rtl':'ltr'}"><style>
          *{box-sizing:border-box}body{margin:0;background:#f4f1eb;color:#191919;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
          header{height:135px;display:flex;align-items:center;justify-content:space-between;padding:0 72px;gap:30px}
          h1{font-size:44px;line-height:1.15;letter-spacing:-1.2px;margin:0;font-weight:750}span{font-size:18px;letter-spacing:1px;color:#b62e21}
          main{height:720px;margin:0 72px;display:flex;align-items:center;justify-content:center}
          img{max-width:100%;max-height:100%;object-fit:contain;box-shadow:0 20px 45px #0003;border-radius:12px}
          </style><header><h1>${headings[locale][index]}</h1><span>Attention / Mac</span></header><main><img src="data:image/png;base64,${image}"></main></html>`);
        await page.locator('img').evaluate(img => img.decode());
        const coverage = await page.locator('img').evaluate(img => {
          const canvas = document.createElement('canvas');
          canvas.width = 160; canvas.height = 100;
          const context = canvas.getContext('2d');
          context.drawImage(img, 0, 0, 160, 100);
          const pixels = context.getImageData(0, 0, 160, 100).data;
          let opaque = 0;
          for (let i = 3; i < pixels.length; i += 4) if (pixels[i] > 240) opaque++;
          return opaque / 16000;
        });
        if (coverage < 0.95) throw new Error(`${locale}/${scene}: window occupies only ${(coverage * 100).toFixed(1)}% of capture; recapture outside window animations`);
        await page.screenshot({path:path.join(output,`mac-${index+1}-${scene}.png`),omitBackground:false});
      }
      await page.close();
      console.log(`Rendered ${locale}`);
    }
  } finally {await browser.close();}
})().catch(error => {console.error(error);process.exit(1)});
