// Field Audit — choose the ShauchMap toilet to audit, or start an unmapped
// discovery.
//
// Nearby/search READS production Firestore (allowed; unaffected by the broken
// write rules; served from the offline cache with no network). Nothing here
// writes to Firestore. Selecting a toilet copies an ALLOWLISTED, identity-free
// subset of its fields into a LOCAL audit record only.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/firestore_service.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_widgets.dart';
import 'field_audit_config.dart';
import 'field_audit_form_screen.dart';
import 'field_audit_model.dart';
import 'field_audit_store.dart';

class FieldAuditPickToiletScreen extends StatefulWidget {
  const FieldAuditPickToiletScreen({super.key, required this.store});
  final FieldAuditStore store;

  @override
  State<FieldAuditPickToiletScreen> createState() =>
      _FieldAuditPickToiletScreenState();
}

class _FieldAuditPickToiletScreenState
    extends State<FieldAuditPickToiletScreen> {
  final _fs = FirestoreService();
  final _search = TextEditingController();
  List<Toilet> _all = const [];
  bool _loading = true;
  String _origin = '';
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Jodhpur fallback centre (same constant the app uses). Only *claimed* as
    // the origin once a fallback has actually happened.
    double lat = 26.2940;
    double lng = 73.0185;
    String origin =
        ''; // '' => still resolving; shown as "Finding your location…"
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        origin = 'Jodhpur default'; // permission refused → fallback really used
      } else {
        // Field work: prefer a FRESH current fix, then fall back to last-known.
        Position? p;
        try {
          p = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
          origin = 'your current location';
        } catch (_) {
          p = await Geolocator.getLastKnownPosition();
          origin = p != null ? 'last-known location' : 'Jodhpur default';
        }
        if (p != null) {
          lat = p.latitude;
          lng = p.longitude;
        }
      }
    } catch (_) {
      origin = 'Jodhpur default'; // any location error → fallback really used
    }
    if (!mounted) return;
    setState(() {
      _lat = lat;
      _lng = lng;
      _origin = origin;
    });
    try {
      final list = await _fs
          .getToiletsNearby(latitude: lat, longitude: lng, radiusKm: 15.0)
          .first;
      if (mounted) setState(() => _all = list);
    } catch (_) {
      // offline with no cache — the "unmapped" option below still works
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Toilet> get _filtered {
    final q = _search.text.trim().toLowerCase();
    var list = _all;
    if (q.isNotEmpty) {
      list = list
          .where(
            (t) =>
                t.name.toLowerCase().contains(q) ||
                t.address.toLowerCase().contains(q) ||
                t.landmark.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_lat != null && _lng != null) {
      list = [...list]
        ..sort(
          (a, b) =>
              Geolocator.distanceBetween(
                _lat!,
                _lng!,
                a.latitude,
                a.longitude,
              ).compareTo(
                Geolocator.distanceBetween(
                  _lat!,
                  _lng!,
                  b.latitude,
                  b.longitude,
                ),
              ),
        );
    }
    return list.take(60).toList();
  }

  // Guards against a second gesture (impatient double-tap, or tap racing a
  // long-press) creating a duplicate audit while the first is still saving.
  bool _busy = false;

  Future<void> _addExisting(Toilet t, {required bool auditNow}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _addExistingInner(t, auditNow: auditNow);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExistingInner(Toilet t, {required bool auditNow}) async {
    Map<String, dynamic> legacy = {};
    String? osmId;
    String? addedBy = t.addedBy.isEmpty ? null : t.addedBy;
    String? address = t.address.isEmpty ? null : t.address;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('toilets')
          .doc(t.id)
          .get();
      final d = snap.data();
      if (d != null) {
        // ONLY the allowlisted, identity-free legacy fields.
        for (final k in FieldAuditConfig.legacyReferenceAllowlist) {
          if (d.containsKey(k)) legacy[k] = d[k];
        }
        osmId = d['osm_id'] as String?;
        addedBy = (d['added_by'] as String?) ?? addedBy;
        address = (d['address'] as String?) ?? address;
      }
    } catch (_) {
      /* fall back to the Toilet model values only */
    }

    final now = DateTime.now();
    final a = FieldAudit(
      auditId: newAuditId(),
      recordContext: RecordContext.mappedRecord,
      queuedAt: now,
      lastSavedAt: now,
      toiletId: t.id,
      toiletName: t.name,
      mappedLat: t.latitude,
      mappedLng: t.longitude,
      mappedAddress: address,
      sourceType: classifySourceType(addedBy),
      sourceRef: osmId, // OSM id only — never a community UID
      legacyReference: legacy,
    );
    await widget.store.save(a);
    if (!mounted) return;
    if (auditNow) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FieldAuditFormScreen(audit: a, store: widget.store),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Queued: ${t.name}')));
    }
  }

  Future<void> _addUnmappedDiscovery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _addUnmappedDiscoveryInner();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addUnmappedDiscoveryInner() async {
    final now = DateTime.now();
    final a = FieldAudit(
      auditId: newAuditId(),
      recordContext: RecordContext.unmappedDiscovery,
      queuedAt: now,
      lastSavedAt: now,
      toiletName: '',
      selectionMethod: 'unmapped_discovery',
      // mapped_* stay null; observed GPS in the form identifies it.
    );
    await widget.store.save(a);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FieldAuditFormScreen(audit: a, store: widget.store),
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final items = _filtered;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Add to audit queue',
          style: SmText.subhead.copyWith(color: c.ink),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SmTokens.s16,
              SmTokens.s8,
              SmTokens.s16,
              SmTokens.s4,
            ),
            child: TextField(
              controller: _search,
              style: SmText.body.copyWith(color: c.ink),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search nearby ShauchMap records by name / area',
                hintStyle: SmText.body.copyWith(color: c.ink3),
                prefixIcon: Icon(Icons.search, color: c.ink3),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SmTokens.rSmall),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SmTokens.s16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading
                    ? (_origin.isEmpty
                          ? 'Finding your location…'
                          : 'Loading nearby (from $_origin)…')
                    : '${items.length} nearby (from $_origin) — tap to queue, '
                          'long-press to audit now.\n"Mapped record not found" is '
                          'recorded INSIDE the audit for the specific record.',
                style: SmText.caption.copyWith(color: c.ink3),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SmTokens.s16),
              children: [
                if (_loading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(SmTokens.s24),
                      child: CircularProgressIndicator(color: c.brandSolid),
                    ),
                  ),
                for (final t in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SmTokens.s8),
                    child: FieldAuditPickRow(
                      title: t.name,
                      subtitle: _lat == null
                          ? t.address
                          : '${Geolocator.distanceBetween(_lat!, _lng!, t.latitude, t.longitude).toStringAsFixed(0)} m · ${t.address}',
                      enabled: !_busy,
                      onQueue: () => _addExisting(t, auditNow: false),
                      onAuditNow: () => _addExisting(t, auditNow: true),
                    ),
                  ),
                const SizedBox(height: SmTokens.s16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addUnmappedDiscovery,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Audit an unmapped physical toilet'),
                ),
                const SizedBox(height: SmTokens.s8),
                Text(
                  'For a mapped record you cannot find on the ground: queue that '
                  'record, then set mapping outcome = "could not locate" in the '
                  'audit. That keeps the failure attached to the specific '
                  'ShauchMap document.',
                  style: SmText.caption.copyWith(color: c.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One nearby-record row in the Field Audit picker.
///
/// A single [InkWell] owns BOTH gestures — a plain tap queues the record for
/// later, a long-press starts auditing it now. There is no outer/parent
/// recognizer to compete with, so a normal tap fires reliably (the previous
/// nested `SmCard(onTap:) > InkWell(onLongPress:)` let the inner InkWell win
/// the gesture arena and silently swallow taps).
///
/// [enabled] is set false by the parent while an add is already in flight so a
/// second gesture cannot create a duplicate audit.
class FieldAuditPickRow extends StatelessWidget {
  const FieldAuditPickRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onQueue,
    required this.onAuditNow,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onQueue;
  final VoidCallback onAuditNow;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return SmCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: enabled ? onQueue : null,
        onLongPress: enabled ? onAuditNow : null,
        borderRadius: BorderRadius.circular(SmTokens.rCard),
        splashColor: Colors.transparent,
        highlightColor: c.soft,
        child: Padding(
          padding: const EdgeInsets.all(SmTokens.s16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmText.bodyStrong.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmText.caption.copyWith(color: c.ink3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_circle_outline, color: c.brand),
            ],
          ),
        ),
      ),
    );
  }
}
