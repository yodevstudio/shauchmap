import 'dart:math' as math;

double freshnessConfidence(DateTime? lastVerified) {
  if (lastVerified == null) return 0.1;
  final h = DateTime.now().difference(lastVerified).inMinutes / 60.0;
  return math.exp(-h / 48.0);
}

double trustScore(double bayesian, double freshness) =>
    0.5 * freshness + 0.5 * (bayesian / 5.0);
