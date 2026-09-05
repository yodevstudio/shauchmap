// Travel-mode estimate + Google Maps hand-off .
//
// SAME numbers as Android (lib/widgets/travel_mode_sheet.dart): straight-line
// distance / speed, ceil to whole minutes. SAME disclaimer. SAME Maps URL as
// lib/utils/map_launcher.dart (web branch). No Directions/Routes API, no key.

export type TravelMode = 'driving' | 'bicycling' | 'walking';

export interface TravelChoice {
  mode: TravelMode;
  label: 'Drive' | 'Ride' | 'Walk';
  /** Whole minutes, matching Android's `.ceil()`. null when distance unknown. */
  etaMinutes: number | null;
}

// metres / second — identical constants to Android.
const SPEED: Record<TravelMode, number> = {
  driving: 11.1,
  bicycling: 4.1,
  walking: 1.4,
};
const LABEL: Record<TravelMode, TravelChoice['label']> = {
  driving: 'Drive',
  bicycling: 'Ride',
  walking: 'Walk',
};

export const TRAVEL_DISCLAIMER =
  'Rough estimate from straight-line distance — not a Maps route time.';

export function estimateMinutes(distanceMeters: number | null, mode: TravelMode): number | null {
  if (distanceMeters == null || !Number.isFinite(distanceMeters)) return null;
  return Math.ceil(distanceMeters / SPEED[mode] / 60);
}

export function travelChoices(distanceMeters: number | null): TravelChoice[] {
  return (['driving', 'bicycling', 'walking'] as TravelMode[]).map((mode) => ({
    mode,
    label: LABEL[mode],
    etaMinutes: estimateMinutes(distanceMeters, mode),
  }));
}

/** The exact web URL Android opens (map_launcher.dart web branch):
 *  https://www.google.com/maps/dir/?api=1&destination=<lat>,<lng>&travelmode=<mode>
 *  Android builds it with `Uri.parse` and a LITERAL comma — matched here. */
export function mapsDirectionsUrl(dest: { lat: number; lng: number }, mode: TravelMode): string {
  return `https://www.google.com/maps/dir/?api=1&destination=${dest.lat},${dest.lng}&travelmode=${mode}`;
}
