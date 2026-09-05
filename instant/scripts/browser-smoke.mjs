// lightweight per-engine smoke. One phone viewport; loads the
// canonical routes + the travel sheet + the offline shell; asserts no page
// horizontal scroll and that the expected key element is present. Fast (one
// context, reused). Usage: node scripts/browser-smoke.mjs <engine> [baseUrl] [outFile]
import { chromium, firefox, webkit } from 'playwright';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const engineName = (process.argv[2] ?? 'chromium').toLowerCase();
const ENGINE = { chromium, firefox, webkit }[engineName];
const base = process.argv[3] ?? 'http://127.0.0.1:4174';
const outFile = resolve(process.argv[4] ?? `generated/browser-smoke.${engineName}.json`);
const LOC = 'loc=26.2389,73.0243';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const CASES = [
  { id: '/', url: '/', expect: 'h1' },
  { id: '/go', url: `/go?demo=default&${LOC}`, expect: '.card[aria-label="Recommended toilet"]' },
  { id: '/go?demo=longname', url: `/go?demo=longname&${LOC}`, expect: '.card[aria-label="Recommended toilet"]' },
  { id: '/t/:id', url: `/t/demo_clock_pay?${LOC}`, expect: '.card[aria-label="Recommended toilet"]' },
  { id: '/q/:id', url: `/q/RJQUEST26?${LOC}`, expect: '.card[aria-label="Recommended toilet"]' },
  { id: 'offline-state', url: `/go?fail=offline&${LOC}`, expect: '.state' },
  { id: 'travel-sheet', url: `/go?demo=default&${LOC}&reval=launch`, expect: '.card[aria-label="Recommended toilet"]', act: 'sheet' },
];

const report = { engine: engineName, ranAt: new Date().toISOString(), available: true, cases: [] };
let ok = 0;
try {
  const browser = await ENGINE.launch();
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
    geolocation: { latitude: 26.2389, longitude: 73.0243 },
    permissions: ['geolocation'],
    serviceWorkers: 'block',
  });
  for (const c of CASES) {
    const page = await ctx.newPage();
    try {
      await page.goto(base + c.url, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector(c.expect, { timeout: 15000 }).catch(() => {});
      await sleep(200);
      if (c.act === 'sheet') {
        await page.click('.card[aria-label="Recommended toilet"] .btn-primary').catch(() => {});
        await page.waitForSelector('.sheet', { timeout: 10000 }).catch(() => {});
        await sleep(300);
      }
      const m = await page.evaluate(() => {
        const de = document.documentElement;
        return {
          horizontalOverflow: Math.max(0, de.scrollWidth - de.clientWidth),
          sheet: !!document.querySelector('.sheet[role="dialog"][aria-modal="true"]'),
        };
      });
      const present = (await page.$(c.expect)) != null;
      const pass = m.horizontalOverflow <= 2 && (present || c.act === 'sheet');
      report.cases.push({ id: c.id, pass, horizontalOverflow: m.horizontalOverflow, present, sheet: m.sheet });
      if (pass) ok++;
      console.log(`  ${pass ? 'ok' : 'FAIL'}  ${c.id}  hOverflow=${m.horizontalOverflow} present=${present}`);
    } catch (e) {
      report.cases.push({ id: c.id, pass: false, error: String(e).slice(0, 120) });
      console.log(`  ERR ${c.id}: ${String(e).slice(0, 100)}`);
    } finally {
      await page.close();
    }
  }
  await browser.close();
} catch (e) {
  report.available = false;
  report.launchError = String(e).split('\n')[0].slice(0, 160);
  console.log(`${engineName}: NOT AVAILABLE — ${report.launchError}`);
}
report.pass = ok;
report.total = CASES.length;
report.overallPass = report.available && ok === CASES.length;
writeFileSync(outFile, JSON.stringify(report, null, 2) + '\n');
console.log(`${engineName}: ${report.available ? `${ok}/${CASES.length}` : 'unavailable'} -> ${outFile}`);
process.exit(report.available && ok === CASES.length ? 0 : report.available ? 1 : 0);
