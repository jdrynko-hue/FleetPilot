// Local static landing only. No Auth, hosted API, sessions or deployment.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const {chromium, webkit} = createRequire(import.meta.url)('playwright');
const root = fileURLToPath(new URL('../web/', import.meta.url));
const screenshots = process.env.MOBILE_SCREENSHOT_DIR;
const locales = ['en','pl','de','sk','cs','hu','ro','es','fr','it','uk','pt'];
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const requested = url.pathname.endsWith('/') ? url.pathname + 'index.html' : url.pathname;
    const file = path.resolve(root, '.' + requested);
    if (!file.startsWith(root) || !/\.(html|png)$/.test(file)) {
      res.writeHead(404).end(); return;
    }
    const body = await readFile(file);
    res.writeHead(200, {'content-type': file.endsWith('.html')
      ? 'text/html; charset=utf-8' : 'image/png'}).end(body);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = 'http://127.0.0.1:' + server.address().port;
let cases = 0;
try {
  if (screenshots) await mkdir(screenshots, {recursive: true});
  for (const [browserName, engine] of Object.entries({chromium, webkit})) {
    const browser = await engine.launch({headless: true});
    try {
      const page = await browser.newPage({viewport: {width: 320, height: 900}});
      await page.route('**/*', route => new URL(route.request().url()).origin === origin
        ? route.continue() : route.abort());
      for (const route of ['/', '/start/']) {
        for (const width of [320, 375, 412, 760, 761, 1050, 1051, 1280]) {
          await page.setViewportSize({width, height: 900});
          await page.goto(origin + route, {waitUntil: 'load'});
          for (const locale of locales) {
            await page.locator('#site-language').selectOption(locale);
            const link = page.locator('.nav-compact-login');
            const visible = await link.isVisible();
            const label = await link.locator('.nav-compact-label').getAttribute('data-' + locale);
            assert.equal(await link.locator('.nav-compact-label').innerText(), label);
            assert.equal(await link.getAttribute('aria-label'), null,
              'Accessible name must use the translated visible label');
            assert.equal(await link.getAttribute('href'), '/app/?lang=' + locale);
            assert.equal(visible, width <= 1050, `${browserName} ${route} ${width} ${locale}`);
            const entry = width <= 1050 ? link : page.locator('.nav-action');
            assert.equal(await entry.isVisible(), true);
            const box = await entry.boundingBox();
            assert.ok(box && box.x >= 0 && box.x + box.width <= width + 1,
              'Portal entry must fit the viewport');
            if (width <= 1050) {
              assert.ok(box.height >= 44 && box.width >= 44, 'Mobile tap target must be at least 44px');
              const accessible = page.locator('header.nav').getByRole('link', {name: label, exact: true});
              assert.equal(await accessible.count(), 1);
              await link.focus();
              assert.equal(await link.evaluate(el => el === document.activeElement), true);
            }
            const overflow = await page.evaluate(() => ({
              width: document.documentElement.scrollWidth,
              viewport: document.documentElement.clientWidth,
              offenders: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1
                ? [...document.querySelectorAll('body *')].filter(el => {
                  const box = el.getBoundingClientRect(); return box.right > innerWidth + 1;
                }).slice(0, 8).map(el => ({tag: el.tagName, cls: el.className,
                  right: el.getBoundingClientRect().right, text: el.textContent.slice(0, 35)})) : [],
            }));
            assert.ok(overflow.width <= overflow.viewport + 1,
              `Horizontal overflow: ${browserName} ${route} ${width} ${locale} ${JSON.stringify(overflow)}`);
            const selector = await page.locator('#site-language').boundingBox();
            assert.ok(selector && selector.x >= 0 && selector.x + selector.width <= width + 1,
              `Language selector must remain in viewport: ${browserName} ${route} ${width} ${locale} ${JSON.stringify(selector)}`);
            if (screenshots && width === 320 && ['pl', 'de'].includes(locale)) {
              await page.screenshot({path: path.join(screenshots,
                `${browserName}-${route === '/' ? 'root' : 'start'}-${locale}-320.png`)});
            }
            cases++;
          }
        }
      }
      await page.close();
      console.log(`PASS: ${browserName} mobile/desktop portal entry`);
    } finally { await browser.close(); }
  }
  console.log(`PASS: ${cases} local landing cases; two engines, two routes, eight widths, 12 languages`);
} finally {
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}
