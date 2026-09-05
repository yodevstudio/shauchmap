import { describe, it, expect } from 'vitest';
import { normalizeFirestoreDoc, normalizeFirestoreValue } from '../src/data/normalize';

// Minimal Firestore-Lite Timestamp stand-in.
class FakeTimestamp {
  constructor(
    readonly seconds: number,
    readonly nanoseconds: number,
  ) {}
  toMillis() {
    return this.seconds * 1000 + this.nanoseconds / 1e6;
  }
}
class FakeGeoPoint {
  constructor(
    readonly latitude: number,
    readonly longitude: number,
  ) {}
}

describe('Firestore -> canonical normalization (web adapter)', () => {
  it('converts a top-level Timestamp to the {"__ts__": ms} sentinel', () => {
    const out = normalizeFirestoreValue(new FakeTimestamp(1788393000, 0));
    expect(out).toEqual({ __ts__: 1788393000000 });
  });

  it('converts nested timestamps at every documented depth', () => {
    const doc = {
      name: 'X',
      latitude: 26.2,
      longitude: 73.0,
      created_at: new FakeTimestamp(1000, 0),
      last_verified: new FakeTimestamp(2000, 0),
      flagged_until: new FakeTimestamp(3000, 0),
      women_safe_until: new FakeTimestamp(4000, 0),
      truth_v2: { version: 2, recorded_at: new FakeTimestamp(5000, 0) },
      evidence_v2: {
        version: 1,
        condition: {
          latest_at: new FakeTimestamp(6000, 0),
          valid_until: new FakeTimestamp(7000, 0),
          computed_at: new FakeTimestamp(8000, 0),
          last_event_at: new FakeTimestamp(9000, 0),
          support: { open: { yes: 1, no: 0, unknown: 0 } },
        },
      },
    };
    const n = normalizeFirestoreDoc(doc) as Record<string, any>;
    expect(n.created_at).toEqual({ __ts__: 1_000_000 });
    expect(n.women_safe_until).toEqual({ __ts__: 4_000_000 });
    expect(n.truth_v2.recorded_at).toEqual({ __ts__: 5_000_000 });
    expect(n.evidence_v2.condition.valid_until).toEqual({ __ts__: 7_000_000 });
    expect(n.evidence_v2.condition.last_event_at).toEqual({ __ts__: 9_000_000 });
    expect(n.evidence_v2.condition.support.open).toEqual({ yes: 1, no: 0, unknown: 0 });
  });

  it('passes scalars, arrays and unknown maps through untouched', () => {
    expect(normalizeFirestoreValue('str')).toBe('str');
    expect(normalizeFirestoreValue(42)).toBe(42);
    expect(normalizeFirestoreValue(true)).toBe(true);
    expect(normalizeFirestoreValue([1, 'a', { b: 2 }])).toEqual([1, 'a', { b: 2 }]);
  });

  it('handles a JS Date and a GeoPoint', () => {
    expect(normalizeFirestoreValue(new Date(1788393000000))).toEqual({ __ts__: 1788393000000 });
    expect(normalizeFirestoreValue(new FakeGeoPoint(26.2, 73.0))).toEqual({
      latitude: 26.2,
      longitude: 73.0,
    });
  });

  it('maps null/undefined to null', () => {
    expect(normalizeFirestoreValue(null)).toBeNull();
    expect(normalizeFirestoreValue(undefined)).toBeNull();
  });
});
