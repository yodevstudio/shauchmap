// Offline app-shell deep-link check .
//   1. load the app once online, wait for the service worker to activate
//   2. go offline
//   3. hard-navigate directly to /go, /t/:id, /q/:id
//   4. assert: the cached SHELL loads, an HONEST offline state shows, and NO
//      recommendation card is rendered.
// Requires:  npm run build && npm run preview   (port 4174)
import { chromium } from 'playwright';

const base = process.argv[2] ?? 'http://127.0.0.1:4174';
const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  serviceWorkers: 'allow',
  geolocation: { latitude: 26.2389, longitude: 73.0243 },
  permissions: ['geolocation'],
});

const fails = [];
const ok = (cond, msg) => {
  console.log(`  ${cond ? '✓' : '✗'} ${msg}`);
  if (!cond) fails.push(msg);
};

try {
  const boot = await ctx.newPage();
  await boot.goto(base + '/', { waitUntil: 'load' });
  // wait for the SW to control the page
  await boot.waitForFunction(
    () => navigator.serviceWorker && navigator.serviceWorker.controller != null,
    { timeout: 15000 },
  );
  console.log('online: service worker active + controlling');
  await boot.close();

  await ctx.setOffline(true);
  console.log('offline: true\n');

  for (const path of ['/go?loc=26.2389,73.0243', '/t/demo_clock_pay?loc=26.2389,73.0243', '/q/RJQUEST26?loc=26.2389,73.0243']) {
    const p = await ctx.newPage();
    let navErr = null;
    await p.goto(base + path, { waitUntil: 'load' }).catch((e) => (navErr = e));
    await p.waitForTimeout(1500);
    const title = await p.title().catch(() => '');
    const text = ((await p.textContent('body').catch(() => '')) || '').toLowerCase();
    const hasShell = title === 'ShauchMap Instant' && (await p.$('#app')) != null;
    const hasRec = (await p.$('.card[aria-label="Recommended toilet"]')) != null;
    const honest =
      /offline/.test(text) || /needs a connection/.test(text) || (await p.$('.state')) != null;

    console.log(`direct offline nav -> ${path}`);
    ok(navErr == null, 'navigation resolved from cache (no network error)');
    ok(hasShell, 'cached app shell loaded (title + #app)');
    ok(honest, 'honest offline / error state shown');
    ok(!hasRec, 'NO recommendation card rendered offline');
    console.log('');
    await p.close();
  }
} finally {
  await browser.close();
}

if (fails.length) {
  console.error(`OFFLINE CHECK FAILED (${fails.length}):\n  - ${fails.join('\n  - ')}`);
  process.exit(1);
}
console.log('OFFLINE CHECK PASS — shell offline for /go, /t/:id, /q/:id; no cached recommendation.');
