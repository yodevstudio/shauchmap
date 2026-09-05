import { describe, it, expect, vi, afterEach } from 'vitest';

// in Firebase mode the Firestore/Firebase chunk is dynamically imported and
// is NOT in the app-shell precache. toiletSource() must determine connectivity
// FIRST and surface an honest offline signal before attempting that chunk load.

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

async function loadWithFirebaseEnv() {
  vi.stubEnv('VITE_DATA_MODE', 'firebase');
  vi.stubEnv('VITE_FIREBASE_API_KEY', 'k');
  vi.stubEnv('VITE_FIREBASE_PROJECT_ID', 'demo-shauchmap-test');
  vi.stubEnv('VITE_FIREBASE_APP_ID', 'x');
  vi.stubEnv('VITE_FIREBASE_DATABASE_ID', '(default)');
  vi.resetModules();
}

describe('Firebase mode source resolution ', () => {
  it('throws an honest offline DataUnavailableError BEFORE importing the Firebase chunk', async () => {
    await loadWithFirebaseEnv();
    vi.doMock('../src/data/connectivity', () => ({ isOnline: vi.fn().mockResolvedValue(false) }));
    const firestoreMod = vi.fn();
    vi.doMock('../src/data/firestore-source', () => {
      firestoreMod();
      return { FirestoreSource: class {} };
    });

    const { toiletSource } = await import('../src/data/create-source');
    const { DataUnavailableError } = await import('../src/data/source');

    const err = await toiletSource().catch((e) => e);
    expect(err).toBeInstanceOf(DataUnavailableError);
    expect(err.kind).toBe('offline');
    expect(firestoreMod).not.toHaveBeenCalled(); // chunk was never loaded
  });

  it('retries: after an offline failure a later (online) call re-attempts the chunk', async () => {
    await loadWithFirebaseEnv();
    const online = { v: false };
    vi.doMock('../src/data/connectivity', () => ({
      isOnline: vi.fn().mockImplementation(async () => online.v),
    }));
    class FakeFS {
      readonly name = 'firebase' as const;
    }
    vi.doMock('../src/data/firestore-source', () => ({ FirestoreSource: FakeFS }));

    const { toiletSource } = await import('../src/data/create-source');
    await expect(toiletSource()).rejects.toMatchObject({ kind: 'offline' });
    online.v = true;
    const src = await toiletSource();
    expect(src).toBeInstanceOf(FakeFS);
  });

  it('fixture mode never touches connectivity or the Firebase chunk', async () => {
    vi.stubEnv('VITE_DATA_MODE', 'fixture');
    vi.resetModules();
    const isOnline = vi.fn();
    vi.doMock('../src/data/connectivity', () => ({ isOnline }));
    const { toiletSource } = await import('../src/data/create-source');
    const src = await toiletSource();
    expect(src.name).toBe('fixture');
    expect(isOnline).not.toHaveBeenCalled();
  });
});
