// A pluggable "where do toilet documents come from" seam. FIXTURE and FIREBASE
// modes both implement it; the domain layer never imports firebase directly.

export interface RawToiletDoc {
  id: string;
  /** Raw, un-normalized Firestore-shaped data (timestamps as Date/Timestamp). */
  data: Record<string, unknown>;
}

export interface LoadOpts {
  /** Search radius in metres. The core still applies the strict cutoff. */
  radiusMeters: number;
 /** Abort signal for the acquisition timeout (: 8 s). */
  signal?: AbortSignal;
}

/** Thrown for an HONEST data failure — never swallowed into an empty pool. */
export class DataUnavailableError extends Error {
  constructor(
    message: string,
    readonly kind: 'offline' | 'timeout' | 'partial' | 'backend' = 'backend',
  ) {
    super(message);
    this.name = 'DataUnavailableError';
  }
}

export interface ToiletSource {
  readonly name: 'fixture' | 'firebase';
  /** Everything plausibly within `radiusMeters` of the user. Superset is fine —
   *  the core distance filter tightens it to a strict 15 km. MUST throw
   *  DataUnavailableError rather than return a short list on partial failure. */
  loadCandidates(
    user: { lat: number; lng: number },
    opts: LoadOpts,
  ): Promise<RawToiletDoc[]>;
  /** One document by id, for /t/:id. null = genuinely not found. */
  loadById(id: string): Promise<RawToiletDoc | null>;
}
