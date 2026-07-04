// lib/theme/sm_theme.dart  (v2 — audited)
//
// Builds the light & dark ThemeData from tokens, exposes `context.sm` for
// semantic colours and `context.smSoft`/`context.smHeavy` for shadows, and a
// text-scale clamp for accessibility.
//
// SAFE TO ADD: additive. Wiring into MaterialApp is one explicit step (Task 1),
// a ~6-line change to main.dart only.
//
// v2 audit changes:
//  - surfaceTint: transparent (kills M3 purple elevation tint -> on-brand).
//  - TextTheme now PRESERVES every slot the existing app reads (displaySmall,
//    titleLarge, titleMedium, bodyMedium, labelSmall) at original sizes, so
//    not-yet-migrated screens do not regress during migration.
//  - context.smSoft / context.smHeavy shadow accessors (brightness-aware).
//  - clampTextScale null-guarded; no global splash override (zero behaviour
//    change in the foundation step).

import 'package:flutter/material.dart';
import 'sm_tokens.dart';

/// Read semantic tokens anywhere. Never null (falls back to light).
extension SmContextX on BuildContext {
  SmColors get sm => Theme.of(this).extension<SmColors>() ?? SmColors.light;

  List<BoxShadow> get smSoft => Theme.of(this).brightness == Brightness.light
      ? SmShadow.softLight
      : SmShadow.softDark;

  List<BoxShadow> get smHeavy => Theme.of(this).brightness == Brightness.light
      ? SmShadow.heavyLight
      : SmShadow.heavyDark;
}

class SmTheme {
  SmTheme._();

  static ThemeData light() => _build(Brightness.light, SmColors.light);
  static ThemeData dark() => _build(Brightness.dark, SmColors.dark);

  static ThemeData _build(Brightness brightness, SmColors c) {
    final base = brightness == Brightness.light
        ? const ColorScheme.light()
        : const ColorScheme.dark();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.line,
      colorScheme: base.copyWith(
        brightness: brightness,
        primary: c.brandSolid,
        onPrimary: c.onBrand,
        surface: c.surface,
        onSurface: c.ink,
        surfaceTint: Colors.transparent, // no M3 elevation tint -> on-brand
        error: c.statusClosed,
        onError: c.onBrand,
      ),
      textTheme: _textTheme(c),
      extensions: <ThemeExtension<dynamic>>[c],
    );
  }

  // Preserves the slots the existing app already reads, mapped to the new
  // scale/colours, plus the new hero slots. Prevents transitional regressions.
  static TextTheme _textTheme(SmColors c) {
    return TextTheme(
      displayLarge: SmText.hero.copyWith(color: c.ink), // new: hero distance
      displayMedium: SmText.heroSmall.copyWith(
        color: c.ink,
      ), // new: smaller hero
      displaySmall: SmText.title.copyWith(
        color: c.ink,
        fontSize: 24.0,
      ), // old app: 24/w800
      titleLarge: SmText.subhead.copyWith(
        color: c.ink,
        fontSize: 18.0,
        fontWeight: FontWeight.w800,
      ), // old: 18/w800
      titleMedium: SmText.subhead.copyWith(
        color: c.ink,
        fontSize: 16.0,
        fontWeight: FontWeight.w700,
      ), // old: 16/w700
      bodyLarge: SmText.body.copyWith(color: c.ink),
      bodyMedium: SmText.body.copyWith(
        color: c.ink2,
        fontSize: 14.0,
        fontWeight: FontWeight.w400,
      ), // old: 14/w400
      labelSmall: SmText.caption.copyWith(color: c.ink3), // old: 12/w500 grey
    );
  }

  /// Clamp OS dynamic-type so huge system fonts can't shatter layouts while
  /// still honouring accessibility. Wire once in MaterialApp.builder:
  ///   builder: (context, child) =>
  ///       child == null ? const SizedBox.shrink() : SmTheme.clampTextScale(context, child),
  static Widget clampTextScale(BuildContext context, Widget child) {
    final mq = MediaQuery.of(context);
    final clamped = mq.textScaler.clamp(
      minScaleFactor: 0.9,
      maxScaleFactor: 1.3,
    );
    return MediaQuery(
      data: mq.copyWith(textScaler: clamped),
      child: child,
    );
  }
}
