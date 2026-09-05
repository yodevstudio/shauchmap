// Browser location adapter (; hardened / 8.3.2).
//
// navigator.geolocation is ONLY the platform sensor. The shared Dart core is
// the sole authority on whether a fix is "fresh enough to act on" — we call
// core.evaluatePositionFreshness, never a TypeScript rule. No default location,
// no stale fallback, no guessing.
//
// the browser sensor's own reported uncertainty (`coords.accuracy`,
// metres) is now part of the WEB trust boundary. A fresh fix whose reported
// accuracy approaches ShauchMap's spatial decision scale can't be ranked
// reliably, so the adapter runs a short staged acquisition and, if it still
// can't get a precise-enough fix, returns a first-class `imprecise` outcome
// instead of feeding a kilometre-scale-uncertain position into the core.
//
// a Phase-A `getCurrentPosition` TIMEOUT no longer surfaces
// immediately. On a real A55, `watchPosition` routinely delivers an excellent
// fix (~20 m) a couple of seconds after the ~4 s one-shot has given up. So a
// Phase-A timeout now enters the SAME bounded watch stage (no seed) — the user
// sees one continuous acquisition of up to ~8 s and only sees "took too long"
// if the whole bounded attempt genuinely fails. No fallback to a stale / old /
// default position, ever.
//
// This is a BROWSER-ADAPTER concern only — Truth / Evidence / GO / Android
// semantics are untouched; the core keeps receiving an already-accepted
// location.

import type { ShauchmapCore } from '../core/interop';
import { isDemo } from '../data/mode';

/** Matches the core's tightest horizon, kGoCachedPositionMaxAge (10 s). */
export const DEFAULT_MAX_AGE_SECONDS = 10;

/**
 * The largest `coords.accuracy` (in metres) the web adapter will accept as a
 * fix good enough to rank nearby toilets.
 *
 * ShauchMap's GO logic carries a 400 m absolute detour guard. Allowing a
 * browser position whose *own* reported uncertainty approaches that decision
 * scale makes spatial ranking unreliable. 200 m is a conservative half-guard
 * sensor-quality ceiling — NOT a claim that the real error is exactly 200 m,
 * just a gate on the browser's reported estimate. A poorer fix is never
 * silently rounded into usability.
 */
export const WEB_MAX_LOCATION_ACCURACY_METERS = 200;

/** Phase A: initial high-accuracy `getCurrentPosition` budget. */
const DEFAULT_PHASE_A_MS = 4000;
/** Phase B: bounded `watchPosition` window. Entered when Phase A returns a
 *  FRESH-but-imprecise fix (quality chase) OR a TIMEOUT (recovery). Never
 *  indefinite — total worst-case acquisition ≈ PHASE_A + this ≈ 8 s. */
const DEFAULT_QUALITY_WINDOW_MS = 4000;

/** A device/GPS timestamp up to this far AHEAD of the wall clock (up to 2 full
 *  seconds) is treated as benign clock/adapter skew, not "your clock is wrong".
 *  Real engines drift by this much: WebKit hands Playwright a geolocation
 *  `timestamp` a few ms past its own clamped `Date.now()`, and unsynced mobile
 *  clocks can sit a second or two ahead. Anything beyond this really is a wrong
 *  clock and we can't judge freshness, so it surfaces as `future`.
 *
 *  This is a BROWSER-ADAPTER normalization ONLY. The shared Dart rule
 *  `isGoPositionFresh` is unchanged: we clamp the timestamp to `now` (below)
 *  before handing it to the core, so within the tolerance the core still sees a
 *  valid "now-or-past" fix and applies the SAME frozen max-age. A genuinely
 *  stale fix (older than the frozen horizon) is still classified `stale` — this
 *  tolerance only forgives small FORWARD skew, never backdates a real age. */
const FUTURE_SKEW_TOLERANCE_MS = 2000;

/**
 * FIXTURE MODE ONLY. Lets demo links / screenshots pin a deterministic
 * location without the real sensor:
 *   ?loc=26.2389,73.0243   ?locage=45 (seconds old)   ?locacc=350 (accuracy m)
 *   ?locerr=denied|timeout|unavailable|future
 * Ignored entirely in FIREBASE / production builds.
 */
type DemoOverride =
  | { kind: 'error'; outcome: LocationOutcome }
  | { kind: 'fix'; lat: number; lng: number; timestampMs: number; accuracyMeters: number };

function demoLocationOverride(now: number): DemoOverride | null {
  if (!isDemo() || typeof location === 'undefined') return null;
  const p = new URLSearchParams(location.search);
  const err = p.get('locerr');
  if (err === 'denied') return { kind: 'error', outcome: { status: 'denied' } };
  if (err === 'timeout') return { kind: 'error', outcome: { status: 'timeout' } };
  if (err === 'unavailable')
    return { kind: 'error', outcome: { status: 'unavailable', reason: 'demo' } };
  const loc = p.get('loc');
  if (!loc) return null;
  const [latS, lngS] = loc.split(',');
  const lat = Number(latS);
  const lng = Number(lngS);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const accRaw = Number(p.get('locacc') ?? '15');
  const accuracyMeters = Number.isFinite(accRaw) && accRaw >= 0 ? accRaw : 15;
  if (err === 'future')
    return { kind: 'fix', lat, lng, timestampMs: now + 60_000, accuracyMeters };
  const ageSec = Number(p.get('locage') ?? '2');
  return { kind: 'fix', lat, lng, timestampMs: now - ageSec * 1000, accuracyMeters };
}

export interface FixData {
  lat: number;
  lng: number;
  timestampMs: number;
  accuracyMeters: number | null;
}

export type LocationOutcome =
  | { status: 'ok'; fix: FixData }
  | { status: 'stale'; fix: FixData; ageSeconds: number }
  | { status: 'future'; fix: FixData }
  /** Fresh fix(es) obtained, but the browser's reported accuracy never got
   *  within `WEB_MAX_LOCATION_ACCURACY_METERS` inside the bounded window. */
  | { status: 'imprecise'; bestAccuracyMeters: number | null }
  | { status: 'denied' }
  | { status: 'prompt' }
  | { status: 'unavailable'; reason?: string }
  | { status: 'timeout' };

export type PermissionState = 'granted' | 'prompt' | 'denied' | 'unknown';

export async function checkPermission(): Promise<PermissionState> {
  try {
    if (isDemo() && typeof location !== 'undefined') {
      const p = new URLSearchParams(location.search);
      if (p.get('perm') === 'prompt') return 'prompt';
      if (p.get('locerr') === 'denied') return 'denied';
      if (p.get('loc')) return 'granted';
    }
    if (typeof navigator === 'undefined' || !navigator.permissions?.query) return 'unknown';
    const s = await navigator.permissions.query({ name: 'geolocation' as PermissionName });
    return (s.state as PermissionState) ?? 'unknown';
  } catch {
    return 'unknown';
  }
}

interface AcquireOpts {
  core: ShauchmapCore;
  maxAgeSeconds?: number;
  /** Phase A `getCurrentPosition` timeout (default 4000 ms). */
  timeoutMs?: number;
  /** Phase B bounded watch window — quality chase after a fresh-but-imprecise
   *  fix, and recovery after a Phase-A timeout (default 4000 ms). */
  qualityWindowMs?: number;
  /** Reported-accuracy ceiling in metres (default WEB_MAX_LOCATION_ACCURACY_METERS). */
  maxAccuracyMeters?: number;
  /** Injectable clock + geolocation for tests. `null` = simulate "no API". */
  now?: () => number;
  geolocation?: Geolocation | null;
}

function fixFrom(p: GeolocationPosition): FixData {
  return {
    lat: p.coords.latitude,
    lng: p.coords.longitude,
    timestampMs: p.timestamp,
    accuracyMeters:
      typeof p.coords.accuracy === 'number' && Number.isFinite(p.coords.accuracy)
        ? p.coords.accuracy
        : null,
  };
}

/** A usable numeric accuracy, or null when the value is unusable
 *  (NaN / Infinity / negative / missing → fail closed). */
function usableAccuracy(a: number | null): number | null {
  return typeof a === 'number' && Number.isFinite(a) && a >= 0 ? a : null;
}

type Classified =
  | { kind: 'ok'; fix: FixData }
  | { kind: 'stale'; fix: FixData; ageSeconds: number }
  | { kind: 'future'; fix: FixData }
  /** fresh, but reported accuracy fails the gate (too large, or unusable). */
  | { kind: 'imprecise'; fix: FixData; accuracyMeters: number | null };

/** Classify a single raw fix: future-skew → shared freshness → accuracy gate.
 * Order matters — `future` and `stale` are terminal ; the accuracy
 *  gate only ever applies to an otherwise-fresh fix. */
function classifyFix(
  fix: FixData,
  nowMs: number,
  maxAgeSeconds: number,
  maxAccuracyMeters: number,
  core: ShauchmapCore,
): Classified {
  if (fix.timestampMs > nowMs + FUTURE_SKEW_TOLERANCE_MS) return { kind: 'future', fix };
  const positionTsMs = Math.min(fix.timestampMs, nowMs);
  const fresh = core.evaluatePositionFreshness({ positionTsMs, nowMs, maxAgeSeconds });
  if (!fresh) {
    return {
      kind: 'stale',
      fix,
      ageSeconds: Math.max(0, Math.round((nowMs - positionTsMs) / 1000)),
    };
  }
  const acc = usableAccuracy(fix.accuracyMeters);
  if (acc == null || acc > maxAccuracyMeters) {
    return { kind: 'imprecise', fix, accuracyMeters: acc };
  }
  return { kind: 'ok', fix };
}

function rawPosition(
  geo: Geolocation,
  timeoutMs: number,
): Promise<GeolocationPosition | GeolocationPositionError> {
  return new Promise((resolve) => {
    geo.getCurrentPosition(resolve, resolve, {
      enableHighAccuracy: true,
      maximumAge: 0,
      timeout: timeoutMs,
    });
  });
}

/** Result of the bounded watch stage.
 *  - `ok` / `imprecise` / `future`: a fresh fix (of that quality) was obtained.
 *  - `none`: the window expired without a single fresh fix (and no seed). */
type WatchResult =
  | { kind: 'ok'; fix: FixData }
  | { kind: 'imprecise'; fix: FixData; accuracyMeters: number | null }
  | { kind: 'future'; fix: FixData }
  | { kind: 'none' };

/**
 * The bounded `watchPosition` stage. Reusable for BOTH:
 *   A. quality chase — `seed` is a FRESH-but-imprecise Phase-A fix; and
 *   B. timeout recovery — `seed` is `null` (Phase A returned no fix).
 *
 * Resolves EARLY with the first FRESH-and-precise fix. Otherwise, at the
 * deadline: the best (lowest-accuracy) fresh-but-imprecise fix seen (or the
 * seed) → `imprecise`; else, if the only fresh fixes seen were future-skewed →
 * `future`; else → `none`. Never regresses to a poorer fix. Always clears the
 * watch and the timer. Resolves exactly once.
 */
function runWatchStage(params: {
  geo: Geolocation;
  windowMs: number;
  now: () => number;
  maxAgeSeconds: number;
  maxAccuracyMeters: number;
  core: ShauchmapCore;
  seed: Extract<Classified, { kind: 'imprecise' }> | null;
}): Promise<WatchResult> {
  const { geo, windowMs, now, maxAgeSeconds, maxAccuracyMeters, core, seed } = params;
  const score = (a: number | null) => (a == null ? Infinity : a);
  return new Promise((resolve) => {
    let best: Extract<Classified, { kind: 'imprecise' }> | null = seed;
    let lastFuture: FixData | null = null;
    let done = false;
    let watchId = 0;

    const settle = (v: WatchResult) => {
      if (done) return;
      done = true;
      try {
        geo.clearWatch(watchId);
      } catch {
        /* ignore */
      }
      clearTimeout(timer);
      resolve(v);
    };

    const atDeadline = (): WatchResult => {
      if (best) return { kind: 'imprecise', fix: best.fix, accuracyMeters: best.accuracyMeters };
      if (lastFuture) return { kind: 'future', fix: lastFuture };
      return { kind: 'none' };
    };

    const timer = setTimeout(() => settle(atDeadline()), windowMs);

    try {
      watchId = geo.watchPosition(
        (p) => {
          if (done) return;
          const c = classifyFix(fixFrom(p), now(), maxAgeSeconds, maxAccuracyMeters, core);
          if (c.kind === 'ok') {
            settle({ kind: 'ok', fix: c.fix });
            return;
          }
          if (c.kind === 'imprecise') {
            if (!best || score(c.accuracyMeters) < score(best.accuracyMeters)) best = c;
            return;
          }
          if (c.kind === 'future') {
            lastFuture = c.fix; // preserve honest clock behaviour, never accept
            return;
          }
          // stale: ignore — never a GO input.
        },
        () => {
          /* transient watch error — let the timer settle it */
        },
        { enableHighAccuracy: true, maximumAge: 0, timeout: windowMs },
      );
    } catch {
      settle(atDeadline());
    }
  });
}

/**
 * Acquire ONE fix and classify it via the shared freshness rule AND the web
 * accuracy gate. Staged: a fast high-accuracy attempt (Phase A), then a single
 * bounded watch window (Phase B) that handles both a fresh-but-imprecise
 * Phase-A fix and a Phase-A timeout. The user experiences one continuous
 * acquisition of up to ~8 s; a good Phase-A fix still returns immediately.
 */
export async function acquireLocation(opts: AcquireOpts): Promise<LocationOutcome> {
  const now = opts.now ?? Date.now;
  const maxAgeSeconds = opts.maxAgeSeconds ?? DEFAULT_MAX_AGE_SECONDS;
  const phaseAMs = opts.timeoutMs ?? DEFAULT_PHASE_A_MS;
  const qualityWindowMs = opts.qualityWindowMs ?? DEFAULT_QUALITY_WINDOW_MS;
  const maxAccuracyMeters = opts.maxAccuracyMeters ?? WEB_MAX_LOCATION_ACCURACY_METERS;

  const toOutcome = (c: Classified): LocationOutcome => {
    switch (c.kind) {
      case 'ok':
        return { status: 'ok', fix: c.fix };
      case 'stale':
        return { status: 'stale', fix: c.fix, ageSeconds: c.ageSeconds };
      case 'future':
        return { status: 'future', fix: c.fix };
      case 'imprecise':
        return { status: 'imprecise', bestAccuracyMeters: c.accuracyMeters };
    }
  };

  // ---- demo override (fixture builds only) ---------------------------------
  const override = opts.geolocation ? null : demoLocationOverride(now());
  if (override?.kind === 'error') return override.outcome;
  if (override?.kind === 'fix') {
    const fix: FixData = {
      lat: override.lat,
      lng: override.lng,
      timestampMs: override.timestampMs,
      accuracyMeters: override.accuracyMeters,
    };
    return toOutcome(classifyFix(fix, now(), maxAgeSeconds, maxAccuracyMeters, opts.core));
  }

  const geo =
    opts.geolocation === null
      ? undefined
      : (opts.geolocation ??
        (typeof navigator !== 'undefined' ? navigator.geolocation : undefined));

  if (!geo || typeof geo.getCurrentPosition !== 'function') {
    return { status: 'unavailable', reason: 'no geolocation API' };
  }
  const canWatch = typeof geo.watchPosition === 'function';

  const runWatch = (seed: Extract<Classified, { kind: 'imprecise' }> | null) =>
    runWatchStage({
      geo,
      windowMs: qualityWindowMs,
      now,
      maxAgeSeconds,
      maxAccuracyMeters,
      core: opts.core,
      seed,
    });

  // ---- Phase A: fast high-accuracy fix -----------------------------------
  const resA = await rawPosition(geo, phaseAMs);

  if ('code' in resA) {
    if (resA.code === resA.PERMISSION_DENIED) return { status: 'denied' }; // never enters the watch
    if (resA.code === resA.TIMEOUT) {
 // /: do NOT surface timeout yet — recover through a bounded watch.
      if (!canWatch) return { status: 'timeout' };
      const rec = await runWatch(null);
      if (rec.kind === 'ok') return { status: 'ok', fix: rec.fix };
      if (rec.kind === 'imprecise')
        return { status: 'imprecise', bestAccuracyMeters: rec.accuracyMeters };
      if (rec.kind === 'future') return { status: 'future', fix: rec.fix };
      return { status: 'timeout' };
    }
    return { status: 'unavailable', reason: resA.message || 'position unavailable' };
  }

  const first = classifyFix(fixFrom(resA), now(), maxAgeSeconds, maxAccuracyMeters, opts.core);
  // ok / future / stale are all terminal here.
  if (first.kind !== 'imprecise') return toOutcome(first);

  // ---- Phase B: fresh but not precise enough — chase a better fix -------
  if (!canWatch) return toOutcome(first);
  const better = await runWatch(first);
  if (better.kind === 'ok') return { status: 'ok', fix: better.fix };
  if (better.kind === 'imprecise')
    return { status: 'imprecise', bestAccuracyMeters: better.accuracyMeters };
  // `future` / `none` from the chase → fall back to the FRESH imprecise seed
  // (a fresh imprecise fix is a better honest answer than "timeout").
  return toOutcome(first);
}
