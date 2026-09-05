// Pure helpers for the 15 km geohash sweep . Kept free of the
// Firebase SDK so the merge / dedupe / "a bound failed" logic is unit-testable.
import { geohashQueryBounds, type GeohashRange } from 'geofire-common';
import type { RawToiletDoc } from './source';

export type Bound = GeohashRange; // [startHash, endHash]

export function boundsFor(user: { lat: number; lng: number }, radiusMeters: number): Bound[] {
  return geohashQueryBounds([user.lat, user.lng], radiusMeters) as Bound[];
}

export interface BoundOutcome {
  bound: Bound;
  docs?: RawToiletDoc[];
  error?: unknown;
}

/**
 * Merge every bound's docs, dedupe by id. If ANY bound errored we do NOT return
 * a partial set — the caller must surface an honest failure (: "do NOT
 * silently drop a successful bound because another fails").
 */
export function mergeBoundOutcomes(outcomes: BoundOutcome[]): {
  docs: RawToiletDoc[];
  failedBounds: number;
} {
  const failedBounds = outcomes.filter((o) => o.error !== undefined).length;
  const byId = new Map<string, RawToiletDoc>();
  for (const o of outcomes) {
    if (o.error !== undefined || !o.docs) continue;
    for (const d of o.docs) if (!byId.has(d.id)) byId.set(d.id, d);
  }
  return { docs: [...byId.values()], failedBounds };
}
