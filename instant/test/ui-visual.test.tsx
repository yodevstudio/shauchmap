import { describe, it, expect, afterEach } from 'vitest';
import { render } from 'preact';
import * as Icons from '../src/ui/icons';
import {
  genderDescriptorFromTruth,
  locationDescriptorFor,
  secondaryDescriptor,
} from '../src/ui/present';

let host: HTMLDivElement;
afterEach(() => host && render(null, host));
function mount(vnode: any) {
  host = document.createElement('div');
  document.body.appendChild(host);
  render(vnode, host);
  return host;
}

describe('SVG icon set ', () => {
  const names = Object.keys(Icons).filter((k) => k.startsWith('Icon'));
  it('exposes every state + travel icon', () => {
    for (const n of [
      'IconPin', 'IconBlocked', 'IconLocationOff', 'IconClock', 'IconAlert',
      'IconOffline', 'IconCloudOff', 'IconSearch', 'IconHelp', 'IconError',
      'IconCompass', 'IconCar', 'IconScooter', 'IconWalk',
    ]) {
      expect(names).toContain(n);
    }
  });
  it('each icon renders a decorative currentColor SVG (no emoji, no <img>)', () => {
    for (const n of names) {
      const el = mount(((Icons as any)[n])({ size: 20 }));
      const svg = el.querySelector('svg')!;
      expect(svg, n).toBeTruthy();
      expect(svg.getAttribute('aria-hidden')).toBe('true');
      expect(svg.getAttribute('focusable')).toBe('false');
      expect(svg.getAttribute('stroke')).toBe('currentColor');
      expect(el.querySelector('img')).toBeNull();
      render(null, el);
    }
  });
});

describe('locationDescriptorFor — descriptive fields only, never gender ', () => {
  it('prefers a non-empty landmark', () => {
    expect(
      locationDescriptorFor({ landmark: 'Behind Nehru Park', address: 'Rajasthan, India' }),
    ).toBe('Behind Nehru Park');
  });
  it('uses a locality-bearing address, never the bare state', () => {
    expect(locationDescriptorFor({ address: 'Rajasthan, India' })).toBeNull();
    expect(locationDescriptorFor({ address: 'India' })).toBeNull();
    expect(locationDescriptorFor({ address: 'Sardarpura, Jodhpur, Rajasthan' })).toBe(
      'Sardarpura, Jodhpur, Rajasthan',
    );
  });
  it('NEVER reads raw gender_type — that is a factual claim, not a description', () => {
    expect(locationDescriptorFor({ gender_type: 'female' })).toBeNull();
    expect(locationDescriptorFor({ landmark: 'Gate 3', gender_type: 'men' })).toBe('Gate 3');
  });
  it('returns null when the data offers nothing (generic "Public Toilet / Rajasthan, India")', () => {
    expect(
      locationDescriptorFor({ name: 'Public Toilet', address: 'Rajasthan, India', landmark: '' }),
    ).toBeNull();
    expect(locationDescriptorFor(undefined)).toBeNull();
    expect(locationDescriptorFor({})).toBeNull();
  });
});

describe('genderDescriptorFromTruth — 1:1 with the core Truth enum ', () => {
  it('translates the authoritative enum, mirroring the frozen core label table', () => {
    expect(genderDescriptorFromTruth({ gender: 'women' })).toBe('Women only');
    expect(genderDescriptorFromTruth({ gender: 'men' })).toBe('Men only');
    expect(genderDescriptorFromTruth({ gender: 'unisex' })).toBe('Unisex');
    expect(genderDescriptorFromTruth({ gender: 'unknown' })).toBeNull();
  });
});

describe('secondaryDescriptor — location part + Truth gender part', () => {
  it('joins a location descriptor and the Truth-derived gender note', () => {
    expect(
      secondaryDescriptor({ landmark: 'Gate 3' }, { gender: 'men' }),
    ).toBe('Gate 3 · Men only');
  });
  it('a raw gender_type of female does NOT surface a note when Truth says unknown', () => {
    expect(
      secondaryDescriptor({ gender_type: 'female', landmark: 'Gate 3' }, { gender: 'unknown' }),
    ).toBe('Gate 3');
  });
  it('null when neither half has anything', () => {
    expect(
      secondaryDescriptor({ address: 'Rajasthan, India' }, { gender: 'unknown' }),
    ).toBeNull();
  });
});
