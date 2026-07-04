// lib/widgets/sm_states.dart
// Additive — presents the 6 canonical app states.
// Import and use in screens. No logic; no Firestore.

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

enum _StateKind { loading, empty, offline, noGps, noOpen, error }

class SmStateView extends StatelessWidget {
  final _StateKind _kind;
  final String? message;
  final String? subMessage;
  final VoidCallback? onAction;
  final String? actionLabel;
  final IconData? icon;

  const SmStateView._(
    this._kind, {
    this.message,
    this.subMessage,
    this.onAction,
    this.actionLabel,
    this.icon,
  });

  /// Shimmer skeleton — use while toilets list is empty and loading.
  factory SmStateView.loading() => const SmStateView._(_StateKind.loading);

  /// Zero results — rural area or filtered-out everything.
  factory SmStateView.empty({VoidCallback? onAdd}) => SmStateView._(
    _StateKind.empty,
    icon: Icons.add_location_alt_outlined,
    message: 'No toilets mapped here yet',
    subMessage:
        'Be the first to put one on the map — it helps your whole city.',
    actionLabel: 'Add a toilet +50 XP',
    onAction: onAdd,
  );

  /// Device offline — showing cached data.
  factory SmStateView.offline() => const SmStateView._(
    _StateKind.offline,
    icon: Icons.wifi_off_outlined,
    message: 'You\'re offline',
    subMessage: 'Showing saved results. Connect to see live updates.',
  );

  /// GPS denied or unavailable — offer manual anchor.
  factory SmStateView.noGps({VoidCallback? onManual}) => SmStateView._(
    _StateKind.noGps,
    icon: Icons.location_off_outlined,
    message: 'Location unavailable',
    subMessage:
        'Allow location access or search by area to find nearby toilets.',
    actionLabel: 'Search by area',
    onAction: onManual,
  );

  /// Go was tapped but nothing nearby is open.
  factory SmStateView.noOpen({String? distance, VoidCallback? onShowClosed}) =>
      SmStateView._(
        _StateKind.noOpen,
        icon: Icons.do_not_disturb_alt_outlined,
        message: distance != null
            ? 'Nearest open toilet is $distance away'
            : 'No open toilets nearby right now',
        subMessage: 'All nearby toilets are closed. Try showing closed ones.',
        actionLabel: 'Show closed toilets',
        onAction: onShowClosed,
      );

  /// Generic error with retry.
  factory SmStateView.error({VoidCallback? onRetry}) => SmStateView._(
    _StateKind.error,
    icon: Icons.error_outline,
    message: 'Something went wrong',
    subMessage: 'Pull down to refresh, or tap retry.',
    actionLabel: 'Retry',
    onAction: onRetry,
  );

  @override
  Widget build(BuildContext context) {
    if (_kind == _StateKind.loading) return _buildShimmer(context);
    if (_kind == _StateKind.offline) return _buildBanner(context);
    return _buildCentered(context);
  }

  Widget _buildShimmer(BuildContext context) {
    final c = context.sm;
    return Shimmer.fromColors(
      baseColor: c.soft,
      highlightColor: c.surface,
      child: ListView.separated(
        padding: const EdgeInsets.all(SmTokens.s16),
        itemCount: 5,
        separatorBuilder: (context, index) =>
            const SizedBox(height: SmTokens.s12),
        itemBuilder: (context, index) => Container(
          height: 88,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SmTokens.rCard),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(BuildContext context) {
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

  Widget _buildCentered(BuildContext context) {
    final c = context.sm;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SmTokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
              child: Center(
                child: Icon(
                  icon ?? Icons.info_outline,
                  size: 32,
                  color: c.ink3,
                ),
              ),
            ),
            const SizedBox(height: SmTokens.s16),
            Text(
              message ?? '',
              style: SmText.subhead.copyWith(color: c.ink),
              textAlign: TextAlign.center,
            ),
            if (subMessage != null) ...[
              const SizedBox(height: SmTokens.s8),
              Text(
                subMessage!,
                style: SmText.body.copyWith(color: c.ink2),
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: SmTokens.s24),
              SmPrimaryButton(label: actionLabel!, onTap: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
