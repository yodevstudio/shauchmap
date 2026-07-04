/// Single source of truth for distance display.
/// < 1000 m  → "850 m"
/// >= 1000 m → "4.2 km" (one decimal), >= 100 km → no decimal "120 km"
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000.0;
  if (km >= 100) return '${km.round()} km';
  return '${km.toStringAsFixed(1)} km';
}

/// For hero displays where number and unit render separately.
/// Returns (number, unit): ('850','m') or ('4.2','km').
(String, String) formatDistanceParts(double meters) {
  if (meters < 1000) return ('${meters.round()}', 'm');
  final km = meters / 1000.0;
  return (km >= 100 ? '${km.round()}' : km.toStringAsFixed(1), 'km');
}
