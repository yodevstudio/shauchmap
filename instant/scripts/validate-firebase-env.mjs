// Pre-build guard for the FIREBASE production path .
//
// `npm run build:firebase` runs this FIRST. It refuses to continue unless the
// resolved env has VITE_DATA_MODE=firebase and every required Firebase Web value
// present and non-empty. It never prints a credential value — only which keys
// are missing.
//
// The default `npm run build` (fixture mode) is fine for local dev, screenshots
// and tests; a real Firebase Hosting deploy MUST use `npm run build:firebase`.
import { loadEnv } from 'vite';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Env files are read from SHAUCHMAP_ENV_DIR when set (CI / tests isolate here),
// otherwise from the instant/ project root.
const root = process.env.SHAUCHMAP_ENV_DIR
  ? resolve(process.env.SHAUCHMAP_ENV_DIR)
  : resolve(dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.env.NODE_ENV === 'development' ? 'development' : 'production';
// loadEnv merges .env, .env.local, .env.[mode], .env.[mode].local (prefix VITE_).
const env = { ...loadEnv(mode, root, 'VITE_'), ...pickVite(process.env) };

function pickVite(o) {
  const out = {};
  for (const [k, v] of Object.entries(o)) if (k.startsWith('VITE_')) out[k] = v;
  return out;
}

const errors = [];
const dm = (env.VITE_DATA_MODE ?? '').trim().toLowerCase();
if (dm !== 'firebase') {
  errors.push(
    dm === '' || dm === 'fixture'
      ? `VITE_DATA_MODE must be "firebase" for a Firebase production build (got ${dm === '' ? 'unset' : `"${dm}"`}).`
      : `VITE_DATA_MODE must be "firebase" (got "${dm}").`,
  );
}
const REQUIRED = [
  'VITE_FIREBASE_API_KEY',
  'VITE_FIREBASE_PROJECT_ID',
  'VITE_FIREBASE_APP_ID',
  'VITE_FIREBASE_DATABASE_ID',
];
for (const key of REQUIRED) {
  if (!env[key] || !String(env[key]).trim()) errors.push(`${key} is missing or empty.`);
}

if (errors.length) {
 console.error('\n✗ Firebase production build blocked — fail-closed :');
  for (const e of errors) console.error(`  • ${e}`);
  console.error('\n  Set these in .env.local (see .env.example). No credential values are printed.');
  console.error('  For local dev / screenshots / tests use `npm run build` (fixture mode).\n');
  process.exit(1);
}

console.log(
  `✓ Firebase env OK — VITE_DATA_MODE=firebase, all required keys present ` +
    `(project ${String(env.VITE_FIREBASE_PROJECT_ID).slice(0, 3)}…, db ${env.VITE_FIREBASE_DATABASE_ID}). ` +
    `Proceeding with the guarded production build.`,
);
