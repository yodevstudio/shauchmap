// Node/Vitest loader for the compiled Dart brain. Reads generated/
// shauchmap_core.js from disk and evaluates it with a minimal `self` shim.
// Never imported by the browser bundle.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import type { ShauchmapCoreGlobal } from './types';

let cached: ShauchmapCoreGlobal | null = null;

export function loadCoreGlobalNode(): ShauchmapCoreGlobal {
  if (cached) return cached;
  const existing = (globalThis as { shauchmapCore?: ShauchmapCoreGlobal }).shauchmapCore;
  if (existing) {
    cached = existing;
    return existing;
  }
  const here = dirname(fileURLToPath(import.meta.url));
  const file = resolve(here, '../../generated/shauchmap_core.js');
  const src = readFileSync(file, 'utf8');
  const g = globalThis as Record<string, unknown>;
  if (typeof g.self === 'undefined') g.self = globalThis;
  // eslint-disable-next-line @typescript-eslint/no-implied-eval
  new Function(src)();
  const core = (globalThis as { shauchmapCore?: ShauchmapCoreGlobal }).shauchmapCore;
  if (!core) throw new Error('core brain evaluated but globalThis.shauchmapCore is missing');
  cached = core;
  return core;
}
