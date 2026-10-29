// [headline, subline, raw scene] for each screenshot, in App Store order. The <span> part is set in red.
// Every language but Chinese pitches one library for links from every site, shown with Apple and Wikipedia pages only;
// Chinese pitches sending YouTube and X links to WeChat.
const COPY = {
  "en-US": [
    ["All your links. <span>One place!</span>", "From any app and any site", "feed"],
    ["Save from <span>any app!</span>", "Tap Share, then Attention", "share"],
    ["No algorithm. <span>No tracking!</span>", "No feed, only what you saved. Private stays behind Face ID", "private"],
    ["Find it <span>by site!</span>", "Search everything, or filter by site", "search"],
    ["Share it <span>your way!</span>", "As a card, plain text or a QR code", "detail"],
  ],
  "zh-Hans": [
    ["别再发<br><span>一串网址！</span>", "YouTube、X 的链接发到微信只剩网址。发张卡片，一眼看懂", "compare"],
    ["标题、封面、<br><span>二维码！</span>", "好友扫码，就能打开原链接", "detail"],
    ["点分享，<br><span>一键生成！</span>", "在 YouTube、X 里点分享，选 Attention", "share"],
    ["卡片、文字、<br><span>随你选！</span>", "默认帮你选好合适的模板", "template"],
    ["存过的，<br><span>随时找回！</span>", "搜索，或按网站筛选", "search"],
  ],
  "zh-Hant": [
    ["所有連結，<br><span>集中一處！</span>", "來自任何 App、任何網站", "feed"],
    ["任何 App<br>都能<span>儲存！</span>", "點一下分享，再選 Attention", "share"],
    ["沒有演算法。<br><span>沒有追蹤！</span>", "沒有動態消息，只有你存下的。私密項目由 Face ID 保護", "private"],
    ["依網站<br><span>找回！</span>", "搜尋全部，或依網站篩選", "search"],
    ["想怎麼分享，<br><span>都可以！</span>", "卡片、文字或 QR Code", "detail"],
  ],
  "ko": [
    ["모든 링크를 <span>한곳에!</span>", "어떤 앱, 어떤 사이트에서든", "feed"],
    ["어떤 앱에서든 <span>저장!</span>", "공유를 누르고 Attention을 선택하세요", "share"],
    ["알고리즘 없이. <span>추적 없이!</span>", "피드 없이 저장한 것만. 비공개 항목은 Face ID로", "private"],
    ["사이트별로 <span>찾기!</span>", "전체 검색, 또는 사이트별 필터", "search"],
    ["원하는 대로 <span>공유!</span>", "카드, 텍스트, QR 코드로", "detail"],
  ],
  "ja": [
    ["すべてのリンクを<br><span>ひとつに！</span>", "どのアプリ、どのサイトのリンクも", "feed"],
    ["どのアプリからでも<br><span>保存！</span>", "共有をタップして Attention を選ぶだけ", "share"],
    ["アルゴリズムなし。<br><span>トラッキングなし！</span>", "フィードなし、保存したものだけ。プライベートは Face ID で", "private"],
    ["サイトごとに<br><span>見つかる！</span>", "まとめて検索、またはサイトで絞り込み", "search"],
    ["好きな形で<br><span>共有！</span>", "カード、テキスト、QR コードで", "detail"],
  ],
  "ru": [
    ["Все ваши ссылки.<br><span>В одном месте!</span>", "Из любого приложения и с любого сайта", "feed"],
    ["Сохраняйте <span>из любого приложения!</span>", "Нажмите «Поделиться», затем Attention", "share"],
    ["Без алгоритмов. <span>Без слежки!</span>", "Без ленты, только сохранённое. Личное — под Face ID", "private"],
    ["Ищите <span>по сайту!</span>", "Поиск по всему или фильтр по сайту", "search"],
    ["Делитесь <span>как удобно!</span>", "Карточкой, текстом или QR-кодом", "detail"],
  ],
  "vi": [
    ["Mọi liên kết. <span>Một nơi!</span>", "Từ mọi ứng dụng và mọi trang web", "feed"],
    ["Lưu từ <span>mọi ứng dụng!</span>", "Chạm Chia sẻ, rồi chọn Attention", "share"],
    ["Không thuật toán. <span>Không theo dõi!</span>", "Không bảng tin, chỉ những gì bạn lưu. Mục riêng tư khóa bằng Face ID", "private"],
    ["Tìm theo <span>trang web!</span>", "Tìm tất cả, hoặc lọc theo trang", "search"],
    ["Chia sẻ <span>theo cách bạn muốn!</span>", "Dạng thẻ, văn bản hoặc mã QR", "detail"],
  ],
  "ar-SA": [
    ["كل روابطك. <span>في مكان واحد!</span>", "من أي تطبيق وأي موقع", "feed"],
    ["احفظ من <span>أي تطبيق!</span>", "اضغط مشاركة، ثم Attention", "share"],
    ["بلا خوارزميات. <span>بلا تتبع!</span>", "بلا خلاصة، فقط ما حفظته. والخاص محمي بـ Face ID", "private"],
    ["ابحث <span>حسب الموقع!</span>", "ابحث في كل شيء أو صفِّ حسب الموقع", "search"],
    ["شارك <span>كما تريد!</span>", "كبطاقة أو نص أو رمز QR", "detail"],
  ],
  "fr-FR": [
    ["Tous vos liens. <span>Au même endroit !</span>", "Depuis n’importe quelle app, n’importe quel site", "feed"],
    ["Enregistrez <span>depuis toute app !</span>", "Touchez Partager, puis Attention", "share"],
    ["Zéro algorithme. <span>Zéro pistage !</span>", "Pas de fil, juste ce que vous gardez. Le privé reste derrière Face ID", "private"],
    ["Retrouvez-les <span>par site !</span>", "Cherchez partout, ou filtrez par site", "search"],
    ["Partagez <span>à votre façon !</span>", "En carte, en texte ou en QR code", "detail"],
  ],
  "de-DE": [
    ["Alle deine Links. <span>An einem Ort!</span>", "Aus jeder App und von jeder Website", "feed"],
    ["Sichern aus <span>jeder App!</span>", "Auf Teilen tippen, dann auf Attention", "share"],
    ["Kein Algorithmus. <span>Kein Tracking!</span>", "Kein Feed, nur was du sicherst. Privates bleibt hinter Face ID", "private"],
    ["Finden <span>nach Website!</span>", "Alles durchsuchen oder nach Website filtern", "search"],
    ["Teilen, <span>wie du willst!</span>", "Als Karte, Text oder QR-Code", "detail"],
  ],
  "es-ES": [
    ["Todos tus enlaces. <span>¡En un solo lugar!</span>", "Desde cualquier app y cualquier sitio", "feed"],
    ["¡Guarda desde <span>cualquier app!</span>", "Toca Compartir y luego Attention", "share"],
    ["Sin algoritmo. <span>¡Sin rastreo!</span>", "Sin feed, solo lo que guardas. Lo privado queda tras Face ID", "private"],
    ["¡Encuéntralos <span>por sitio!</span>", "Busca en todo o filtra por sitio", "search"],
    ["¡Compártelo <span>a tu manera!</span>", "Como tarjeta, texto o código QR", "detail"],
  ],
};
if (typeof module !== "undefined") module.exports = COPY;
