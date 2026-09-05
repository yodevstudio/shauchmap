// Production-build performance measurement .
//   - static: gzip + brotli of every dist asset, grouped
//   - runtime: mobile-throttled (Fast-3G + 4x CPU) load of /go, median of N runs
//     FCP, time-to-usable (recommendation card visible), total transfer.
// Requires: npm run build  &&  npm run preview  (port 4174)
import { chromium } from 'playwright';
import { gzipSync, brotliCompressSync, constants as zc } from 'node:zlib';
import { readFileSync, readdirSync, statSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve, extname } from 'node:path';

const dist = resolve('dist');
const base = process.argv[2] ?? 'http://127.0.0.1:4174';
const outDir = resolve(process.argv[3] ?? 'generated');
const RUNS = 5;

// ---------- static sizes ----------
function walk(dir) {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}
const br = (b) => brotliCompressSync(b, { params: { [zc.BROTLI_PARAM_QUALITY]: 11 } }).length;
const gz = (b) => gzipSync(b, { level: 9 }).length;

const files = walk(dist).filter((f) => !/\.map$/.test(f));
const groups = {
  html: /\.html$/,
  css: /\.css$/,
  'dart-core': /shauchmap_core-.*\.js$/,
  'app-js': /assets[\\/]index-.*\.js$/,
  'preact-vendor': /assets[\\/](preact|workbox-window).*\.js$/,
  'firebase (not in shell)': /firebase-.*\.js$/,
  'geofire (not in shell)': /geofire-.*\.js$/,
  'firestore-source (not in shell)': /firestore-source-.*\.js$/,
  sw: /(sw|workbox-[a-f0-9]+)\.js$/,
  manifest: /\.webmanifest$/,
  icons: /icons[\\/].*\.(svg|png)$/,
};
const staticRows = [];
for (const [name, re] of Object.entries(groups)) {
  const gf = files.filter((f) => re.test(f));
  if (!gf.length) continue;
  let raw = 0,
    g = 0,
    b = 0;
  for (const f of gf) {
    const buf = readFileSync(f);
    raw += buf.length;
    g += gz(buf);
    b += br(buf);
  }
  staticRows.push({ group: name, files: gf.length, raw, gzip: g, brotli: b });
}

// what the browser actually pulls on a cold /go (fixture mode): shell only
const shellRe = [groups.html, groups.css, groups['dart-core'], groups['app-js'], groups['preact-vendor'], groups.manifest, /icons[\\/]icon\.svg$/];
let shellRaw = 0,
  shellGz = 0,
  shellBr = 0;
for (const f of files) {
  if (shellRe.some((re) => re.test(f))) {
    const buf = readFileSync(f);
    shellRaw += buf.length;
    shellGz += gz(buf);
    shellBr += br(buf);
  }
}

// precache manifest size from sw.js
let precache = null;
try {
  const sw = readFileSync(join(dist, 'sw.js'), 'utf8');
  const m = [...sw.matchAll(/\{url:/g)];
  const bytes = [...sw.matchAll(/url:"([^"]+)"/g)]
    .map((x) => x[1])
    .map((u) => {
      try {
        return statSync(join(dist, u)).size;
      } catch {
        return 0;
      }
    })
    .reduce((a, b) => a + b, 0);
  precache = { entries: m.length, rawBytes: bytes };
} catch {
  /* ignore */
}

// ---------- runtime, throttled, median of N ----------
const url = `${base}/go?demo=default&loc=26.2389,73.0243`;
const browser = await chromium.launch();
const runs = [];
for (let i = 0; i < RUNS; i++) {
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    serviceWorkers: 'block',
  });
  const page = await ctx.newPage();
  const client = await ctx.newCDPSession(page);
  await client.send('Network.enable');
  await client.send('Network.emulateNetworkConditions', {
    offline: false,
    latency: 150, // Fast 3G-ish
    downloadThroughput: (1.6 * 1024 * 1024) / 8,
    uploadThroughput: (750 * 1024) / 8,
  });
  await client.send('Emulation.setCPUThrottlingRate', { rate: 4 });

  let transferred = 0;
  client.on('Network.loadingFinished', (e) => {
    transferred += e.encodedDataLength || 0;
  });

  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'commit' });
  await page.waitForSelector('.card[aria-label="Recommended toilet"], .state', { timeout: 20000 });
  const usableMs = Date.now() - t0;
  // let trailing resources settle before reading the transfer total
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForTimeout(300);

  const fcp = await page.evaluate(
    () =>
      new Promise((res) => {
        const e = performance.getEntriesByName('first-contentful-paint')[0];
        if (e) return res(e.startTime);
        new PerformanceObserver((list, obs) => {
          const p = list.getEntriesByName('first-contentful-paint')[0];
          if (p) {
            obs.disconnect();
            res(p.startTime);
          }
        }).observe({ type: 'paint', buffered: true });
        setTimeout(() => res(null), 3000);
      }),
  );

  runs.push({ fcpMs: fcp == null ? null : Math.round(fcp), usableMs, transferBytes: transferred });
  await ctx.close();
}
await browser.close();

const median = (xs) => {
  const s = [...xs].filter((x) => x != null).sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : null;
};
const runtime = {
  runs,
  medianFcpMs: median(runs.map((r) => r.fcpMs)),
  medianUsableMs: median(runs.map((r) => r.usableMs)),
  medianTransferBytes: median(runs.map((r) => r.transferBytes)),
  throttle: 'CDP Fast-3G (1.6 Mbps / 150 ms RTT) + 4x CPU',
};

const report = {
  measuredAt: new Date().toISOString(),
  static: {
    groups: staticRows,
    coldGoShell: { raw: shellRaw, gzip: shellGz, brotli: shellBr },
    precache,
    note: 'coldGoShell = html+css+dart-core+app-js+preact/workbox-window+manifest+icon.svg (fixture mode). Firebase/geofire/firestore-source are async chunks, never loaded in fixture mode and excluded from the SW precache.',
  },
  runtime,
};
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'perf-report.json'), JSON.stringify(report, null, 2) + '\n');

const kb = (n) => (n / 1024).toFixed(1) + ' KB';
console.log('\n=== STATIC (dist) ===');
for (const r of staticRows) console.log(`  ${r.group.padEnd(30)} raw ${kb(r.raw).padStart(9)}  gzip ${kb(r.gzip).padStart(9)}  brotli ${kb(r.brotli).padStart(9)}`);
console.log(`  ${'COLD /go SHELL'.padEnd(30)} raw ${kb(shellRaw).padStart(9)}  gzip ${kb(shellGz).padStart(9)}  brotli ${kb(shellBr).padStart(9)}`);
console.log(`  precache entries: ${precache?.entries ?? '?'}`);
console.log('\n=== RUNTIME (mobile throttled, median of ' + RUNS + ') ===');
console.log(`  FCP:            ${runtime.medianFcpMs} ms`);
console.log(`  time-to-usable: ${runtime.medianUsableMs} ms`);
console.log(`  transfer:       ${kb(runtime.medianTransferBytes)}`);
console.log(`\nwrote ${join(outDir, 'perf-report.json')}`);
