import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Small, unobtrusive credit for the OpenStreetMap-derived toilet location
/// data (ODbL requires attribution to be reasonably visible to end users,
/// not just documented in the repo). This is about the TOILET DATA, not the
/// Google Maps tiles rendered underneath — the wording says so explicitly so
/// the two are never conflated.
class OsmAttributionBadge extends StatelessWidget {
  const OsmAttributionBadge({super.key});

  static final Uri _copyrightUrl = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () =>
            launchUrl(_copyrightUrl, mode: LaunchMode.externalApplication),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'Toilet data: © OpenStreetMap contributors',
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
      ),
    );
  }
}
