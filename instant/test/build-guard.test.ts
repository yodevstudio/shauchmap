import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const script = resolve(__dirname, '../scripts/validate-firebase-env.mjs');

// Isolate the guard from any local instant/.env.local — read env files from an
// empty temp dir so only the explicit env we pass is seen.
let emptyEnvDir: string;
beforeAll(() => {
  emptyEnvDir = mkdtempSync(join(tmpdir(), 'sm-envguard-'));
});
afterAll(() => {
  rmSync(emptyEnvDir, { recursive: true, force: true });
});

function run(env: Record<string, string>): { code: number; out: string } {
  const clean: Record<string, string | undefined> = { ...process.env };
  for (const k of Object.keys(clean)) if (k.startsWith('VITE_')) delete clean[k];
  try {
    const out = execFileSync('node', [script], {
      encoding: 'utf8',
      env: { ...clean, SHAUCHMAP_ENV_DIR: emptyEnvDir, ...env, VITE_DATA_MODE: env.VITE_DATA_MODE ?? '' },
    });
    return { code: 0, out };
  } catch (e: any) {
    return { code: e.status ?? 1, out: (e.stdout ?? '') + (e.stderr ?? '') };
  }
}

describe('Firebase production build guard ', () => {
  it('BLOCKS with no data mode', () => {
    const r = run({});
    expect(r.code).toBe(1);
    expect(r.out).toMatch(/VITE_DATA_MODE must be "firebase"/);
  });

  it('BLOCKS fixture mode', () => {
    const r = run({ VITE_DATA_MODE: 'fixture' });
    expect(r.code).toBe(1);
    expect(r.out).toMatch(/must be "firebase"/);
  });

  it('BLOCKS firebase mode with every key missing (names each)', () => {
    const r = run({ VITE_DATA_MODE: 'firebase' });
    expect(r.code).toBe(1);
    for (const k of [
      'VITE_FIREBASE_API_KEY',
      'VITE_FIREBASE_PROJECT_ID',
      'VITE_FIREBASE_APP_ID',
      'VITE_FIREBASE_DATABASE_ID',
    ]) {
      expect(r.out).toContain(k);
    }
  });

  it.each([
    'VITE_FIREBASE_API_KEY',
    'VITE_FIREBASE_PROJECT_ID',
    'VITE_FIREBASE_APP_ID',
    'VITE_FIREBASE_DATABASE_ID',
  ])('BLOCKS firebase mode when %s alone is missing', (missing) => {
    const full: Record<string, string> = {
      VITE_DATA_MODE: 'firebase',
      VITE_FIREBASE_API_KEY: 'a',
      VITE_FIREBASE_PROJECT_ID: 'p',
      VITE_FIREBASE_APP_ID: 'x',
      VITE_FIREBASE_DATABASE_ID: '(default)',
    };
    delete full[missing];
    const r = run(full);
    expect(r.code).toBe(1);
    expect(r.out).toContain(missing);
  });

  it('PASSES with firebase mode + all keys, and never prints a credential value', () => {
    const r = run({
      VITE_DATA_MODE: 'firebase',
      VITE_FIREBASE_API_KEY: 'AIzaSecretDoNotPrint123456',
      VITE_FIREBASE_PROJECT_ID: 'demo-shauchmap-test',
      VITE_FIREBASE_APP_ID: '1:2:web:deadbeef',
      VITE_FIREBASE_DATABASE_ID: '(default)',
    });
    expect(r.code).toBe(0);
    expect(r.out).toMatch(/Firebase env OK/);
    expect(r.out).not.toContain('AIzaSecretDoNotPrint123456');
    expect(r.out).not.toContain('1:2:web:deadbeef');
  });
});
