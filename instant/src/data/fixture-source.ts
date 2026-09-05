import {
  fixtureToiletById,
  fixtureWorld,
  type FixtureWorldName,
} from './fixtures';
import { DataUnavailableError, type LoadOpts, type RawToiletDoc, type ToiletSource } from './source';

const WORLDS: FixtureWorldName[] = [
  'default',
  'unknown',
  'confirm',
  'none',
  'empty',
  'longname',
  'genderconflict',
];

function worldFromQuery(): FixtureWorldName {
  if (typeof location === 'undefined') return 'default';
  const q = new URLSearchParams(location.search).get('demo');
  return (WORLDS as string[]).includes(q ?? '') ? (q as FixtureWorldName) : 'default';
}

/** Deterministic demo source. `?demo=confirm|none|empty` picks a world.
 *  `?fail=offline|timeout|partial` simulates an honest data failure. */
export class FixtureSource implements ToiletSource {
  readonly name = 'fixture' as const;

  constructor(private readonly world: FixtureWorldName = worldFromQuery()) {}

  private simulatedFailure(): void {
    // Genuinely offline: even demo data must not stand in for "current toilet
 // status" . The app shows the honest offline state.
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      throw new DataUnavailableError('Offline — ShauchMap needs a connection to refresh status.', 'offline');
    }
    if (typeof location === 'undefined') return;
    const f = new URLSearchParams(location.search).get('fail');
    if (f === 'offline') throw new DataUnavailableError('Simulated offline (demo).', 'offline');
    if (f === 'timeout') throw new DataUnavailableError('Simulated backend timeout (demo).', 'timeout');
    if (f === 'partial')
      throw new DataUnavailableError('Simulated partial region failure (demo).', 'partial');
  }

  async loadCandidates(
    _user: { lat: number; lng: number },
    _opts: LoadOpts,
  ): Promise<RawToiletDoc[]> {
    this.simulatedFailure();
    // `?slow=<ms>` lets screenshots catch the loading state (demo only).
    if (typeof location !== 'undefined') {
      const slow = Number(new URLSearchParams(location.search).get('slow') ?? '0');
      if (slow > 0) await new Promise((r) => setTimeout(r, Math.min(slow, 5000)));
    }
    return fixtureWorld(this.world).map((d) => ({ id: d.id, data: d.data }));
  }

  async loadById(id: string): Promise<RawToiletDoc | null> {
    this.simulatedFailure();
    const d = fixtureToiletById(id);
    return d ? { id: d.id, data: d.data } : null;
  }
}
