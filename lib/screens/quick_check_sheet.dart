import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/custom_haptics_service.dart';
import '../main.dart' show showAppSnackBar;
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

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
  bool? _hasWater;
  bool? _doorLocks;
  bool? _safeApproach;
  bool? _womenSafetyOk;
  bool _isSubmitting = false;

  final FirestoreService _firestoreService = FirestoreService();

  bool get _canSubmit =>
      _hasWater != null &&
      _doorLocks != null &&
      _safeApproach != null &&
      _womenSafetyOk != null;

  Widget _buildToggleRow(
    String question,
    bool? value,
    void Function(bool) onChanged,
  ) {
    return SizedBox(
      height: 56.0,
      child: Row(
        children: [
          Expanded(
            child: Text(
              question,
              style: SmText.body.copyWith(color: context.sm.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12.0),
          _buildSegment("Yes", true, value, onChanged),
          const SizedBox(width: 4.0),
          _buildSegment("No", false, value, onChanged),
        ],
      ),
    );
  }

  Widget _buildSegment(
    String label,
    bool segmentValue,
    bool? current,
    void Function(bool) onChanged,
  ) {
    final c = context.sm;
    final bool isSelected = current == segmentValue;
    final Color activeColor = segmentValue ? c.statusOpen : c.statusClosed;
    return GestureDetector(
      onTap: () {
        CustomHapticsService.playToggleSnap();
        onChanged(segmentValue);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SmTokens.s16,
          vertical: SmTokens.s8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : c.soft,
          borderRadius: BorderRadius.circular(SmTokens.rSmall),
          border: Border.all(
            color: isSelected ? activeColor : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: SmText.subhead.copyWith(
            color: isSelected ? Colors.white : c.ink2,
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      await _firestoreService.submitQuickCheck(
        widget.toilet.id,
        widget.userId,
        widget.userName,
        _hasWater!,
        _doorLocks!,
        _safeApproach!,
        _womenSafetyOk!,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SmGrabHandle(),
          Text('Quick check', style: SmText.title.copyWith(color: c.ink)),
          const SizedBox(height: SmTokens.s20),
          _buildToggleRow(
            "Running water right now?",
            _hasWater,
            (v) => setState(() => _hasWater = v),
          ),
          const Divider(color: Colors.transparent, height: 1.0),
          _buildToggleRow(
            "Door locks properly?",
            _doorLocks,
            (v) => setState(() => _doorLocks = v),
          ),
          const Divider(color: Colors.transparent, height: 1.0),
          _buildToggleRow(
            "Safe approach / no issues?",
            _safeApproach,
            (v) => setState(() => _safeApproach = v),
          ),
          const Divider(color: Colors.transparent, height: 1.0),
          _buildToggleRow(
            "Safe for women / no harassment?",
            _womenSafetyOk,
            (v) => setState(() => _womenSafetyOk = v),
          ),
          const SizedBox(height: SmTokens.s24),
          SmPrimaryButton(
            label: 'Check in +15 XP',
            onTap: _canSubmit && !_isSubmitting ? _submit : null,
          ),
        ],
      ),
    );
  }
}
