// Real connectivity probe . `navigator.onLine` is unreliable
// for a page served entirely from the service-worker cache (Chromium keeps it
// `true`), so we make a tiny no-store request to a path the SW does NOT
// precache: a network failure throws (offline), any HTTP response — even 404 —
// resolves (online). Bounded by a short timeout.

export async function isOnline(timeoutMs = 2500): Promise<boolean> {
  if (typeof fetch === 'undefined') return true; // non-browser — assume online
  // Vitest / jsdom: relative fetch has no real network — treat as online.
  if (typeof process !== 'undefined' && process.env?.VITEST) return true;
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return false;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    // Not precached; cache-busted; HEAD keeps it cheap.
    await fetch(`/__connectivity__?t=${Date.now()}`, {
      method: 'HEAD',
      cache: 'no-store',
      signal: ctrl.signal,
    });
    return true; // reached the network (status irrelevant)
  } catch {
    return false; // network unreachable / aborted
  } finally {
    clearTimeout(timer);
  }
}
