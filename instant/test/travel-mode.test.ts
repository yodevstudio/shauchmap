import { describe, it, expect } from 'vitest';
import {
  estimateMinutes,
  mapsDirectionsUrl,
  travelChoices,
  TRAVEL_DISCLAIMER,
} from '../src/domain/travel-mode';

describe('travel-mode (must mirror Android exactly)', () => {
  it('uses Android speeds + ceil for the rough estimate', () => {
    // lib/widgets/travel_mode_sheet.dart: d/11.1/60, d/4.1/60, d/1.4/60 -> ceil
    const d = 2000;
    expect(estimateMinutes(d, 'driving')).toBe(Math.ceil(d / 11.1 / 60));
    expect(estimateMinutes(d, 'bicycling')).toBe(Math.ceil(d / 4.1 / 60));
    expect(estimateMinutes(d, 'walking')).toBe(Math.ceil(d / 1.4 / 60));
    expect(estimateMinutes(d, 'driving')).toBe(4);
    expect(estimateMinutes(d, 'walking')).toBe(24);
  });

  it('returns null minutes when distance is unknown', () => {
    expect(estimateMinutes(null, 'driving')).toBeNull();
    expect(estimateMinutes(Infinity, 'walking')).toBeNull();
  });

  it('labels modes Drive / Ride / Walk', () => {
    expect(travelChoices(1000).map((c) => c.label)).toEqual(['Drive', 'Ride', 'Walk']);
  });

  it('keeps the Android disclaimer verbatim', () => {
    expect(TRAVEL_DISCLAIMER).toBe(
      'Rough estimate from straight-line distance — not a Maps route time.',
    );
  });

  it('builds the exact Android web Maps URL', () => {
    // lib/utils/map_launcher.dart web branch
    expect(mapsDirectionsUrl({ lat: 26.2389, lng: 73.0243 }, 'driving')).toBe(
      'https://www.google.com/maps/dir/?api=1&destination=26.2389,73.0243&travelmode=driving',
    );
    expect(mapsDirectionsUrl({ lat: 1, lng: 2 }, 'walking')).toContain('travelmode=walking');
    expect(mapsDirectionsUrl({ lat: 1, lng: 2 }, 'bicycling')).toContain('travelmode=bicycling');
  });
});
