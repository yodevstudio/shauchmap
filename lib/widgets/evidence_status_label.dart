import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/presentation_truth.dart';
import '../services/firestore_service.dart';
import '../theme/sm_widgets.dart';

/// Renders a toilet's CURRENT condition status from the server-derived Evidence
/// V2 index, and SELF-EXPIRES.
///
/// A server-derived condition summary can go stale simply because time passes
/// (observations leaving the 60-minute window can flip the majority) with NO
/// Firestore write to trigger a rebuild. So when the evidence carries a
/// `validUntil`, this widget schedules exactly ONE `Timer` to that instant;
/// when it fires the widget rebuilds and `ToiletPresentation.fromEvidence`
/// returns "Status unconfirmed". No polling, no periodic timer. The timer is
/// re-scheduled when the toilet's evidence changes and cancelled on dispose.
///
/// Used by the map peek sheet, list rows and the GO preview so an expired
/// "Recent checks: open/closed" can never linger on screen.
class EvidenceStatusLabel extends StatefulWidget {
  final Toilet toilet;

  /// Injectable clock — `null` means `DateTime.now`. Only tests pass this.
  final DateTime Function()? clock;

  const EvidenceStatusLabel(this.toilet, {super.key, this.clock});

  @override
  State<EvidenceStatusLabel> createState() => _EvidenceStatusLabelState();
}

class _EvidenceStatusLabelState extends State<EvidenceStatusLabel> {
  Timer? _expiry;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant EvidenceStatusLabel old) {
    super.didUpdateWidget(old);
    if (old.toilet.id != widget.toilet.id ||
        old.toilet.evidence.condition.validUntil !=
            widget.toilet.evidence.condition.validUntil) {
      _schedule();
    }
  }

  void _schedule() {
    _expiry?.cancel();
    _expiry = null;
    final vu = widget.toilet.evidence.condition.validUntil;
    if (vu == null) return;
    final d = vu.difference(_now()) + const Duration(milliseconds: 50);
    if (d.isNegative) return; // already past — nothing to wait for
    _expiry = Timer(d, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pt = ToiletPresentation.fromEvidence(widget.toilet, now: _now());
    final SmStatus status = switch (pt.open) {
      Evidence.yes => SmStatus.open,
      Evidence.no => SmStatus.closed,
      Evidence.unknown => SmStatus.unsure,
    };
    return SmStatusLabel(status, text: pt.openLabel);
  }
}
