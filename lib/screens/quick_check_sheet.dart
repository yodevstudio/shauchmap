import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/custom_haptics_service.dart';
import '../main.dart' show showAppSnackBar;
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

/// Condition check (2026-09-02 trust model).
///
/// Replaces the legacy "Quick check". A tri-state observation of the facility
/// right now — Yes / No / Unknown, with **Unknown as a real, submittable
/// answer**. There is deliberately NO "safe for women / harassment" question:
/// one person's tap must never become a women-safety certification. Nothing
/// here writes to the parent toilet document.
class QuickCheckSheet extends StatefulWidget {
  final Toilet toilet;
  final String userId;
  final String userName;

  const QuickCheckSheet({
    super.key,
    required this.toilet,
    required this.userId,
    this.userName = '',
  });

  @override
  State<QuickCheckSheet> createState() => _QuickCheckSheetState();
}

class _QuickCheckSheetState extends State<QuickCheckSheet> {
  // null = not answered yet; 'yes' | 'no' | 'unknown' once the user picks.
  String? _open;
  String? _water;
  String? _usable;
  String? _lock;
  bool _isSubmitting = false;

  final FirestoreService _firestoreService = FirestoreService();

  // The three core dimensions must be answered (Unknown counts as answered).
  bool get _canSubmit => _open != null && _water != null && _usable != null;

  Widget _buildTriRow(
    String question,
    String? value,
    void Function(String) onChanged, {
    String? helper,
  }) {
    final c = context.sm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SmTokens.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: SmText.body.copyWith(color: c.ink)),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(helper, style: SmText.caption.copyWith(color: c.ink3)),
          ],
          const SizedBox(height: SmTokens.s8),
          Row(
            children: [
              _seg('Yes', 'yes', value, onChanged),
              const SizedBox(width: SmTokens.s8),
              _seg('No', 'no', value, onChanged),
              const SizedBox(width: SmTokens.s8),
              _seg('Unknown', 'unknown', value, onChanged),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seg(
    String label,
    String segValue,
    String? current,
    void Function(String) onChanged,
  ) {
    final c = context.sm;
    final bool selected = current == segValue;
    final Color active = switch (segValue) {
      'yes' => c.statusOpen,
      'no' => c.statusClosed,
      _ => c.statusUnsure,
    };
    return Expanded(
      child: GestureDetector(
        onTap: () {
          CustomHapticsService.playToggleSnap();
          onChanged(segValue);
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: SmTokens.s12),
          decoration: BoxDecoration(
            color: selected ? active : c.soft,
            borderRadius: BorderRadius.circular(SmTokens.rSmall),
            border: Border.all(
              color: selected ? active : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Text(
            label,
            style: SmText.caption.copyWith(
              color: selected ? Colors.white : c.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      await _firestoreService.submitConditionCheck(
        widget.toilet.id,
        widget.userId,
        open: _open!,
        water: _water!,
        usable: _usable!,
        lock: _lock,
      );
      CustomHapticsService.playCrispSuccess();
      if (mounted) {
        Navigator.of(context).pop();
        showAppSnackBar('Thanks! You earned 15 Scout Points.');
      }
    } catch (e) {
      if (mounted) showAppSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return Container(
      decoration: smSheetDecoration(context),
      padding: EdgeInsets.only(
        left: SmTokens.s24,
        right: SmTokens.s24,
        top: SmTokens.s12,
        bottom: MediaQuery.of(context).viewInsets.bottom + SmTokens.s24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SmGrabHandle(),
            Text('Condition check', style: SmText.title.copyWith(color: c.ink)),
            const SizedBox(height: SmTokens.s4),
            Text(
              'What did you actually see just now? "Unknown" is a valid answer.',
              style: SmText.caption.copyWith(color: c.ink2),
            ),
            const SizedBox(height: SmTokens.s12),
            _buildTriRow(
              'Open right now?',
              _open,
              (v) => setState(() => _open = v),
            ),
            _buildTriRow(
              'Running water?',
              _water,
              (v) => setState(() => _water = v),
            ),
            _buildTriRow(
              'Usable / not out of order?',
              _usable,
              (v) => setState(() => _usable = v),
            ),
            _buildTriRow(
              'Door / latch works?',
              _lock,
              (v) => setState(() => _lock = v),
              helper: 'Optional',
            ),
            const SizedBox(height: SmTokens.s20),
            SmPrimaryButton(
              label: 'Submit +15 XP',
              onTap: _canSubmit && !_isSubmitting ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
