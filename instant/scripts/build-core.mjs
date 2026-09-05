// Deterministic build of the ONE authoritative ShauchMap domain core.
//
//   packages/shauchmap_core/tool/interop_entry.dart   --(dart compile js -O2)-->
//   instant/generated/shauchmap_core.js
//
// This compiles the REAL package (via its path dependency), never a fork.
// Do not hand-edit the generated output. `npm run dev` / `npm run build` call
// this first (predev / prebuild).
import { execFileSync } from 'node:child_process';
import { gzipSync, brotliCompressSync, constants as zc } from 'node:zlib';
import { existsSync, mkdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const instantRoot = resolve(here, '..');
const repoRoot = resolve(instantRoot, '..');
const pkgDir = join(repoRoot, 'packages', 'shauchmap_core');
const entry = join(pkgDir, 'tool', 'interop_entry.dart');
const outDir = join(instantRoot, 'generated');
const outFile = join(outDir, 'shauchmap_core.js');
const metaFile = join(outDir, 'shauchmap_core.meta.json');

function findDart() {
  if (process.env.DART && existsSync(process.env.DART)) return process.env.DART;
  const candidates = [
    'dart',
    'C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe',
    join(process.env.FLUTTER_ROOT ?? '', 'bin/cache/dart-sdk/bin/dart.exe'),
    join(process.env.HOME ?? process.env.USERPROFILE ?? '', 'flutter/bin/cache/dart-sdk/bin/dart'),
  ].filter(Boolean);
  for (const c of candidates) {
    try {
      execFileSync(c, ['--version'], { stdio: 'ignore' });
      return c;
    } catch {
      /* try next */
    }
  }
  throw new Error('Dart SDK not found. Set DART=/path/to/dart or FLUTTER_ROOT.');
}

if (!existsSync(entry)) throw new Error(`interop entry missing: ${entry}`);
mkdirSync(outDir, { recursive: true });

const dart = findDart();
const dartVersion = execFileSync(dart, ['--version'], { encoding: 'utf8' }).trim();

console.log(`[build:core] ${dartVersion}`);
console.log(`[build:core] dart compile js -O2  ${entry}`);
execFileSync(
  dart,
  ['compile', 'js', '-O2', '--no-source-maps', '-o', outFile, entry],
  { cwd: pkgDir, stdio: 'inherit' },
);

// dart compile js also emits <out>.deps — harmless, leave it.
const raw = readFileSync(outFile);
const gz = gzipSync(raw, { level: 9 });
const br = brotliCompressSync(raw, {
  params: { [zc.BROTLI_PARAM_QUALITY]: 11, [zc.BROTLI_PARAM_SIZE_HINT]: raw.length },
});

// Pull the interop version straight out of the compiled artifact as a smoke check.
const m = raw.toString('utf8').match(/interopVersion['"]?\s*[:=]\s*(\d+)/);
const meta = {
  builtAt: new Date().toISOString(),
  dartVersion,
  entry: 'packages/shauchmap_core/tool/interop_entry.dart',
  command: `dart compile js -O2 --no-source-maps -o generated/shauchmap_core.js ${entry.replace(repoRoot + '\\', '').replace(/\\/g, '/')}`,
  bytes: { raw: raw.length, gzip: gz.length, brotli: br.length },
  interopVersionInArtifact: m ? Number(m[1]) : null,
  bannedTokens: ['flutter', 'firebase', 'geolocator', 'cloud_firestore'].filter((t) =>
    new RegExp(`\\b${t}\\b`, 'i').test(raw.toString('utf8')),
  ),
};
writeFileSync(metaFile, JSON.stringify(meta, null, 2) + '\n');

const kb = (n) => (n / 1024).toFixed(1) + ' KB';
console.log(
  `[build:core] shauchmap_core.js  raw ${kb(raw.length)}  gzip ${kb(gz.length)}  brotli ${kb(br.length)}`,
);
if (meta.bannedTokens.length) {
  console.error(`[build:core] FAIL banned tokens in core: ${meta.bannedTokens.join(', ')}`);
  process.exit(1);
}
const GUARD_KB = 40;
if (br.length > GUARD_KB * 1024) {
  console.error(`[build:core] FAIL brotli ${kb(br.length)} > ${GUARD_KB} KB guard`);
  process.exit(1);
}
console.log(`[build:core] OK  (brotli guard <= ${GUARD_KB} KB, banned deps: none)  size ${statSync(outFile).size}`);
