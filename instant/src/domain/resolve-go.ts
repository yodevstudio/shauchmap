// pool -> shared-core GO. The web shell NEVER reinterprets the decision; it
// only reads GoJson (esp. `presentation` and, for /t/:id, `focus`).
//
// /t/:id HINT SEMANTICS are the frozen Android contract, computed by the shared
// core (`resolveHintFocus` / `findInActiveTier` / `goAlternativeFromTarget` /
// `presentGoAlternative`) and returned as `go.focus`. The hint NEVER gains
// recommendation authority — FOCUS != SELECTED.

import type { ShauchmapCore } from '../core/interop';
import type { GoFocusJson, GoInputItem, GoJson } from '../core/types';
import type { GoPool, PoolEntry } from './geo-pool';

export interface GoResult {
  go: GoJson;
  pool: GoPool;
  nowMs: number;
  /** Toilet id passed as a /t/:id hint, if any. A HINT only — never forced. */
  hintId: string | null;
  /** Shared-core focus: the hinted alternative to render as the MAIN card, or
   *  null when there is no hint / the hint is the selected toilet / the hint is
   *  not in the fresh active tier. */
  focus: GoFocusJson | null;
  /** true when a real (non-empty) hint was given but the core returned no focus
   *  AND the hint is not simply the selected toilet — i.e. absent / ineligible /
   *  lower-tier. Drives the "showing the current top pick instead" note. */
  hintIneligible: boolean;
}

function toInputs(entries: PoolEntry[]): GoInputItem[] {
  return entries.map((e) => ({ id: e.id, distanceMeters: e.distanceMeters, map: e.map }));
}

export function runGo(params: {
  core: ShauchmapCore;
  pool: GoPool;
  nowMs?: number;
  hintId?: string | null;
}): GoResult {
  const nowMs = params.nowMs ?? Date.now();
  const hintId = params.hintId ?? null;
  const go = params.core.evaluateGo(toInputs(params.pool.entries), nowMs, hintId);
  const focus = go.focus ?? null;
  const realHint = hintId != null && hintId !== '';
  const hintIsSelected = realHint && hintId === go.selectedId;
  return {
    go,
    pool: params.pool,
    nowMs,
    hintId,
    focus,
    hintIneligible: realHint && !hintIsSelected && focus == null && go.selectedId != null,
  };
}

/** Look up one pool entry (for rendering a facility's own coords/name). */
export function poolEntry(pool: GoPool, id: string | null): PoolEntry | null {
  if (!id) return null;
  return pool.entries.find((e) => e.id === id) ?? null;
}

/** The id the user's Navigate action targets: the focused alternative when a
 *  /t/:id focus is active, otherwise the GO-selected toilet. FOCUS != SELECTED —
 *  this never mutates `go.selectedId`. */
export function primaryTargetId(r: GoResult): string | null {
  return r.focus ? r.focus.id : r.go.selectedId;
}
