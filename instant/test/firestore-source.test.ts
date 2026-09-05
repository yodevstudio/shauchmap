import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock the Firebase Lite SDK so the adapter can be tested with no network.
const state: { getDocsImpl: (q: unknown) => Promise<{ docs: any[] }> } = {
  getDocsImpl: async () => ({ docs: [] }),
};

vi.mock('firebase/app', () => ({
  initializeApp: vi.fn(() => ({ name: 'test' })),
}));
vi.mock('firebase/firestore/lite', () => ({
  getFirestore: vi.fn(() => ({})),
  collection: vi.fn((_db, name) => ({ __collection: name })),
  query: vi.fn((...parts) => ({ __query: parts })),
  orderBy: vi.fn((f) => ({ __orderBy: f })),
  startAt: vi.fn((v) => ({ __startAt: v })),
  endAt: vi.fn((v) => ({ __endAt: v })),
  getDocs: vi.fn((q) => state.getDocsImpl(q)),
  doc: vi.fn((_db, _c, id) => ({ __doc: id })),
  getDoc: vi.fn(async () => ({ exists: () => false })),
}));

import { FirestoreSource } from '../src/data/firestore-source';
import { DataUnavailableError } from '../src/data/source';

const CFG = {
  apiKey: 'k',
  projectId: 'p',
  appId: 'a',
  databaseId: '(default)',
};
const USER = { lat: 26.2389, lng: 73.0243 };

function docSnap(id: string, data: Record<string, unknown>) {
  return { id, data: () => data };
}

beforeEach(() => {
  state.getDocsImpl = async () => ({ docs: [] });
});

describe('FirestoreSource (Firestore Lite adapter, )', () => {
  it('sweeps geohash bounds, merges and dedupes by id', async () => {
    let call = 0;
    state.getDocsImpl = async () => {
      call++;
      if (call === 1) return { docs: [docSnap('t1', { name: 'A' }), docSnap('t2', { name: 'B' })] };
      if (call === 2) return { docs: [docSnap('t2', { name: 'B' }), docSnap('t3', { name: 'C' })] };
      return { docs: [] };
    };
    const src = new FirestoreSource(CFG);
    const out = await src.loadCandidates(USER, { radiusMeters: 15_000 });
    expect(out.map((d) => d.id).sort()).toEqual(['t1', 't2', 't3']);
    expect(call).toBeGreaterThan(1); // more than one bound queried
  });

  it('throws an HONEST DataUnavailableError (kind "partial") if ANY bound fails', async () => {
    let call = 0;
    state.getDocsImpl = async () => {
      call++;
      if (call === 2) throw new Error('region unavailable');
      return { docs: [docSnap(`t${call}`, {})] };
    };
    const src = new FirestoreSource(CFG);
    const err = await src.loadCandidates(USER, { radiusMeters: 15_000 }).catch((e) => e);
    expect(err).toBeInstanceOf(DataUnavailableError);
    expect(err.kind).toBe('partial');
  });

  it('loadById returns null for a missing doc', async () => {
    const src = new FirestoreSource(CFG);
    expect(await src.loadById('nope')).toBeNull();
  });
});
