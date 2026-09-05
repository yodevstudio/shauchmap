import { dataMode } from './mode';
import { isOnline } from './connectivity';
import { DataUnavailableError, type ToiletSource } from './source';
import { FixtureSource } from './fixture-source';

let cached: Promise<ToiletSource> | null = null;

/** The active source for this build, decided once by VITE_DATA_MODE.
 *  FirestoreSource (and firebase / geofire-common) is dynamically imported —
 *  a fixture-mode build never ships the Firebase SDK.
 *
 * : the Firebase SDK chunk is deliberately NOT in the app-shell precache,
 *  so an offline `import('./firestore-source')` would fail with a generic
 *  module-load error. We determine connectivity FIRST and surface the honest
 *  offline signal before attempting the chunk load. (Not cached, so a later
 *  online retry re-attempts.) */
export function toiletSource(): Promise<ToiletSource> {
  const m = dataMode();
  if (m.mode !== 'firebase') {
    if (!cached) cached = Promise.resolve(new FixtureSource());
    return cached;
  }
  if (cached) return cached;
  const build = (async () => {
    if (!(await isOnline())) {
      throw new DataUnavailableError(
        "You're offline. ShauchMap Instant needs a connection to refresh toilet status.",
        'offline',
      );
    }
    const { FirestoreSource } = await import('./firestore-source');
    return new FirestoreSource(m.firebase!);
  })();
  // Only memoize a SUCCESSFUL build — an offline failure must be retryable.
  cached = build.catch((e) => {
    cached = null;
    throw e;
  });
  return cached;
}

export function __resetSourceForTests(): void {
  cached = null;
}
