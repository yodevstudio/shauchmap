// Field Audit — the fast in-field observation form (schema v2).
//
// Autosaves on every change (serialized, last-write-wins in the store), so a
// crash or app kill never loses work and reopening resumes exactly.
// GPS and photos are best-effort: failure never blocks Save.
//
// visit_started_at is stamped ONCE, the first time this form is opened for a
// record — it is never reset on reopening.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/sm_theme.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_widgets.dart';
import 'field_audit_model.dart';
import 'field_audit_store.dart';
import 'field_audit_widgets.dart';

class FieldAuditFormScreen extends StatefulWidget {
  const FieldAuditFormScreen({
    super.key,
    required this.audit,
    required this.store,
  });

  final FieldAudit audit;
  final FieldAuditStore store;

  @override
  State<FieldAuditFormScreen> createState() => _FieldAuditFormScreenState();
}

class _FieldAuditFormScreenState extends State<FieldAuditFormScreen> {
  late final FieldAudit a = widget.audit;
  final _picker = ImagePicker();
  late final TextEditingController _notes = TextEditingController(
    text: a.notes,
  );
  late final TextEditingController _cleanNote = TextEditingController(
    text: a.cleanlinessNote,
  );
  late final TextEditingController _fee = TextEditingController(
    text: a.feeAmountInr == null ? '' : a.feeAmountInr!.toStringAsFixed(0),
  );
  late final TextEditingController _nameCtrl = TextEditingController(
    text: a.toiletName,
  );

  String? _photosDirPath;
  bool _gpsBusy = false;
  bool _photoReminderShown = false;
  bool _completionClearedNoticeShown = false;

  bool get _mapped => a.recordContext == RecordContext.mappedRecord;

  @override
  void initState() {
    super.initState();
    // The visit genuinely starts NOW, the first time the form is opened.
    if (a.visitStartedAt == null) {
      a.visitStartedAt = DateTime.now();
      widget.store.save(a);
    }
    widget.store.photosDir().then((d) {
      if (mounted) setState(() => _photosDirPath = d.path);
    });
    // Only auto-acquire GPS for a brand-new (pending) audit. Opening a
    // completed / in-progress / revisit record must never mutate it.
    if (a.status == AuditStatus.pending &&
        a.gpsSource == GpsSource.unavailable &&
        a.auditorObservedLat == null) {
      _captureGps();
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _cleanNote.dispose();
    _fee.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- persistence
  Future<void> _persist({bool complete = false, bool revisit = false}) async {
    if (revisit) {
      a.status = AuditStatus.revisit;
      a.completedAt = null; // a revisit is not a completed observation
    } else if (complete) {
      a.status = AuditStatus.completed;
      a.completedAt = DateTime.now();
    } else if (a.status == AuditStatus.pending) {
      a.status = AuditStatus.inProgress;
    }
    try {
      await widget.store.save(a);
      await widget.store.flush(a.auditId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  /// Every real field change goes through here. The FIRST change to a completed
  /// (or revisit) record drops it back to in_progress and clears completed_at —
  /// it must pass "Save & complete" again before re-entering the analysis set.
  void _mutate(VoidCallback fn) {
    final wasCompleted = a.status == AuditStatus.completed;
    setState(() {
      a.beginEdit();
      fn();
    });
    widget.store.save(a); // serialized + last-write-wins in the store
    if (wasCompleted && !_completionClearedNoticeShown && mounted) {
      _completionClearedNoticeShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completion cleared. Press "Save & complete" again to re-include '
            'this in the analysis dataset.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------- gps
  Future<void> _captureGps() async {
    if (_gpsBusy) return;
    setState(() => _gpsBusy = true);
    try {
      final att = await _acquireGps();
      final note = a.applyGpsAttempt(att);
      // Persist + (if the record was completed) invalidate completion — a GPS
      // replacement is a real mutation.
      _mutate(() {});
      if (note != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(note), duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  /// Prefer a fresh current fix; fall back to last-known; else failed.
  /// Never mislabels a last-known fix as current. Does not decide whether to
  /// keep or replace prior evidence — [FieldAudit.applyGpsAttempt] does that.
  Future<GpsAttempt> _acquireGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return const GpsAttempt.failed();
      }
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        return GpsAttempt.current(
          p.latitude,
          p.longitude,
          p.accuracy,
          p.timestamp,
        );
      } catch (_) {
        final lk = await Geolocator.getLastKnownPosition();
        return lk == null
            ? const GpsAttempt.failed()
            : GpsAttempt.lastKnown(
                lk.latitude,
                lk.longitude,
                lk.accuracy,
                lk.timestamp,
              );
      }
    } catch (_) {
      return const GpsAttempt.failed();
    }
  }

  // -------------------------------------------------------------------- photos
  Future<void> _addPhoto(ImageSource src) async {
    if (!_photoReminderShown) {
      _photoReminderShown = true;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.sm.surface,
          title: Text(
            'Before you photograph',
            style: SmText.subhead.copyWith(color: ctx.sm.ink),
          ),
          content: Text(
            'Do not photograph people, attendants, or occupied / private '
            'cubicle situations. Capture the entrance, signage, and general '
            'facility condition only.',
            style: SmText.body.copyWith(color: ctx.sm.ink2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final x = await _picker.pickImage(
        source: src,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final fn = await widget.store.savePhotoBytes(
        a.auditId,
        'evidence',
        bytes,
      );
      _mutate(() => a.photoFilenames.add(fn));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo capture failed: $e')));
      }
    }
  }

  Future<void> _removePhoto(String fn) async {
    await widget.store.deletePhoto(fn);
    _mutate(() => a.photoFilenames.remove(fn));
  }

  // ------------------------------------------------------------- save & finish
  Future<void> _saveAndComplete() async {
    final gaps = a.completionGaps();
    final needPhotoPrompt = !a.hasPhotos;
    if (gaps.isEmpty && !needPhotoPrompt) {
      await _persist(complete: true);
      if (mounted) Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.sm;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(
            'Complete with unresolved items?',
            style: SmText.subhead.copyWith(color: c.ink),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final g in gaps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $g',
                    style: SmText.body.copyWith(color: c.ink2),
                  ),
                ),
              if (needPhotoPrompt)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• Continue without entrance / signage photo?',
                    style: SmText.body.copyWith(color: c.ink2),
                  ),
                ),
              const SizedBox(height: SmTokens.s8),
              Text(
                'You can still complete — this is a data-quality note only.',
                style: SmText.caption.copyWith(color: c.ink3),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Complete anyway'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await _persist(complete: true);
      if (mounted) Navigator.pop(context);
    }
  }

  // --------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Audit — ${a.toiletName.isEmpty ? "facility" : a.toiletName}',
          style: SmText.subhead.copyWith(color: c.ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SmTokens.s16,
          SmTokens.s8,
          SmTokens.s16,
          150,
        ),
        children: [
          _contextCard(c),
          _gpsCard(c),

          if (!_mapped) ...[
            const AuditSectionHeader('Facility name / descriptor'),
            TextField(
              controller: _nameCtrl,
              style: SmText.body.copyWith(color: c.ink),
              decoration: _dec(c, 'e.g. Clock Tower west-side public toilet'),
              onChanged: (v) => _mutate(() => a.toiletName = v.trim()),
            ),
          ],

          if (_mapped) ...[
            const AuditSectionHeader('Mapping outcome (this ShauchMap record)'),
            AuditChoiceRow<MappingOutcome>(
              label: 'What did you find at the mapped point?',
              value: a.mappingOutcome,
              options: const [
                AuditOption(
                  MappingOutcome.confirmedAtLocation,
                  'Confirmed here',
                  emphasis: AuditEmphasis.good,
                ),
                AuditOption(
                  MappingOutcome.foundNearbyButMoved,
                  'Nearby, moved',
                ),
                AuditOption(
                  MappingOutcome.couldNotLocate,
                  'Could not locate',
                  emphasis: AuditEmphasis.bad,
                ),
                AuditOption(MappingOutcome.duplicate, 'Duplicate'),
                AuditOption(
                  MappingOutcome.notAToilet,
                  'Not a toilet',
                  emphasis: AuditEmphasis.bad,
                ),
                AuditOption(
                  MappingOutcome.unknown,
                  'Unknown',
                  emphasis: AuditEmphasis.unknown,
                ),
              ],
              onChanged: (v) => _mutate(() => a.mappingOutcome = v),
            ),
          ],

          const AuditSectionHeader('Public access'),
          _ynu(
            'Open at visit?',
            a.openAtVisit,
            (v) => _mutate(() => a.openAtVisit = v),
          ),
          _ynu(
            'Publicly accessible at visit?',
            a.publiclyAccessibleAtVisit,
            (v) => _mutate(() => a.publiclyAccessibleAtVisit = v),
            hint: 'Locked, staff-only or blocked entry = No.',
          ),

          const AuditSectionHeader('Functionality'),
          _ync('Running water', a.water, (v) => _mutate(() => a.water = v)),
          _ync(
            'Soap',
            a.soap,
            (v) => _mutate(() => a.soap = v),
            hint: 'Recorded for comparison. NOT part of the usability verdict.',
          ),
          _ync(
            'Usable cubicle',
            a.usableCubicle,
            (v) => _mutate(() => a.usableCubicle = v),
          ),
          _ync(
            'Door / latch works',
            a.doorOrLatch,
            (v) => _mutate(() => a.doorOrLatch = v),
          ),
          _ync('Lighting', a.lighting, (v) => _mutate(() => a.lighting = v)),
          _ync(
            'Western seat present',
            a.westernSeat,
            (v) => _mutate(() => a.westernSeat = v),
          ),

          const AuditSectionHeader('Accessibility'),
          _ync(
            'Wheelchair entry',
            a.wheelchairEntry,
            (v) => _mutate(() => a.wheelchairEntry = v),
          ),
          _ync(
            'Accessible toilet',
            a.accessibleToilet,
            (v) => _mutate(() => a.accessibleToilet = v),
          ),

          const AuditSectionHeader('Facility / gender'),
          _ync(
            "Men's section",
            a.mensSection,
            (v) => _mutate(() => a.mensSection = v),
          ),
          _ync(
            "Women's section",
            a.womensSection,
            (v) => _mutate(() => a.womensSection = v),
          ),
          _ync('Unisex', a.unisex, (v) => _mutate(() => a.unisex = v)),

          const AuditSectionHeader('Fee'),
          AuditChoiceRow<FeeKind>(
            label: 'Fee to use',
            value: a.fee,
            options: const [
              AuditOption(FeeKind.free, 'Free', emphasis: AuditEmphasis.good),
              AuditOption(FeeKind.paid, 'Paid'),
              AuditOption(
                FeeKind.unknown,
                'Unknown',
                emphasis: AuditEmphasis.unknown,
              ),
            ],
            onChanged: (v) => _mutate(() {
              a.fee = v;
              if (v != FeeKind.paid) {
                a.feeAmountInr = null;
                _fee.clear();
              }
            }),
          ),
          if (a.fee == FeeKind.paid)
            Padding(
              padding: const EdgeInsets.only(top: SmTokens.s8),
              child: TextField(
                controller: _fee,
                keyboardType: TextInputType.number,
                style: SmText.body.copyWith(color: c.ink),
                decoration: _dec(c, 'Amount (₹) — optional'),
                onChanged: (v) =>
                    _mutate(() => a.feeAmountInr = double.tryParse(v.trim())),
              ),
            ),

          const AuditSectionHeader('Condition'),
          AuditChoiceRow<Cleanliness>(
            label: 'Observed cleanliness',
            hint: 'Categorical only — no fabricated score.',
            value: a.cleanliness,
            options: const [
              AuditOption(
                Cleanliness.acceptable,
                'Acceptable',
                emphasis: AuditEmphasis.good,
              ),
              AuditOption(
                Cleanliness.poor,
                'Poor',
                emphasis: AuditEmphasis.bad,
              ),
              AuditOption(
                Cleanliness.notChecked,
                'Not checked',
                emphasis: AuditEmphasis.unknown,
              ),
            ],
            onChanged: (v) => _mutate(() => a.cleanliness = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: SmTokens.s8),
            child: TextField(
              controller: _cleanNote,
              style: SmText.body.copyWith(color: c.ink),
              maxLines: 2,
              decoration: _dec(c, 'Short context note — optional'),
              onChanged: (v) => _mutate(() => a.cleanlinessNote = v),
            ),
          ),

          const AuditSectionHeader('Photo evidence'),
          _photoSection(c),

          const AuditSectionHeader('Notes'),
          TextField(
            controller: _notes,
            style: SmText.body.copyWith(color: c.ink),
            maxLines: 3,
            decoration: _dec(c, 'Anything else worth recording'),
            onChanged: (v) => _mutate(() => a.notes = v),
          ),

          const AuditSectionHeader('Computed'),
          _verdictCard(
            c,
            'facility_usable_at_visit',
            fourStateUsableWire(a.computeFacilityUsable()),
            a.facilityUsableReason(),
            _colorFor4(c, a.computeFacilityUsable()),
          ),
          const SizedBox(height: SmTokens.s8),
          _verdictCard(
            c,
            'mapped_option_usable_at_visit',
            mappedOptionUsableWire(a.computeMappedOptionUsable()),
            a.mappedOptionReason(),
            _colorForMapped(c, a.computeMappedOptionUsable()),
          ),
          const SizedBox(height: SmTokens.s8),
          Text(
            'Physical usability and map reliability are separate metrics. '
            'Soap, cleanliness and wheelchair access are recorded but are NOT '
            'part of either verdict.',
            style: SmText.caption.copyWith(color: c.ink3),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(c),
    );
  }

  // ----------------------------------------------------------------- fragments
  Widget _ynu(
    String label,
    YesNoUnknown v,
    ValueChanged<YesNoUnknown> on, {
    String? hint,
  }) => AuditChoiceRow<YesNoUnknown>(
    label: label,
    hint: hint,
    value: v,
    options: const [
      AuditOption(YesNoUnknown.yes, 'Yes', emphasis: AuditEmphasis.good),
      AuditOption(YesNoUnknown.no, 'No', emphasis: AuditEmphasis.bad),
      AuditOption(
        YesNoUnknown.unknown,
        'Unknown',
        emphasis: AuditEmphasis.unknown,
      ),
    ],
    onChanged: on,
  );

  Widget _ync(
    String label,
    YesNoNotChecked v,
    ValueChanged<YesNoNotChecked> on, {
    String? hint,
  }) => AuditChoiceRow<YesNoNotChecked>(
    label: label,
    hint: hint,
    value: v,
    options: const [
      AuditOption(YesNoNotChecked.yes, 'Yes', emphasis: AuditEmphasis.good),
      AuditOption(YesNoNotChecked.no, 'No', emphasis: AuditEmphasis.bad),
      AuditOption(
        YesNoNotChecked.notChecked,
        'Not checked',
        emphasis: AuditEmphasis.unknown,
      ),
    ],
    onChanged: on,
  );

  InputDecoration _dec(SmColors c, String hint) => InputDecoration(
    hintText: hint,
    hintStyle: SmText.body.copyWith(color: c.ink3),
    filled: true,
    fillColor: c.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(SmTokens.rSmall),
      borderSide: BorderSide(color: c.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(SmTokens.rSmall),
      borderSide: BorderSide(color: c.line),
    ),
  );

  Widget _contextCard(SmColors c) {
    final rf = a.legacyReference;
    String ref(String k) => rf.containsKey(k) ? '${rf[k]}' : '—';
    return SmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mapped ? 'MAPPED RECORD' : 'UNMAPPED DISCOVERY',
            style: SmText.caption.copyWith(
              color: _mapped ? c.brand : c.statusUnsure,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: SmTokens.s4),
          Text(
            _mapped ? 'doc ${a.toiletId}' : 'No map record — GPS identifies it',
            style: SmText.caption.copyWith(color: c.ink3),
          ),
          if (a.mappedLat != null && a.mappedLng != null)
            Text(
              'mapped: ${a.mappedLat!.toStringAsFixed(6)}, '
              '${a.mappedLng!.toStringAsFixed(6)}',
              style: SmText.caption.copyWith(color: c.ink2),
            ),
          if (a.mappedAddress != null && a.mappedAddress!.isNotEmpty)
            Text(
              a.mappedAddress!,
              style: SmText.caption.copyWith(color: c.ink2),
            ),
          Text(
            'source: ${sourceTypeWire(a.sourceType)}'
            '${a.sourceRef != null ? " (${a.sourceRef})" : ""}',
            style: SmText.caption.copyWith(color: c.ink3),
          ),
          if (rf.isNotEmpty) ...[
            const SizedBox(height: SmTokens.s4),
            Text(
              'REFERENCE ONLY — legacy data, NOT ground truth',
              style: SmText.caption.copyWith(
                color: c.statusUnsure,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'legacy: is_open=${ref('is_open')} · is_free=${ref('is_free')} · '
              'has_water=${ref('has_water')} · has_soap=${ref('has_soap')} · '
              'category=${ref('category')}',
              style: SmText.caption.copyWith(color: c.ink3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gpsCard(SmColors c) {
    final d = a.distanceFromMappedPointMeters;
    final stale = a.gpsSource == GpsSource.lastKnown;
    final unavailable = a.gpsSource == GpsSource.unavailable;
    final warnColor = c.statusClosed;
    return Padding(
      padding: const EdgeInsets.only(top: SmTokens.s8),
      child: SmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'GPS: ${gpsSourceWire(a.gpsSource)}',
                    style: SmText.bodyStrong.copyWith(
                      color: a.gpsSource == GpsSource.current
                          ? c.statusOpen
                          : warnColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _gpsBusy ? null : _captureGps,
                  child: Text(_gpsBusy ? '…' : 'Get current fix'),
                ),
              ],
            ),
            if (stale || unavailable)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                padding: const EdgeInsets.all(SmTokens.s8),
                decoration: BoxDecoration(
                  color: warnColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SmTokens.rSmall),
                ),
                child: Text(
                  unavailable
                      ? 'No GPS fix. Coordinates not recorded — mark this in '
                            'notes.'
                      : 'LAST-KNOWN fix, not a fresh field reading. '
                            'Age ${a.gpsAgeSecondsAtCapture ?? "?"} s. Tap "Get '
                            'current fix" once you are physically at the facility.',
                  style: SmText.caption.copyWith(
                    color: warnColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (a.auditorObservedLat != null)
              Text(
                'observed: ${a.auditorObservedLat!.toStringAsFixed(6)}, '
                '${a.auditorObservedLng!.toStringAsFixed(6)}',
                style: SmText.caption.copyWith(color: c.ink2),
              ),
            Text(
              'accuracy: ${a.gpsAccuracyMeters == null ? "n/a" : "${a.gpsAccuracyMeters!.toStringAsFixed(1)} m"}'
              ' · age at capture: ${a.gpsAgeSecondsAtCapture == null ? "n/a" : "${a.gpsAgeSecondsAtCapture} s"}',
              style: SmText.caption.copyWith(color: c.ink3),
            ),
            Text(
              d == null
                  ? 'distance from mapped point: n/a'
                  : 'distance from mapped point: ${d.toStringAsFixed(1)} m',
              style: SmText.caption.copyWith(color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoSection(SmColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SmTokens.s12),
          decoration: BoxDecoration(
            color: c.statusUnsure.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(SmTokens.rSmall),
          ),
          child: Text(
            'Do not photograph people or occupied / private cubicle situations.',
            style: SmText.caption.copyWith(
              color: c.statusUnsure,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: SmTokens.s8),
        Text(
          a.photoFilenames.isEmpty
              ? 'Entrance / signage photo strongly recommended (optional).'
              : '${a.photoFilenames.length} photo(s) attached.',
          style: SmText.caption.copyWith(color: c.ink3),
        ),
        const SizedBox(height: SmTokens.s8),
        Wrap(
          spacing: SmTokens.s8,
          runSpacing: SmTokens.s8,
          children: [
            for (final fn in a.photoFilenames) _thumb(c, fn),
            _addTile(
              c,
              Icons.photo_camera_outlined,
              'Camera',
              () => _addPhoto(ImageSource.camera),
            ),
            _addTile(
              c,
              Icons.photo_library_outlined,
              'Gallery',
              () => _addPhoto(ImageSource.gallery),
            ),
          ],
        ),
      ],
    );
  }

  Widget _thumb(SmColors c, String fn) {
    final path = _photosDirPath;
    return Stack(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(SmTokens.rSmall),
            border: Border.all(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: path == null
              ? const SizedBox.shrink()
              : Image.file(
                  File('$path/$fn'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.broken_image_outlined, color: c.ink3),
                ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: IconButton(
            icon: Icon(Icons.cancel, color: c.statusClosed, size: 20),
            onPressed: () => _removePhoto(fn),
          ),
        ),
      ],
    );
  }

  Widget _addTile(SmColors c, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(SmTokens.rSmall),
      onTap: onTap,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SmTokens.rSmall),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c.brand),
            const SizedBox(height: 4),
            Text(label, style: SmText.caption.copyWith(color: c.ink2)),
          ],
        ),
      ),
    );
  }

  Color _colorFor4(SmColors c, FourStateUsable v) {
    switch (v) {
      case FourStateUsable.yes:
        return c.statusOpen;
      case FourStateUsable.no:
        return c.statusClosed;
      case FourStateUsable.indeterminate:
        return c.statusUnsure;
      case FourStateUsable.notObserved:
        return c.ink3;
    }
  }

  Color _colorForMapped(SmColors c, MappedOptionUsable v) {
    switch (v) {
      case MappedOptionUsable.yes:
        return c.statusOpen;
      case MappedOptionUsable.no:
        return c.statusClosed;
      case MappedOptionUsable.indeterminate:
        return c.statusUnsure;
      case MappedOptionUsable.notApplicable:
        return c.ink3;
    }
  }

  Widget _verdictCard(
    SmColors c,
    String key,
    String value,
    String reason,
    Color col,
  ) {
    return SmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, size: 18, color: col),
              const SizedBox(width: SmTokens.s8),
              Expanded(
                child: Text(
                  '$key = $value',
                  style: SmText.bodyStrong.copyWith(color: col),
                ),
              ),
            ],
          ),
          const SizedBox(height: SmTokens.s4),
          Text(reason, style: SmText.caption.copyWith(color: c.ink2)),
        ],
      ),
    );
  }

  Widget _bottomBar(SmColors c) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        SmTokens.s16,
        SmTokens.s8,
        SmTokens.s16,
        SmTokens.s12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await _persist(revisit: true);
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Mark revisit'),
                ),
              ),
              const SizedBox(width: SmTokens.s8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await _persist();
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: SmTokens.s8),
          SmPrimaryButton(
            label: 'Save & complete',
            icon: Icons.check_rounded,
            onTap: _saveAndComplete,
          ),
        ],
      ),
    );
  }
}
