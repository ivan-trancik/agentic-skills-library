// Takes the screenshots for a design review in one Chrome session. screenshot.sh
// runs it through npx, says what each image shows, and cuts full.png into tiles.
//
//   node capture.cjs <url> <folder>    with CANARY_WORD in the environment
//
// Prints a JSON line saying which element one Tab press focused.
const path = require('path');
const { chromium, devices } = require('playwright');

const [url, folder] = process.argv.slice(2);
const out = (name) => path.join(folder, name);

(async () => {
  const browser = await chromium.launch({ channel: 'chrome' });
  const capture = async (options, take) => {
    const context = await browser.newContext(options);
    const page = await context.newPage();
    await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
    await take(page);
    await context.close();
  };
  const desktop = { viewport: { width: 1440, height: 900 } };
  const still = { animations: 'disabled' };
  let focused = 'nothing';

  const canary = await browser.newContext({ viewport: { width: 480, height: 140 } });
  const canaryPage = await canary.newPage();
  await canaryPage.setContent(`<p style="font: bold 56px sans-serif; margin: 30px">${process.env.CANARY_WORD}</p>`);
  await canaryPage.screenshot({ path: out('canary.png') });
  await canary.close();

  await capture(desktop, async (page) => {
    await page.screenshot({ path: out('desktop.png'), ...still });
    await page.screenshot({ path: out('full.png'), fullPage: true, ...still });
    await page.keyboard.press('Tab');
    focused = await page.evaluate(() => {
      const element = document.activeElement;
      if (!element || element === document.body) return 'nothing';
      const text = (element.innerText || element.value || element.getAttribute('aria-label') || '').trim().slice(0, 40);
      return `${element.tagName.toLowerCase()}${element.id ? '#' + element.id : ''}${text ? ` "${text}"` : ''}`;
    });
    await page.screenshot({ path: out('focus.png'), ...still });
  });
  await capture({ viewport: { width: 768, height: 1024 } }, (page) => page.screenshot({ path: out('tablet.png'), ...still }));
  await capture(devices['Pixel 7'], (page) => page.screenshot({ path: out('phone.png'), ...still }));
  await capture({ ...desktop, colorScheme: 'dark' }, (page) => page.screenshot({ path: out('dark.png'), ...still }));

  await browser.close();
  console.log(JSON.stringify({ focused }));
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
