// lib/widgets/sm_states.dart
// The offline banner state. No logic; no Firestore.

import 'package:flutter/material.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';

class SmStateView extends StatelessWidget {
  final String? message;

  const SmStateView._({this.message});

  /// Device offline — showing cached data.
  factory SmStateView.offline() =>
      const SmStateView._(message: "You're offline");

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SmTokens.s16,
        vertical: SmTokens.s12,
      ),
      color: c.statusUnsure.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.wifi_off_outlined, size: 16, color: c.statusUnsure),
          const SizedBox(width: SmTokens.s8),
          Expanded(
            child: Text(
              message ?? 'Offline — showing saved results',
              style: SmText.caption.copyWith(
                color: c.statusUnsure,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
