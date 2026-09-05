import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { loadCore, type ShauchmapCore } from '../core/interop';
import { toiletSource } from '../data/create-source';
import { DataUnavailableError, type ToiletSource } from '../data/source';
import { acquireGoPool } from '../domain/geo-pool';
import { runGo, type GoResult } from '../domain/resolve-go';
import { revalidateBeforeNavigate, type RevalidationResult } from '../domain/revalidate';
import {
  acquireLocation,
  checkPermission,
  type LocationOutcome,
} from '../location/geolocation';

export type FlowPhase =
  | 'booting'
  | 'need-permission'
  | 'locating'
  | 'location-problem'
  | 'loading'
  | 'data-problem'
  | 'ready';

export type NavPhase = 'idle' | 'revalidating' | 'confirm' | 'refreshed' | 'nav-problem' | 'launched';

export interface GoFlow {
  phase: FlowPhase;
  result: GoResult | null;
  locationProblem: Exclude<LocationOutcome, { status: 'ok' }> | null;
  dataProblem: DataUnavailableError['kind'] | null;
  core: ShauchmapCore | null;

  start(): void;
  retry(): void;

  nav: {
    phase: NavPhase;
    reval: RevalidationResult | null;
    targetId: string | null;
  };
  beginNavigate(targetId: string | null): void;
  confirmNavigate(): void;
  dismissNav(): void;
}

export function useGoFlow(opts: { hintId?: string | null } = {}): GoFlow {
  const hintId = opts.hintId ?? null;
  const [phase, setPhase] = useState<FlowPhase>('booting');
  const [result, setResult] = useState<GoResult | null>(null);
  const [locationProblem, setLocationProblem] = useState<GoFlow['locationProblem']>(null);
  const [dataProblem, setDataProblem] = useState<GoFlow['dataProblem']>(null);
  const [nav, setNav] = useState<GoFlow['nav']>({ phase: 'idle', reval: null, targetId: null });

  const coreRef = useRef<ShauchmapCore | null>(null);
  const sourceRef = useRef<ToiletSource | null>(null);
  const runId = useRef(0);

  const ensureDeps = useCallback(async () => {
    if (!coreRef.current) coreRef.current = await loadCore();
    if (!sourceRef.current) sourceRef.current = await toiletSource();
    return { core: coreRef.current, source: sourceRef.current };
  }, []);

  const start = useCallback(async () => {
    const id = ++runId.current;
    setLocationProblem(null);
    setDataProblem(null);
    setResult(null);
    setPhase('locating');
    try {
      let core: ShauchmapCore, source: ToiletSource;
      try {
        ({ core, source } = await ensureDeps());
      } catch (e) {
 // Offline (or any data-layer failure) while resolving the source —
        // e.g. the Firebase SDK chunk can't load offline. Surface it honestly,
        // never a generic error.
        if (id !== runId.current) return;
        setDataProblem(e instanceof DataUnavailableError ? e.kind : 'backend');
        setPhase('data-problem');
        return;
      }

      const loc = await acquireLocation({ core });
      if (id !== runId.current) return;
      if (loc.status !== 'ok') {
        setLocationProblem(loc);
        setPhase('location-problem');
        return;
      }
      console.info('[go] location acquired');

      setPhase('loading');
      let pool;
      try {
        pool = await acquireGoPool({
          source,
          core,
          user: { lat: loc.fix.lat, lng: loc.fix.lng },
        });
      } catch (e) {
        if (id !== runId.current) return;
        const kind = e instanceof DataUnavailableError ? e.kind : 'backend';
        setDataProblem(kind);
        setPhase('data-problem');
        return;
      }
      if (id !== runId.current) return;
      console.info('[go] pool ready', pool.entries.length);

      const go = runGo({ core, pool, hintId });
      setResult(go);
      setPhase('ready');
    } catch (e) {
      if (id !== runId.current) return;
      // Core load / unexpected — treat as a data problem, never a fake result.
      console.error(e);
      setDataProblem('backend');
      setPhase('data-problem');
    }
  }, [ensureDeps, hintId]);

  const retry = useCallback(() => void start(), [start]);

 // Auto-start when permission is already granted .
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const p = await checkPermission();
      if (cancelled) return;
      if (p === 'granted') void start();
      else setPhase('need-permission');
    })();
    return () => {
      cancelled = true;
    };
  }, [start]);

  const beginNavigate = useCallback(
    async (targetId: string | null) => {
      if (!result || !coreRef.current || !sourceRef.current) return;
      setNav({ phase: 'revalidating', reval: null, targetId });
      const reval = await revalidateBeforeNavigate({
        core: coreRef.current,
        source: sourceRef.current,
        stale: result,
        targetId,
      });

      if (reval.kind !== 'resolved') {
        setNav({ phase: 'nav-problem', reval, targetId });
        return;
      }

      // Always show the FRESH decision first if it changed anything.
      setResult(reval.fresh);

      if (reval.outcome === 'launch') {
        setNav({ phase: 'launched', reval, targetId });
        return;
      }
      if (reval.outcome === 'confirmThenLaunch') {
        setNav({ phase: 'confirm', reval, targetId });
        return;
      }
      // refreshSuggestion / refreshOption — update UI, do NOT launch.
      setNav({ phase: 'refreshed', reval, targetId });
    },
    [result],
  );

  const confirmNavigate = useCallback(() => {
    setNav((n) => ({ ...n, phase: 'launched' }));
  }, []);

  const dismissNav = useCallback(() => {
    setNav({ phase: 'idle', reval: null, targetId: null });
  }, []);

  return {
    phase,
    result,
    locationProblem,
    dataProblem,
    core: coreRef.current,
    start: () => void start(),
    retry,
    nav,
    beginNavigate: (t) => void beginNavigate(t),
    confirmNavigate,
    dismissNav,
  };
}
