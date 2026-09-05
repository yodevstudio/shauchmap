// Loads the compiled Dart brain (generated/shauchmap_core.js) in the BROWSER
// and hands back the raw `globalThis.shauchmapCore`. The generated file is a
// classic IIFE that installs a global — not an ES module, never hand-edited.
//
// It is injected as a <script src>, deliberately kept out of the module graph.
// (Node/Vitest use core-loader.node.ts instead — no node builtins here, so the
// browser bundle stays clean.)

import type { ShauchmapCoreGlobal } from './types';

// Vite rewrites this to the emitted asset URL at build time.
import coreUrl from '../../generated/shauchmap_core.js?url';

let cached: Promise<ShauchmapCoreGlobal> | null = null;

function fromGlobal(): ShauchmapCoreGlobal | undefined {
  return (globalThis as { shauchmapCore?: ShauchmapCoreGlobal }).shauchmapCore;
}

/** Idempotent. Resolves to the raw core global (unversioned — use interop.ts). */
export function loadCoreGlobal(): Promise<ShauchmapCoreGlobal> {
  if (cached) return cached;
  cached = (async () => {
    const existing = fromGlobal();
    if (existing) return existing;
    await new Promise<void>((resolve, reject) => {
      const s = document.createElement('script');
      s.src = coreUrl;
      s.async = false;
      s.onload = () => resolve();
      s.onerror = () => reject(new Error(`failed to load core brain: ${coreUrl}`));
      document.head.appendChild(s);
    });
    const core = fromGlobal();
    if (!core) throw new Error('core brain loaded but globalThis.shauchmapCore is missing');
    return core;
  })();
  return cached;
}

/** Test-only: drop the memoized promise. */
export function __resetCoreForTests(): void {
  cached = null;
}
