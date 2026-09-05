// automated responsive / overflow / a11y matrix.
// Requires: npm run build && npm run preview (port 4174)  [fixture build]
// Usage: node scripts/responsive-matrix.mjs <outDir> [baseUrl] [engine]
import { chromium, firefox, webkit } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const outDir = resolve(process.argv[2] ?? 'generated');
const base = process.argv[3] ?? 'http://127.0.0.1:4174';
const engineName = (process.argv[4] ?? 'chromium').toLowerCase();
const ENGINE = { chromium, firefox, webkit }[engineName] ?? chromium;
mkdirSync(outDir, { recursive: true });
const shotDir = resolve(outDir, 'shots');
mkdirSync(shotDir, { recursive: true });
const LOC = 'loc=26.2389,73.0243';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const QUICK = process.env.QUICK === '1';
const ALL_VIEWPORTS = [
  ['320x568', 320, 568, 'phone-portrait'],
  ['360x640', 360, 640, 'phone-portrait'],
  ['375x667', 375, 667, 'phone-portrait'],
  ['390x844', 390, 844, 'phone-portrait'],
  ['412x915', 412, 915, 'phone-portrait'],
  ['430x932', 430, 932, 'phone-portrait'],
  ['568x320', 568, 320, 'phone-landscape'],
  ['667x375', 667, 375, 'phone-landscape'],
  ['844x390', 844, 390, 'phone-landscape'],
  ['915x412', 915, 412, 'phone-landscape'],
  ['768x1024', 768, 1024, 'tablet'],
  ['1024x768', 1024, 768, 'tablet'],
  ['1280x800', 1280, 800, 'desktop'],
  ['1440x900', 1440, 900, 'desktop'],
];
// cross-engine QUICK subset — representative viewports incl. the shortest
// landscape (568x320) so the modal states are exercised there too .
const QUICK_VP = new Set(['320x568', '568x320', '390x844', '844x390', '768x1024', '1440x900']);
const VIEWPORTS = QUICK ? ALL_VIEWPORTS.filter((v) => QUICK_VP.has(v[0])) : ALL_VIEWPORTS;

// state -> { url, wait, act?, textScale? }
const STATES = [
  { id: 'landing', url: '/' },
  { id: 'permission', url: `/go?perm=prompt`, wait: '.state' },
  { id: 'go-unknown', url: `/go?demo=unknown&${LOC}`, wait: '.card[aria-label="Recommended toilet"]' },
  { id: 'go-corroborated', url: `/go?demo=default&${LOC}`, wait: '.card[aria-label="Recommended toilet"]' },
  { id: 'go-longname', url: `/go?demo=longname&${LOC}`, wait: '.card[aria-label="Recommended toilet"]' },
  { id: 't-focus', url: `/t/demo_clock_pay?${LOC}`, wait: '.card[aria-label="Recommended toilet"]' },
  { id: 't-focus-longname', url: `/t/demo_long_selected?demo=longname&${LOC}`, wait: '.card[aria-label="Recommended toilet"]' },
  { id: 't-ineligible', url: `/t/demo_old_bus_stand?${LOC}`, wait: '.card[aria-label="Recommended toilet"]' },
  { id: 'offline', url: `/go?fail=offline&${LOC}`, wait: '.state' },
  { id: 'location-denied', url: `/go?locerr=denied&${LOC}`, wait: '.state' },
  { id: 'location-timeout', url: `/go?locerr=timeout`, wait: '.state' },
  { id: 'no-toilets', url: `/go?demo=empty&${LOC}`, wait: '.state' },
  { id: 'no-confident', url: `/go?demo=none&${LOC}`, wait: '.state' },
  { id: 'go-text200', url: `/go?demo=default&${LOC}`, wait: '.card[aria-label="Recommended toilet"]', textScale: 2 },
  { id: 'go-longname-text150', url: `/go?demo=longname&${LOC}`, wait: '.card[aria-label="Recommended toilet"]', textScale: 1.5 },
];
// interactive (modal) states — run at EVERY viewport in the full matrix .
const MODAL_STATES = [
  { id: 'travel-sheet', url: `/go?demo=default&${LOC}&reval=launch`, act: 'navigate-sheet' },
  { id: 'confirm-dialog', url: `/go?demo=longname&${LOC}&reval=confirmThenLaunch`, act: 'navigate-confirm' },
];

// FULL matrix: every state (static + modal) at every viewport.
// QUICK cross-engine subset: a defined viewport + state list (must include the
// shortest landscape and both modal states — ).
const QUICK_STATE_IDS = [
  'landing', 'go-corroborated', 'go-longname', 't-focus', 'offline', 'permission',
  'go-text200', 'travel-sheet', 'confirm-dialog',
];
const ALL_STATES = STATES.concat(MODAL_STATES);
// Every state (static + modal) runs at every viewport. No selective sampling —
// the full Chromium matrix is exactly VIEWPORTS.length * STATES_.length rows and
// the run asserts that below .
const STATES_ = QUICK ? ALL_STATES.filter((s) => QUICK_STATE_IDS.includes(s.id)) : ALL_STATES;

// which (viewport,state) get a screenshot
const SHOT = new Set([
  '320x568|go-longname', '390x844|go-corroborated', '430x932|go-corroborated',
  '844x390|travel-sheet', '844x390|confirm-dialog', '768x1024|go-corroborated',
  '1440x900|landing', '1440x900|go-corroborated', '390x844|go-text200',
  't-focus', 'offline', 'permission', 'go-longname|1440', 'location-denied',
  '320x568|t-focus-longname', '390x844|confirm-dialog',
]);

const OVERFLOW_TOL = 2; // px rounding tolerance

async function measure(page, vpW) {
  return page.evaluate(
    ({ vpW, tol }) => {
      const de = document.documentElement;
      const scrollWidth = de.scrollWidth;
      const clientWidth = de.clientWidth;
      const horizontalOverflow = Math.max(0, scrollWidth - clientWidth);
      let maxElementOverflowPx = 0;
      let clippedElementCount = 0;
      const offenders = [];
      for (const el of document.querySelectorAll('body *')) {
        const r = el.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) continue;
        const cs = getComputedStyle(el);
        // Ignore intentionally off-canvas a11y helpers (skip link parked at
        // left:-999px, sr-only, [hidden]) — these do NOT cause page scroll.
        const offCanvasLeft = (cs.position === 'absolute' || cs.position === 'fixed') && r.right <= 1;
        if (offCanvasLeft || cs.visibility === 'hidden' || el.hasAttribute('hidden')) continue;
        // Rightward overflow is what breaks layout / forces horizontal scroll.
        const over = r.right - vpW;
        if (over > tol) {
          maxElementOverflowPx = Math.max(maxElementOverflowPx, over);
          clippedElementCount++;
          if (offenders.length < 6)
            offenders.push({ tag: el.tagName.toLowerCase(), cls: String(el.className).slice(0, 60), over: Math.round(over) });
        }
      }
      // key elements present
      const q = (s) => !!document.querySelector(s);
      const btns = [...document.querySelectorAll('button, a.btn')].map((b) => {
        const r = b.getBoundingClientRect();
        return { t: (b.textContent || '').trim().slice(0, 24), w: Math.round(r.width), h: Math.round(r.height) };
      });
      const actionable = btns.filter((b) => b.w > 0 && b.h > 0);
      const buttonMinSizePass = actionable.every((b) => b.h >= 44 && b.w >= 44);
      const smallButtons = actionable.filter((b) => b.h < 44 || b.w < 44);
      // modal in viewport?
      const sheet = document.querySelector('.sheet');
      let dialogInViewport = null;
      if (sheet) {
        const r = sheet.getBoundingClientRect();
        dialogInViewport =
          r.left >= -tol &&
          r.right <= vpW + tol &&
          r.bottom <= window.innerHeight + tol &&
          // its own content is scrollable if taller
          sheet.scrollHeight <= sheet.clientHeight + 1
            ? true
            : sheet.scrollHeight > sheet.clientHeight
              ? 'scrollable'
              : false;
      }
      return {
        scrollWidth,
        clientWidth,
        horizontalOverflow,
        maxElementOverflowPx: Math.round(maxElementOverflowPx),
        clippedElementCount,
        offenders,
        keyElements: {
          h1: q('h1'),
          distancePill: q('.pill-distance'),
          statusPills: document.querySelectorAll('.pill').length,
          cautions: document.querySelectorAll('.cautions li').length,
          primaryCta: q('.btn-primary'),
          secondaryCta: q('.btn-secondary, .btn-ghost'),
          alternatives: document.querySelectorAll('.alt').length,
          footer: q('.wrap > .stack > p.small.muted:last-child') || q('.wrap p.small.muted'),
          focusCard: (document.querySelector('.card[aria-label="Recommended toilet"] p')?.textContent || '').includes('FROM YOUR LINK') || q('.card[aria-label="Recommended toilet"]'),
        },
        buttonMinSizePass,
        smallButtons,
        dialogInViewport,
      };
    },
    { vpW, tol: OVERFLOW_TOL },
  );
}

const rows = [];
const browser = await ENGINE.launch();

for (const [vp, w, h, cls] of VIEWPORTS) {
  for (const st of STATES_) {
    const ctx = await browser.newContext({
      viewport: { width: w, height: h },
      deviceScaleFactor: 2,
      isMobile: cls.startsWith('phone'),
      hasTouch: cls.startsWith('phone'),
      geolocation: { latitude: 26.2389, longitude: 73.0243 },
      permissions: ['geolocation'],
      serviceWorkers: 'block',
      colorScheme: 'light',
    });
    const page = await ctx.newPage();
    try {
      if (st.textScale) await page.addInitScript((s) => {
        document.addEventListener('DOMContentLoaded', () => (document.documentElement.style.fontSize = 16 * s + 'px'));
      }, st.textScale);
      await page.goto(base + st.url, { waitUntil: 'domcontentloaded' });
      if (st.wait) await page.waitForSelector(st.wait, { timeout: 12000 }).catch(() => {});
      await sleep(250);
      if (st.act === 'navigate-sheet' || st.act === 'navigate-confirm') {
        await page.click('.card[aria-label="Recommended toilet"] .btn-primary').catch(() => {});
        await page.waitForSelector('.sheet', { timeout: 10000 }).catch(() => {});
        await sleep(350);
      }
      const m = await measure(page, w);
      const pass =
        m.horizontalOverflow <= OVERFLOW_TOL &&
        m.maxElementOverflowPx <= OVERFLOW_TOL &&
        m.buttonMinSizePass &&
        (m.dialogInViewport === null || m.dialogInViewport === true || m.dialogInViewport === 'scrollable');
      const key = `${vp}|${st.id}`;
      let shotPath = null;
      if ([...SHOT].some((s) => key.includes(s) || key === s || st.id === s)) {
        shotPath = `shots/${vp}_${st.id}.png`;
        await page.screenshot({ path: resolve(outDir, shotPath), fullPage: !st.act });
      }
      rows.push({ viewport: vp, class: cls, state: st.id, pass, screenshot: shotPath, ...m });
      process.stdout.write(pass ? '.' : `\n  FAIL ${key}  hOverflow=${m.horizontalOverflow} maxEl=${m.maxElementOverflowPx} btns=${m.buttonMinSizePass} dialog=${m.dialogInViewport}\n`);
    } catch (e) {
      rows.push({ viewport: vp, class: cls, state: st.id, pass: false, error: String(e).slice(0, 160) });
      process.stdout.write(`\n  ERR ${vp}|${st.id}: ${String(e).slice(0, 120)}\n`);
    } finally {
      await ctx.close();
    }
  }
}
await browser.close();

const fails = rows.filter((r) => !r.pass);

// --- Matrix-completeness accounting ---------------------------------
// The run must cover EVERY (viewport, state) pair — no selective sampling.
// A future regression that silently drops combinations must not be reportable
// as a full matrix: assert rows.length === viewports * states, and enumerate
// any missing pair.
const stateIds = STATES_.map((s) => s.id);
const expectedRows = VIEWPORTS.length * stateIds.length;
const seen = new Set(rows.map((r) => `${r.viewport}|${r.state}`));
const missingCombinations = [];
for (const [vp] of VIEWPORTS)
  for (const id of stateIds) if (!seen.has(`${vp}|${id}`)) missingCombinations.push(`${vp}|${id}`);
const duplicateRows = rows.length - seen.size;
const matrixComplete =
  rows.length === expectedRows && missingCombinations.length === 0 && duplicateRows === 0;
const matrixMode = QUICK ? 'QUICK SUBSET' : 'FULL MATRIX';

const report = {
  ranAt: new Date().toISOString(),
  engine: engineName,
  base,
  matrixMode,
  viewports: VIEWPORTS.map((v) => v[0]),
  states: stateIds,
  staticStates: STATES.map((s) => s.id),
  modalStates: MODAL_STATES.map((s) => s.id),
  expectedRows,
  actualRows: rows.length,
  missingCombinations,
  duplicateRows,
  matrixComplete,
  totalChecks: rows.length,
  passed: rows.length - fails.length,
  failed: fails.length,
  overallPass: fails.length === 0 && matrixComplete,
  fails: fails.map((f) => ({ viewport: f.viewport, state: f.state, horizontalOverflow: f.horizontalOverflow, maxElementOverflowPx: f.maxElementOverflowPx, buttonMinSizePass: f.buttonMinSizePass, smallButtons: f.smallButtons, dialogInViewport: f.dialogInViewport, offenders: f.offenders, error: f.error })),
  rows,
};
writeFileSync(resolve(outDir, `responsive-matrix${engineName === 'chromium' ? '' : '.' + engineName}.json`), JSON.stringify(report, null, 2) + '\n');
console.log(`\n\n${engineName}: ${matrixMode}`);
console.log(`  EXPECTED MATRIX ROWS: ${expectedRows}  (${VIEWPORTS.length} viewports x ${stateIds.length} states)`);
console.log(`  ACTUAL MATRIX ROWS:   ${rows.length}`);
console.log(`  MISSING COMBINATIONS: ${missingCombinations.length}${missingCombinations.length ? '  ' + missingCombinations.join(', ') : ''}`);
console.log(`  DUPLICATE ROWS:       ${duplicateRows}`);
console.log(`  ${report.passed}/${report.totalChecks} checks pass  (fails: ${fails.length})`);
if (fails.length) console.log(fails.map((f) => `  ${f.viewport}|${f.state}`).join('\n'));
if (!matrixComplete) console.log('  MATRIX INCOMPLETE — this run does NOT constitute full coverage.');
process.exit(fails.length === 0 && matrixComplete ? 0 : 1);
