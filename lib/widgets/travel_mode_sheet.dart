import 'package:flutter/material.dart';
import '../utils/map_launcher.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

/// Single source of truth for the travel-mode bottom sheet.
/// Returns the chosen [TravelMode], or null if dismissed.
/// Pass [distanceMeters] to show per-mode ETA; omit for no ETA.
Future<TravelMode?> showTravelModeSheet(
  BuildContext context, {
  double? distanceMeters,
}) {
  final driveMin = distanceMeters != null
      ? (distanceMeters / 11.1 / 60).ceil()
      : null;
  final bikeMin = distanceMeters != null
      ? (distanceMeters / 4.1 / 60).ceil()
      : null;
  final walkMin = distanceMeters != null
      ? (distanceMeters / 1.4 / 60).ceil()
      : null;

  return showModalBottomSheet<TravelMode>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final c = context.sm;
      return Container(
        decoration: smSheetDecoration(context),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: SmTokens.s8),
              const SmGrabHandle(),
              const SizedBox(height: SmTokens.s12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SmTokens.s20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: const SmEyebrow('How will you get there?'),
                ),
              ),
              const SizedBox(height: SmTokens.s8),
              _ModeRow(
                icon: Icons.directions_car,
                label: 'Drive',
                eta: driveMin != null ? '~$driveMin min' : null,
                mode: TravelMode.driving,
                c: c,
              ),
              _ModeRow(
                icon: Icons.directions_bike,
                label: 'Ride',
                eta: bikeMin != null ? '~$bikeMin min' : null,
                mode: TravelMode.bicycling,
                c: c,
              ),
              _ModeRow(
                icon: Icons.directions_walk,
                label: 'Walk',
                eta: walkMin != null ? '~$walkMin min' : null,
                mode: TravelMode.walking,
                c: c,
              ),
              const SizedBox(height: SmTokens.s16),
            ],
          ),
        ),
      );
    },
  );
}

class _ModeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? eta;
  final TravelMode mode;
  final SmColors c;

  const _ModeRow({
    required this.icon,
    required this.label,
    required this.eta,
    required this.mode,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SmTokens.s20,
          vertical: SmTokens.s16,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(SmTokens.rSmall),
              ),
              child: Icon(icon, color: c.brand, size: 20),
            ),
            const SizedBox(width: SmTokens.s16),
            Expanded(
              child: Text(
                label,
                style: SmText.body.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (eta != null)
              Text(eta!, style: SmText.body.copyWith(color: c.ink2)),
          ],
        ),
      ),
    );
  }
}
