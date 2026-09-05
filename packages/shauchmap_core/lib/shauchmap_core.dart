/// ShauchMap domain core — the single authoritative implementation of Truth V2,
/// Evidence V2, GO V2, and their presentation reduction.
///
/// Pure Dart. No Flutter, Firebase, cloud_firestore, geolocator, or platform
/// API. Clients (the Android app; the compiled-to-JS web core) supply thin
/// adapters that convert Firestore documents / platform positions into the
/// plain values parsed here — see [Instant], [GeoPos], and `Toilet.fromMap`.
library;

export 'src/time/instant.dart';
export 'src/geo/geo.dart';

export 'src/models/toilet.dart';
export 'src/models/presentation_truth.dart';

export 'src/truth/toilet_truth.dart';
export 'src/evidence/toilet_evidence.dart';

export 'src/go/nearest_ordering.dart';
export 'src/go/go_decision.dart';
export 'src/go/go_presentation.dart';
export 'src/go/go_resolver.dart';
