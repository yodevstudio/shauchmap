// Data mode resolution .
//
//   FIXTURE MODE  — deterministic local data, no Firebase, clearly DEMO.
//   FIREBASE MODE — real Firestore Lite adapter; requires full Web env config;
//                   fail-closed if any var is missing. NOT activated in 8.1.
//
// A production build that asks for firebase but is missing config throws at
// module load — it NEVER silently serves fixtures.

export type DataMode = 'fixture' | 'firebase';

export interface FirebaseWebConfig {
  apiKey: string;
  projectId: string;
  appId: string;
  databaseId: string;
  authDomain?: string;
}

export interface ResolvedMode {
  mode: DataMode;
  /** Present only in firebase mode. */
  firebase?: FirebaseWebConfig;
  /** Human-readable reason, surfaced in the demo badge / diagnostics. */
  note: string;
}

type Env = Record<string, string | undefined>;

function readFirebaseConfig(env: Env): FirebaseWebConfig | { missing: string[] } {
  const req = {
    apiKey: env.VITE_FIREBASE_API_KEY,
    projectId: env.VITE_FIREBASE_PROJECT_ID,
    appId: env.VITE_FIREBASE_APP_ID,
    databaseId: env.VITE_FIREBASE_DATABASE_ID,
  };
  const missing = Object.entries(req)
    .filter(([, v]) => !v || !v.trim())
    .map(([k]) => k);
  if (missing.length) return { missing };
  return {
    apiKey: req.apiKey!,
    projectId: req.projectId!,
    appId: req.appId!,
    databaseId: req.databaseId!,
    ...(env.VITE_FIREBASE_AUTH_DOMAIN ? { authDomain: env.VITE_FIREBASE_AUTH_DOMAIN } : {}),
  };
}

function resolve(): ResolvedMode {
  const env = import.meta.env as Env;
  // An unset OR empty VITE_DATA_MODE means fixture mode.
  const requested = (env.VITE_DATA_MODE?.trim() || 'fixture').toLowerCase();

  if (requested === 'firebase') {
    const cfg = readFirebaseConfig(env);
    if ('missing' in cfg) {
      // Fail-closed. Never downgrade to fixtures when firebase was asked for.
      throw new Error(
        `VITE_DATA_MODE=firebase but missing config: ${cfg.missing.join(', ')}. ` +
          `Set them in .env.local (see .env.example). ShauchMap Instant will not ` +
          `serve demo data in place of a requested Firebase connection.`,
      );
    }
    return {
      mode: 'firebase',
      firebase: cfg,
      note: `Firebase mode — project ${cfg.projectId}, db ${cfg.databaseId}`,
    };
  }

  if (requested !== 'fixture') {
    throw new Error(`VITE_DATA_MODE must be "fixture" or "firebase", got "${requested}"`);
  }
  return {
    mode: 'fixture',
    note: 'Fixture mode — deterministic demo data, not live. No Firebase connection.',
  };
}

let cached: ResolvedMode | null = null;
export function dataMode(): ResolvedMode {
  if (!cached) cached = resolve();
  return cached;
}

/** Test-only: re-read import.meta.env on the next dataMode() call. */
export function __resetModeForTests(): void {
  cached = null;
}

/** True in fixture mode — drives the persistent "DEMO DATA" badge. */
export function isDemo(): boolean {
  return dataMode().mode === 'fixture';
}
