// card ↔ fresh-revalidation UI consistency.
//
// After a successful navigation-time revalidation, the VISIBLE recommendation
// card, the FRESH target metadata, and the travel-mode estimates must all
// describe the SAME current decision. The card's distance must not lag behind
// the fresh decision that drives the sheet.
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render } from 'preact';
import { act } from 'preact/test-utils';

const base = { lat: 26.2389, lng: 73.0243 };
const north = (m: number) => base.lat + m / 111_320;

// A fresh, precise position the adapter will accept. `posRef` is mutated between
// the initial acquisition and the navigation-time revalidation.
const posRef = { current: { lat: north(0), lng: base.lng } };
function stubGeo() {
  const geo = {
    getCurrentPosition: (ok: PositionCallback) =>
      ok({
        coords: {
          latitude: posRef.current.lat,
          longitude: posRef.current.lng,
          accuracy: 12,
          altitude: null,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
          toJSON() { return this; },
        },
        timestamp: Date.now(),
        toJSON() { return this; },
      } as GeolocationPosition),
    watchPosition: () => 0,
    clearWatch: () => undefined,
  };
  Object.defineProperty(navigator, 'geolocation', { value: geo, configurable: true });
  Object.defineProperty(navigator, 'permissions', {
    value: { query: async () => ({ state: 'granted', onchange: null }) },
    configurable: true,
  });
}

// OSM-style docs: a fixed cluster. Distances are recomputed by the shared core
// from whatever position the adapter returns, so moving `posRef` moves every
// reported distance.
function doc(id: string, metresNorth: number) {
  return {
    id,
    data: {
      name: id.toUpperCase(),
      added_by: 'osm_india_import_2026',
      latitude: north(metresNorth),
      longitude: base.lng,
      is_free: true,
    },
  };
}
const DOCS = [doc('a_near', 120), doc('b_mid', 900), doc('c_far', 4000)];

vi.mock('../src/data/create-source', () => ({
  toiletSource: async () => ({
    name: 'fixture',
    async loadCandidates() {
      return DOCS;
    },
    async loadById(id: string) {
      return DOCS.find((d) => d.id === id) ?? null;
    },
  }),
}));

const flush = async (ms = 60) => {
  await act(async () => {
    await new Promise((r) => setTimeout(r, ms));
  });
};

let host: HTMLDivElement;
beforeEach(() => {
  posRef.current = { lat: north(0), lng: base.lng };
  stubGeo();
  host = document.createElement('div');
  document.body.appendChild(host);
});

async function mountGoScreen(search: string, hintId: string | null = null) {
  window.history.replaceState({}, '', '/go' + search);
  const { GoScreen } = await import('../src/ui/go-screen');
  await act(async () => {
    render(<GoScreen hintId={hintId} />, host);
  });
  await flush(120); // core load + location + pool + GO
}

const cardDistanceText = () =>
  host.querySelector('.card[aria-label="Recommended toilet"] .pill-distance')?.textContent?.trim() ?? '';
const sheetVisible = () => /How will you get there\?/.test(host.textContent ?? '');
const walkEtaText = () => {
  const rows = [...host.querySelectorAll('.mode-row')];
  const walk = rows.find((r) => /Walk/.test(r.textContent ?? ''));
  return walk?.querySelector('.eta')?.textContent?.trim() ?? '';
};
const ceilMin = (m: number, speed: number) => Math.ceil(m / speed / 60);

describe('R1 — same selected target, distance changed, outcome launch', () => {
  it('the card distance updates to the FRESH distance before the travel sheet shows, and the ETAs match it', async () => {
    await mountGoScreen('?reval=launch');
    expect(cardDistanceText()).toMatch(/m away|km away/);
    const initial = cardDistanceText();

    // move the user ~500 m further from the cluster, then Navigate
    posRef.current = { lat: north(-500), lng: base.lng };
    const navBtn = [...host.querySelectorAll('button')].find((b) => /^Navigate/.test(b.textContent ?? ''))!;
    await act(async () => navBtn.click());
    await flush(150);

    expect(sheetVisible()).toBe(true);

    // The background card must now read the FRESH distance, not the pre-move one.
    const fresh = cardDistanceText();
    expect(fresh).not.toBe(initial);

    // And the sheet's Walk ETA must be derived from that same fresh distance.
    const freshMeters =
      fresh.endsWith('km away')
        ? parseFloat(fresh) * 1000
        : parseInt(fresh, 10);
    expect(walkEtaText()).toBe(`~${ceilMin(freshMeters, 1.4)} min`);
  });
});

describe('R2 — /t/:id focus target stays valid, fresh distance changes', () => {
  it('the focused card updates to the fresh focus distance before the sheet', async () => {
    // hint = b_mid, which is an eligible non-selected alternative -> FOCUS card
    await mountGoScreen('?reval=launch', 'b_mid');
    const focusCard = host.querySelector('.card[aria-label="Recommended toilet"]');
    expect(focusCard?.textContent).toMatch(/From your link/i);
    const initial = cardDistanceText();

    posRef.current = { lat: north(-800), lng: base.lng };
    const navBtn = [...host.querySelectorAll('button')].find((b) => /^Navigate/.test(b.textContent ?? ''))!;
    await act(async () => navBtn.click());
    await flush(150);

    expect(sheetVisible()).toBe(true);
    const fresh = cardDistanceText();
    expect(fresh).not.toBe(initial);
    const freshMeters = fresh.endsWith('km away') ? parseFloat(fresh) * 1000 : parseInt(fresh, 10);
    expect(walkEtaText()).toBe(`~${ceilMin(freshMeters, 1.4)} min`);
  });
});

describe('R3 — fresh decision materially changes the target', () => {
  it('refreshSuggestion wins: the recommendation is re-checked and shown, NO premature travel sheet', async () => {
    await mountGoScreen('?reval=refreshSuggestion');
    posRef.current = { lat: north(-3000), lng: base.lng };
    const navBtn = [...host.querySelectorAll('button')].find((b) => /^Navigate/.test(b.textContent ?? ''))!;
    await act(async () => navBtn.click());
    await flush(150);

    expect(sheetVisible()).toBe(false);
    expect(host.textContent).toMatch(/re-checked with your current location/i);
  });
});
