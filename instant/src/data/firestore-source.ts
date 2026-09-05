// FIREBASE MODE data source . Firestore *Lite* only — no realtime,
// no cloud_firestore assumptions. NOT activated in ; implemented and
// unit-tested so 8.2 can switch it on with real Web config.
//
// Primary GO reads ONLY parent `toilets/{id}` documents. Nested contribution
// collections (ratings/votes/condition events) are never read here — the
// trusted server-derived `truth_v2` / `evidence_v2` on the parent is enough.

import { initializeApp, type FirebaseApp } from 'firebase/app';
import {
  collection,
  doc,
  endAt,
  getDoc,
  getDocs,
  getFirestore,
  orderBy,
  query,
  startAt,
  type Firestore,
} from 'firebase/firestore/lite';
import type { FirebaseWebConfig } from './mode';
import { boundsFor, mergeBoundOutcomes, type BoundOutcome } from './geohash';
import { DataUnavailableError, type LoadOpts, type RawToiletDoc, type ToiletSource } from './source';

const COLLECTION = 'toilets';
const GEOHASH_FIELD = 'position.geohash';

export class FirestoreSource implements ToiletSource {
  readonly name = 'firebase' as const;
  private readonly app: FirebaseApp;
  private readonly db: Firestore;

  constructor(cfg: FirebaseWebConfig) {
    this.app = initializeApp({
      apiKey: cfg.apiKey,
      projectId: cfg.projectId,
      appId: cfg.appId,
      ...(cfg.authDomain ? { authDomain: cfg.authDomain } : {}),
    });
    this.db =
      cfg.databaseId && cfg.databaseId !== '(default)'
        ? getFirestore(this.app, cfg.databaseId)
        : getFirestore(this.app);
  }

  async loadCandidates(
    user: { lat: number; lng: number },
    opts: LoadOpts,
  ): Promise<RawToiletDoc[]> {
    const bounds = boundsFor(user, opts.radiusMeters);
    const outcomes: BoundOutcome[] = await Promise.all(
      bounds.map(async (bound) => {
        try {
          const q = query(
            collection(this.db, COLLECTION),
            orderBy(GEOHASH_FIELD),
            startAt(bound[0]),
            endAt(bound[1]),
          );
          const snap = await getDocs(q);
          const docs: RawToiletDoc[] = snap.docs.map((d) => ({
            id: d.id,
            data: d.data() as Record<string, unknown>,
          }));
          return { bound, docs };
        } catch (error) {
          return { bound, error };
        }
      }),
    );

    if (opts.signal?.aborted) {
      throw new DataUnavailableError('Toilet data timed out.', 'timeout');
    }

    const { docs, failedBounds } = mergeBoundOutcomes(outcomes);
    if (failedBounds > 0) {
      throw new DataUnavailableError(
        `${failedBounds} of ${bounds.length} map regions failed to load — showing a result now could hide a closer option.`,
        'partial',
      );
    }
    return docs;
  }

  async loadById(id: string): Promise<RawToiletDoc | null> {
    try {
      const snap = await getDoc(doc(this.db, COLLECTION, id));
      if (!snap.exists()) return null;
      return { id: snap.id, data: snap.data() as Record<string, unknown> };
    } catch (error) {
      throw new DataUnavailableError(
        `Could not load that facility: ${(error as Error).message}`,
        'backend',
      );
    }
  }
}
