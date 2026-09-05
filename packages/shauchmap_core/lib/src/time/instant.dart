/// A normalized point in time for the ShauchMap domain core.
///
/// The core NEVER sees a Firestore `Timestamp` or any platform date type. Each
/// client converts its timestamps to [Instant] at its adapter boundary:
///   * Android: `Instant.fromDateTime(firestoreTimestamp.toDate())`
///   * Web (compiled core, JSON boundary): `Instant.fromEpochMillis(ms)`
///
/// Internally the parsers immediately unwrap to a plain [DateTime] via
/// [toDateTime], so all downstream domain arithmetic is unchanged.
class Instant {
  /// Milliseconds since the Unix epoch (UTC).
  final int epochMillis;

  const Instant.fromEpochMillis(this.epochMillis);

  Instant.fromDateTime(DateTime d) : epochMillis = d.millisecondsSinceEpoch;

  /// A UTC [DateTime] for the same instant. UTC is irrelevant to the domain
  /// (every comparison is instant-based) and is used only for determinism.
  DateTime toDateTime() =>
      DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true);

  @override
  bool operator ==(Object other) =>
      other is Instant && other.epochMillis == epochMillis;

  @override
  int get hashCode => epochMillis.hashCode;

  @override
  String toString() => 'Instant(${toDateTime().toIso8601String()})';
}
