import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/map_launcher.dart';

/// Global app settings backed by SharedPreferences.
/// Widgets listen via [ValueListenableBuilder].
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _keyTheme = 'settings_theme_mode';
  static const _keyTravel = 'settings_travel_mode';

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
  final ValueNotifier<TravelMode> travelMode = ValueNotifier(
    TravelMode.walking,
  );

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_keyTheme);
    themeMode.value = switch (t) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    final v = p.getString(_keyTravel);
    travelMode.value = switch (v) {
      'driving' => TravelMode.driving,
      'bicycling' => TravelMode.bicycling,
      _ => TravelMode.walking,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyTheme, switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      _ => 'light',
    });
  }

  Future<void> setTravelMode(TravelMode mode) async {
    travelMode.value = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyTravel, switch (mode) {
      TravelMode.driving => 'driving',
      TravelMode.bicycling => 'bicycling',
      _ => 'walking',
    });
  }
}
