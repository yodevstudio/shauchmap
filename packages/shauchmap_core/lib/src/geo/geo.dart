import 'dart:math' as math;

/// A plain user position for GO resolution. Each client fills this from its
/// platform location API at the adapter boundary:
///   * Android: from `geolocator` `Position` (`latitude`, `longitude`,
///     `timestamp`).
///   * Web: from `navigator.geolocation` (`coords.latitude/longitude`,
///     `timestamp`).
class GeoPos {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  const GeoPos({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}

/// The ONE canonical great-circle distance primitive for ShauchMap, in metres.
///
/// This is a byte-for-byte reproduction of
/// `geolocator_platform_interface` 4.2.6 `GeolocatorPlatform.distanceBetween`
/// — which `geolocator_android` 5.0.2 does NOT override, so it is exactly what
/// runs on the ShauchMap Android device. It has verified numerical identity
/// with the real `Geolocator.distanceBetween` (0.0 m difference across a 51-case
/// Jodhpur battery). Using it here makes:
///
///     ANDROID distance == WEB distance == CORE distance
///
/// for the same coordinates, with **no change to Android behaviour**.
///
/// Note the constant: `earthRadius = 6378137.0` is the WGS-84 EQUATORIAL radius,
/// exactly as geolocator uses — NOT a mean radius. The 400 m absolute detour
/// guard in `decideGo` is sensitive to this at the sub-metre level; a different
/// radius flips ~15 GO decisions in a ~0.45 m band around the cap (
/// distance_parity_results.json).
double geoDistanceMeters(
  double startLatitude,
  double startLongitude,
  double endLatitude,
  double endLongitude,
) {
  const earthRadius = 6378137.0;
  final dLat = _toRadians(endLatitude - startLatitude);
  final dLon = _toRadians(endLongitude - startLongitude);

  final a = math.pow(math.sin(dLat / 2), 2) +
      math.pow(math.sin(dLon / 2), 2) *
          math.cos(_toRadians(startLatitude)) *
          math.cos(_toRadians(endLatitude));
  final c = 2 * math.asin(math.sqrt(a));

  return earthRadius * c;
}

double _toRadians(double degree) => degree * math.pi / 180;
