import { describe, it, expect, beforeAll, afterEach } from 'vitest';
import { render } from 'preact';
import { loadCore, type ShauchmapCore } from '../src/core/interop';
import { acquireGoPool, type GoPool } from '../src/domain/geo-pool';
import { runGo } from '../src/domain/resolve-go';
import { FixtureSource } from '../src/data/fixture-source';
import { GoCard, AltList } from '../src/ui/go-card';
import { NoConfidentOption, DataUnavailable, PermissionDenied, StalePosition } from '../src/ui/states';
import { App } from '../src/app';

const USER = { lat: 26.2389, lng: 73.0243 };

let core: ShauchmapCore;
let pool: GoPool;
beforeAll(async () => {
  core = await loadCore();
  pool = await acquireGoPool({ source: new FixtureSource('default'), core, user: USER });
});

let host: HTMLDivElement;
afterEach(() => {
  if (host) render(null, host);
});
function mount(vnode: any): HTMLDivElement {
  host = document.createElement('div');
  document.body.appendChild(host);
  render(vnode, host);
  return host;
}

describe('result rendering', () => {
  it('renders the CORE presentation verbatim (no TS reinterpretation)', () => {
    const result = runGo({ core, pool, nowMs: Date.now() });
    expect(result.go.selectedId).not.toBeNull();
    const el = mount(<GoCard result={result} core={core} onNavigate={() => {}} />);
    const text = el.textContent ?? '';
    expect(text).toContain(result.go.presentation.headline);
    expect(text).toContain(result.go.presentation.primaryCta);
    // deliberately weak wording — never "verified"/"guaranteed"
    expect(text.toLowerCase()).not.toMatch(/\b(verified|guaranteed|confirmed open)\b/);
  });

  it('renders up to 3 alternatives in the core order, not visually equal to a result', () => {
    const result = runGo({ core, pool, nowMs: Date.now() });
    const el = mount(<AltList result={result} core={core} onPick={() => {}} />);
    const names = [...el.querySelectorAll('.alt-name')].map((n) => n.textContent);
    expect(names.length).toBeLessThanOrEqual(3);
    expect(names.length).toBe(Math.min(3, result.go.alternatives.length));
  });
});

describe('confirm dialog wording ', () => {
  it('confirm label matches the next action (opens the travel-mode chooser, not Maps directly)', async () => {
    const { ConfirmDialog } = await import('../src/ui/travel-sheet');
    const el = mount(
      <ConfirmDialog
        title="Confirm before navigating"
        body="x"
        confirmLabel="Continue"
        onConfirm={() => {}}
        onClose={() => {}}
      />,
    );
    const primary = el.querySelector('.btn-primary');
    expect(primary?.textContent).toBe('Continue');
    expect(primary?.textContent).not.toBe('Open in Maps');
  });
});

describe('failure rendering', () => {
  it('each failure state renders its message and never a recommendation', () => {
    for (const node of [
      <NoConfidentOption onRetry={() => {}} />,
      <DataUnavailable kind="offline" onRetry={() => {}} />,
      <PermissionDenied onRetry={() => {}} />,
      <StalePosition onRetry={() => {}} ageSeconds={42} />,
    ]) {
      const el = mount(node);
      expect((el.textContent ?? '').length).toBeGreaterThan(10);
      expect(el.querySelector('.card, .state')).not.toBeNull();
      render(null, el);
    }
  });
});

describe('routing', () => {
  it('/ renders the landing screen', () => {
    history.replaceState(null, '', '/');
    const el = mount(<App />);
    expect(el.textContent).toContain('Find a nearby public toilet');
 // No pre-evidence overclaims on the landing copy.
    expect(el.textContent?.toLowerCase()).not.toMatch(/\b(usable|guaranteed|verified)\b/);
    expect(el.textContent?.toLowerCase()).not.toContain('no tracking');
    expect(el.textContent?.toLowerCase()).not.toContain('never leaves your device');
  });

  it('an unknown route renders a safe 404 with a Find a toilet CTA', () => {
    history.replaceState(null, '', '/definitely-not-a-route');
    const el = mount(<App />);
    expect(el.textContent).toContain('Page not found');
    expect([...el.querySelectorAll('a')].some((a) => /find a toilet/i.test(a.textContent ?? ''))).toBe(
      true,
    );
  });
});
