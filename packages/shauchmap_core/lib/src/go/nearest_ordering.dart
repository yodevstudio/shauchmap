// ShauchMap GO V2 — pure nearest-first ordering for the bounded candidate pool.
//
// LEAF FILE — imports NOTHING (so it can be used by both the Firestore service
// and by tests without a layering cycle through `Toilet`).
//
// The geohash geo-query returns records in geohash-cell order, NOT distance
// order. `getGoPool` calls this with `limit: 0` — it uses the ordering only for
// DETERMINISTIC / debuggable behaviour and returns the WHOLE bounded result to
// `decideGo` (authority is part of the frozen policy, so a pre-engine "nearest
// N" cap could hide the only primary and change the semantic outcome). The
// `limit` parameter is retained for any non-GO caller that genuinely wants a
// bounded slice.

/// One candidate: its opaque [item] plus its already-computed straight-line
/// [distanceKm] from the query centre.
typedef Ranked<T> = ({T item, double distanceKm});

/// Return the nearest [limit] items, ordered by `(distanceKm asc, id asc)`.
///
/// * A record returned LAST by the source but physically nearest still survives.
/// * Ties on distance are broken by [idOf] lexical ascending (deterministic).
/// * `limit <= 0` returns everything, ordered.
List<T> orderNearest<T>(
  List<Ranked<T>> raw,
  String Function(T item) idOf, {
  required int limit,
}) {
  final sorted = [...raw]..sort((a, b) {
      final d = a.distanceKm.compareTo(b.distanceKm);
      return d != 0 ? d : idOf(a.item).compareTo(idOf(b.item));
    });
  final ordered = [for (final r in sorted) r.item];
  if (limit <= 0 || ordered.length <= limit) return ordered;
  return ordered.sublist(0, limit);
}
