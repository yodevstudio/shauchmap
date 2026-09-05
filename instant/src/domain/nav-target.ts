// FRESH metadata for a specific navigation target after revalidation .
// NEVER substitutes the GO-selected toilet's distance/name for an alternative
// or a /t/:id focus target.

import type { GoResult } from './resolve-go';
import { poolEntry } from './resolve-go';

export interface TargetMeta {
  name: string;
  distanceMeters: number | null;
  /** 'selected' | 'alternative' | 'focus' | 'unknown' — for tests / diagnostics. */
  kind: 'selected' | 'alternative' | 'focus' | 'unknown';
}

function nameOf(map: Record<string, unknown> | undefined, fallback: string): string {
  const n = map?.['name'];
  return typeof n === 'string' && n.trim() ? n : fallback;
}

export function freshTargetMeta(fresh: GoResult, targetId: string | null): TargetMeta {
  const entry = poolEntry(fresh.pool, targetId);
  const name = nameOf(entry?.map, targetId ?? 'the facility');

  if (targetId && targetId === fresh.go.selectedId) {
    return { name, distanceMeters: fresh.go.selectedDistanceMeters, kind: 'selected' };
  }
  if (targetId) {
    // A /t/:id focus wins the label even though the same toilet also appears in
    // `alternatives` — distance is identical, but the kind is the meaningful one.
    if (fresh.focus && fresh.focus.id === targetId) {
      return { name, distanceMeters: fresh.focus.distanceMeters, kind: 'focus' };
    }
    const alt = fresh.go.alternatives.find((a) => a.id === targetId);
    if (alt) return { name, distanceMeters: alt.distanceMeters, kind: 'alternative' };
  }
  return { name, distanceMeters: entry ? entry.distanceMeters : null, kind: 'unknown' };
}
