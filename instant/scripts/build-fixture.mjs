// Force a FIXTURE-mode production build even when instant/.env.local exists
// and sets VITE_DATA_MODE=firebase. A shell VITE_ var wins over .env.local
// in Vite, so we set it here and run the normal build.
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const env = { ...process.env, VITE_DATA_MODE: 'fixture' };
for (const k of Object.keys(env)) if (/^VITE_FIREBASE_/.test(k)) delete env[k];
const run = (args) => execFileSync('node', args, { cwd: root, stdio: 'inherit', env });

console.log('[build:fixture] forcing VITE_DATA_MODE=fixture');
run([resolve(root, 'scripts/build-core.mjs')]);
run([resolve(root, 'node_modules/typescript/bin/tsc'), '--noEmit']);
run([resolve(root, 'node_modules/vite/bin/vite.js'), 'build']);
