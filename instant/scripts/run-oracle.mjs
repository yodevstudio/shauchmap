// Cross-runtime oracle: run every vector in packages/shauchmap_core/oracle
// through the COMPILED-JS brain (generated/shauchmap_core.js) in headless
// Chromium and assert byte-identical output vs the NATIVE-Dart expected.json.
//
// closes the last gap: the `freshness` section now runs through the
// real `evaluatePositionFreshness` interop function, so JS parity is 67/67.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
const instantRoot = resolve(here, '..');
const repoRoot = resolve(instantRoot, '..');
const oracleDir = join(repoRoot, 'packages', 'shauchmap_core', 'oracle');
const coreJs = join(instantRoot, 'generated', 'shauchmap_core.js');

for (const f of [coreJs, join(oracleDir, 'vectors.json'), join(oracleDir, 'expected.json')]) {
  if (!existsSync(f)) throw new Error(`missing ${f} — run npm run build:core / dart run tool/oracle_native.dart --gen`);
}

const V = JSON.parse(readFileSync(join(oracleDir, 'vectors.json'), 'utf8'));
const E = JSON.parse(readFileSync(join(oracleDir, 'expected.json'), 'utf8'));
const core = readFileSync(coreJs, 'utf8');

const EXPECTED_INTEROP_VERSION = 3;

const driver = `
addEventListener('load', () => {
  const C = globalThis.shauchmapCore;
  const out = { interopVersion: C.interopVersion, version: C.version, t: 0, p: 0, fail: 0, f: [] };
  const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const chk = (tag, got, want) => { out.t++; if (eq(got, want)) out.p++; else { out.fail++; out.f.push(tag); } };

  if (C.interopVersion !== ${EXPECTED_INTEROP_VERSION}) {
    document.getElementById('o').textContent = 'RESULT ' + JSON.stringify(
      { ...out, fail: 999, f: ['INTEROP VERSION MISMATCH got=' + C.interopVersion + ' want=${EXPECTED_INTEROP_VERSION}'] });
    return;
  }

  V.truth.forEach((v, i) => chk('T:' + v.name,
    JSON.parse(C.evaluateTruth(JSON.stringify(v.map))), E.truth[i].out));
  V.evidence.forEach((v, i) => chk('E:' + v.name,
    JSON.parse(C.evaluateEvidence(JSON.stringify(v.evidence_v2), V._nowMs)), E.evidence[i].out));
  V.go.forEach((v, i) => chk('G:' + v.name,
    JSON.parse(C.evaluateGo(JSON.stringify({ pool: v.pool }), v.nowMs)), E.go[i].out));
  V.revalidation.forEach((v, i) => chk('R:' + v.name,
    JSON.parse(C.evaluateRevalidation(JSON.stringify({ targetId: v.targetId, stale: v.stale, fresh: v.fresh }))),
    E.revalidation[i].out));
  (V.freshness || []).forEach((v, i) => chk('F:' + v.name,
    JSON.parse(C.evaluatePositionFreshness(JSON.stringify(
      { positionTsMs: v.positionTsMs, nowMs: v.nowMs, maxAgeSeconds: v.maxAgeSeconds }))),
    E.freshness[i].out));
  (V.distances || []).forEach((v, i) => chk('D:' + v.name,
    JSON.parse(C.evaluateDistances(JSON.stringify({ from: v.from, to: v.to }))),
    E.distances[i].out));
  (V.hint || []).forEach((v, i) => chk('H:' + v.name,
    JSON.parse(C.evaluateGo(JSON.stringify({ pool: v.pool, hintId: v.hintId }), v.nowMs)),
    E.hint[i].out));

  document.getElementById('o').textContent = 'RESULT ' + JSON.stringify(out);
});
`;

const html = `<!doctype html><meta charset=utf-8><title>oracle</title><pre id=o>pending</pre>
<script>const V=${JSON.stringify(V)};const E=${JSON.stringify(E)};</script>
<script>${core}</script>
<script>${driver}</script>`;

const work = join(tmpdir(), 'shauchmap-instant-oracle-' + Date.now());
mkdirSync(work, { recursive: true });
const htmlFile = join(work, 'oracle.html');
writeFileSync(htmlFile, html);

function findChrome() {
  const cands = [
    process.env.CHROME_BIN,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    '/usr/bin/google-chrome',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ].filter(Boolean);
  for (const c of cands) if (existsSync(c)) return c;
  throw new Error('Chrome not found; set CHROME_BIN');
}

const chrome = findChrome();
const profileDir = join(work, 'cprofile');
mkdirSync(profileDir, { recursive: true });
const dump = execFileSync(
  chrome,
  [
    '--headless=new',
    '--disable-gpu',
    '--no-sandbox',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--disable-background-networking',
    '--disable-sync',
    '--disable-default-apps',
    `--user-data-dir=${profileDir}`,
    '--virtual-time-budget=8000',
    '--dump-dom',
    'file://' + htmlFile.replace(/\\/g, '/'),
  ],
  { encoding: 'utf8', timeout: 60000 },
);

const match = dump.match(/RESULT (\{.*\})/);
if (!match) {
  console.error(dump.slice(0, 2000));
  throw new Error('no RESULT token in headless Chrome output');
}
const res = JSON.parse(match[1]);
rmSync(work, { recursive: true, force: true });

const nativeCount =
  E.truth.length +
  E.evidence.length +
  E.go.length +
  E.revalidation.length +
  E.freshness.length +
  (E.distances?.length ?? 0) + (E.hint?.length ?? 0);
const specCorpus =
  E.truth.length + E.evidence.length + E.go.length + E.revalidation.length + E.freshness.length;

console.log(`CHROMIUM oracle: ${res.p}/${res.t}  (interopVersion=${res.interopVersion}, ${res.version})`);
console.log(
  `NATIVE expected: ${nativeCount} vectors  (t${E.truth.length} e${E.evidence.length} g${E.go.length} r${E.revalidation.length} f${E.freshness.length} d${E.distances?.length ?? 0} h${E.hint?.length ?? 0})`,
);
console.log(`  spec corpus (8.0B + freshness): ${specCorpus}/${specCorpus}`);
if (res.f.length) console.log('FAILS:\n  ' + res.f.join('\n  '));

function chromeVersion() {
  try {
    // `chrome.exe --version` hangs on Windows; read the product version off disk.
    const v = execFileSync(
      'powershell',
      ['-NoProfile', '-Command', `(Get-Item '${chrome}').VersionInfo.ProductVersion`],
      { encoding: 'utf8', timeout: 10000 },
    ).trim();
    return v ? `Chrome ${v}` : 'Chrome (version unknown)';
  } catch {
    return 'Chrome (version unknown)';
  }
}

const report = {
  ranAt: new Date().toISOString(),
  chrome: chromeVersion(),
  interopVersion: res.interopVersion,
  coreVersion: res.version,
  chromium: { pass: res.p, total: res.t, fail: res.fail },
  native: { total: nativeCount, specCorpus, sections: {
    truth: E.truth.length, evidence: E.evidence.length, go: E.go.length,
    revalidation: E.revalidation.length, freshness: E.freshness.length,
    distances: E.distances?.length ?? 0, hint: E.hint?.length ?? 0 } },
  fails: res.f,
};
mkdirSync(join(instantRoot, 'generated'), { recursive: true });
writeFileSync(join(instantRoot, 'generated', 'oracle-result.json'), JSON.stringify(report, null, 2) + '\n');

if (res.p !== res.t || res.t !== nativeCount) {
  console.error(`ORACLE FAIL: chromium ${res.p}/${res.t}, native ${nativeCount}`);
  process.exit(1);
}
console.log(`ORACLE OK: native ${nativeCount}/${nativeCount}  ==  chromium ${res.p}/${res.t}`);
