import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../utils/map_launcher.dart';
import '../theme/sm_tokens.dart';
import '../theme/sm_theme.dart';
import '../theme/sm_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final settings = AppSettings.instance;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: c.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings', style: SmText.subhead.copyWith(color: c.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SmTokens.s16,
          vertical: SmTokens.s8,
        ),
        children: [
          // ── Appearance ──────────────────────────────────────────────
          _SectionHeader('Appearance'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: settings.themeMode,
            builder: (context, mode, child) => SmCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ThemeRow(
                    icon: Icons.light_mode_rounded,
                    label: 'Light',
                    selected: mode == ThemeMode.light,
                    onTap: () => settings.setThemeMode(ThemeMode.light),
                    c: c,
                  ),
                  Divider(height: 1, color: c.line),
                  _ThemeRow(
                    icon: Icons.dark_mode_rounded,
                    label: 'Dark',
                    selected: mode == ThemeMode.dark,
                    onTap: () => settings.setThemeMode(ThemeMode.dark),
                    c: c,
                  ),
                  Divider(height: 1, color: c.line),
                  _ThemeRow(
                    icon: Icons.phone_android_rounded,
                    label: 'System default',
                    selected: mode == ThemeMode.system,
                    onTap: () => settings.setThemeMode(ThemeMode.system),
                    c: c,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: SmTokens.s20),

          // ── Navigation ───────────────────────────────────────────────
          _SectionHeader('Preferred travel mode'),
          ValueListenableBuilder<TravelMode>(
            valueListenable: settings.travelMode,
            builder: (context, mode, child) => SmCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _TravelRow(
                    icon: Icons.directions_walk,
                    label: 'Walk',
                    selected: mode == TravelMode.walking,
                    onTap: () => settings.setTravelMode(TravelMode.walking),
                    c: c,
                  ),
                  Divider(height: 1, color: c.line),
                  _TravelRow(
                    icon: Icons.directions_bike,
                    label: 'Ride',
                    selected: mode == TravelMode.bicycling,
                    onTap: () => settings.setTravelMode(TravelMode.bicycling),
                    c: c,
                  ),
                  Divider(height: 1, color: c.line),
                  _TravelRow(
                    icon: Icons.directions_car,
                    label: 'Drive',
                    selected: mode == TravelMode.driving,
                    onTap: () => settings.setTravelMode(TravelMode.driving),
                    c: c,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: SmTokens.s32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: SmTokens.s4,
        bottom: SmTokens.s8,
        top: SmTokens.s4,
      ),
      child: SmEyebrow(text),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SmColors c;

  const _ThemeRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SmTokens.rCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SmTokens.s16,
          vertical: SmTokens.s12,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? c.brand : c.ink2),
            const SizedBox(width: SmTokens.s12),
            Expanded(
              child: Text(
                label,
                style: SmText.body.copyWith(
                  color: selected ? c.brand : c.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 18, color: c.brandSolid),
          ],
        ),
      ),
    );
  }
}

class _TravelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SmColors c;

  const _TravelRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) => _ThemeRow(
    icon: icon,
    label: label,
    selected: selected,
    onTap: onTap,
    c: c,
  );
}
