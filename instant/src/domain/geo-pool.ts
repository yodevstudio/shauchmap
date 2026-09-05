// Build the COMPLETE strict-15 km GO universe .
//
//   load candidates (superset)  ->  normalize each doc  ->  canonical
//   shared-core distance (core.evaluateDistances)  ->  strict <= 15,000 m
//   ->  deterministic (distance, then id) ordering  ->  NO cap.
//
// GO then receives the whole set. No pre-ranking, no "nearest 50".

import type { ShauchmapCore } from '../core/interop';
import type { CanonicalValue } from '../core/types';
import { isOnline } from '../data/connectivity';
import { normalizeFirestoreDoc } from '../data/normalize';
import {
  DataUnavailableError,
  type LoadOpts,
  type RawToiletDoc,
  type ToiletSource,
} from '../data/source';

export const GO_RADIUS_METERS = 15_000;
export const GO_POOL_TIMEOUT_MS = 8_000;

export interface PoolEntry {
  id: string;
  distanceMeters: number;
  /** Normalized, canonical-JSON doc map fed to the core. */
  map: Record<string, CanonicalValue>;
  lat: number;
  lng: number;
}

export interface GoPool {
  user: { lat: number; lng: number };
  /** Strict <= 15 km, sorted by (distance, id). Complete — never capped. */
  entries: PoolEntry[];
  /** Candidates the source returned before the strict cutoff. */
  candidateCount: number;
  radiusMeters: number;
}

function numAt(map: Record<string, CanonicalValue>, key: string): number | null {
  const v = map[key];
  return typeof v === 'number' ? v : null;
}

/** Acquire + tighten the pool. Throws DataUnavailableError on honest failure. */
export async function acquireGoPool(params: {
  source: ToiletSource;
  core: ShauchmapCore;
  user: { lat: number; lng: number };
  timeoutMs?: number;
  /** Test seam — skip the network connectivity probe. */
  skipConnectivityCheck?: boolean;
}): Promise<GoPool> {
  const { source, core, user } = params;
  const timeoutMs = params.timeoutMs ?? GO_POOL_TIMEOUT_MS;

  // Never present cached/local data as "current toilet status" while offline
 // . This holds for BOTH fixture and Firebase sources.
  if (!params.skipConnectivityCheck && !(await isOnline())) {
    throw new DataUnavailableError(
      "You're offline. ShauchMap Instant needs a connection to refresh toilet status.",
      'offline',
    );
  }

  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  let raw: RawToiletDoc[];
  try {
    const opts: LoadOpts = { radiusMeters: GO_RADIUS_METERS, signal: ac.signal };
    raw = await Promise.race([
      source.loadCandidates(user, opts),
      new Promise<never>((_, reject) =>
        ac.signal.addEventListener('abort', () =>
          reject(new DataUnavailableError('Finding nearby toilets took too long.', 'timeout')),
        ),
      ),
    ]);
  } finally {
    clearTimeout(timer);
  }

  // Normalize every candidate; keep only those with real coordinates.
  const normalized = raw
    .map((d) => ({ id: d.id, map: normalizeFirestoreDoc(d.data) }))
    .map((d) => ({
      ...d,
      lat: numAt(d.map, 'latitude'),
      lng: numAt(d.map, 'longitude'),
    }))
    .filter((d): d is { id: string; map: Record<string, CanonicalValue>; lat: number; lng: number } =>
      d.lat !== null && d.lng !== null,
    );

  // ONE canonical distance call for the whole set — no TS trigonometry.
  const distances =
    normalized.length === 0
      ? []
      : core.evaluateDistances({
          from: { lat: user.lat, lng: user.lng },
          to: normalized.map((d) => ({ id: d.id, lat: d.lat, lng: d.lng })),
        });
  const dById = new Map(distances.map((x) => [x.id, x.meters]));

  const entries: PoolEntry[] = normalized
    .map((d) => ({
      id: d.id,
      distanceMeters: dById.get(d.id) ?? Number.POSITIVE_INFINITY,
      map: d.map,
      lat: d.lat,
      lng: d.lng,
    }))
    .filter((e) => Number.isFinite(e.distanceMeters) && e.distanceMeters <= GO_RADIUS_METERS)
    .sort((a, b) => a.distanceMeters - b.distanceMeters || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  return {
    user,
    entries,
    candidateCount: raw.length,
    radiusMeters: GO_RADIUS_METERS,
  };
}
