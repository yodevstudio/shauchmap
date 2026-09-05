// Firestore document value  ->  the core's canonical JSON representation
// . This is the web sibling of the Android
// `firestore_domain_adapter.normalizeFirestoreTimestamps`.
//
// The ONLY structural transform is: a Firestore Timestamp (at any depth —
// truth_v2.recorded_at, every evidence_v2.* time, created_at, last_verified,
// flagged_until, women_safe_until, …) becomes the sentinel {"__ts__": ms} that
// canonical.dart revives to a core `Instant`. Everything else passes through
// untouched so the core's own parsers/adapters decide meaning.

import type { CanonicalValue } from '../core/types';

interface TimestampLike {
  toMillis?: () => number;
  toDate?: () => Date;
  seconds?: number;
  nanoseconds?: number;
}

function timestampToMillis(v: TimestampLike): number | null {
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v.toDate === 'function') return v.toDate().getTime();
  if (typeof v.seconds === 'number') {
    return Math.round(v.seconds * 1000 + (v.nanoseconds ?? 0) / 1e6);
  }
  return null;
}

function isTimestampLike(v: unknown): v is TimestampLike {
  if (typeof v !== 'object' || v === null) return false;
  const o = v as TimestampLike;
  return (
    typeof o.toMillis === 'function' ||
    (typeof o.seconds === 'number' && typeof o.nanoseconds === 'number')
  );
}

interface GeoPointLike {
  latitude: number;
  longitude: number;
}
function isGeoPoint(v: unknown): v is GeoPointLike {
  if (typeof v !== 'object' || v === null) return false;
  const o = v as Record<string, unknown>;
  return (
    typeof o.latitude === 'number' &&
    typeof o.longitude === 'number' &&
    typeof o.toMillis !== 'function' &&
    Object.keys(o).length <= 3
  );
}

/** Recursively normalize a raw Firestore value into canonical JSON. */
export function normalizeFirestoreValue(value: unknown): CanonicalValue {
  if (value === null || value === undefined) return null;

  if (isTimestampLike(value)) {
    const ms = timestampToMillis(value);
    return ms === null ? null : { __ts__: ms };
  }

  if (value instanceof Date) return { __ts__: value.getTime() };

  if (isGeoPoint(value)) {
    return { latitude: value.latitude, longitude: value.longitude };
  }

  if (Array.isArray(value)) return value.map(normalizeFirestoreValue);

  if (typeof value === 'object') {
    const out: Record<string, CanonicalValue> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = normalizeFirestoreValue(v);
    }
    return out;
  }

  if (typeof value === 'number' || typeof value === 'string' || typeof value === 'boolean') {
    return value;
  }
  // Unknown exotic type (bytes, reference…) — drop it; the core defaults to UNKNOWN.
  return null;
}

/** Normalize a whole Firestore document's data map. */
export function normalizeFirestoreDoc(data: Record<string, unknown>): Record<string, CanonicalValue> {
  return normalizeFirestoreValue(data) as Record<string, CanonicalValue>;
}
