import { describe, it, expect } from 'vitest';
import { boundsFor, mergeBoundOutcomes, type BoundOutcome } from '../src/data/geohash';

describe('geohash sweep helpers ', () => {
  it('produces geohash bounds covering a 15 km radius', () => {
    const b = boundsFor({ lat: 26.2389, lng: 73.0243 }, 15_000);
    expect(b.length).toBeGreaterThan(0);
    for (const [start, end] of b) {
      expect(typeof start).toBe('string');
      expect(typeof end).toBe('string');
    }
  });

  it('merges bounds and dedupes by document id', () => {
    const outcomes: BoundOutcome[] = [
      { bound: ['a', 'b'], docs: [{ id: 't1', data: {} }, { id: 't2', data: {} }] },
      { bound: ['c', 'd'], docs: [{ id: 't2', data: {} }, { id: 't3', data: {} }] },
    ];
    const { docs, failedBounds } = mergeBoundOutcomes(outcomes);
    expect(failedBounds).toBe(0);
    expect(docs.map((d) => d.id).sort()).toEqual(['t1', 't2', 't3']);
  });

  it('reports failed bounds and does NOT silently return a partial set', () => {
    const outcomes: BoundOutcome[] = [
      { bound: ['a', 'b'], docs: [{ id: 't1', data: {} }] },
      { bound: ['c', 'd'], error: new Error('region down') },
    ];
    const { docs, failedBounds } = mergeBoundOutcomes(outcomes);
    expect(failedBounds).toBe(1);
    // the caller must treat failedBounds>0 as an honest failure (tested in
    // firestore-source.test) — merge still only returns the good docs it had
    expect(docs.map((d) => d.id)).toEqual(['t1']);
  });
});
