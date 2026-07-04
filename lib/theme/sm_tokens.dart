// lib/theme/sm_tokens.dart  (v2 — audited)
//
// ShauchMap design tokens — single source of truth for colour, type,
// spacing, radii, motion and SHADOW. Pure Flutter, no external packages.
//
// SAFE TO ADD: additive. Defines values only; changes no logic, no Firestore
// calls, no model. Nothing imports it until screens are migrated task-by-task.
//
// v2 audit changes:
//  - Added SmShadow (soft/heavy x light/dark) — brand-tinted depth, no blur.
//  - Light bg deepened (#E9F0EC) so white cards pop in harsh sunlight.
//  - Hero line-heights 1.0 -> 1.1; all heights made generous for Devanagari.

import 'package:flutter/material.dart';

class SmTokens {
  SmTokens._();

  // ---- Spacing (strict 8pt grid) ----
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;

  // ---- Corner radii ----
  static const double rSmall = 12.0;
  static const double rCard = 16.0;
  static const double rSheet = 24.0;
  static const double rPill = 999.0;

  // ---- Touch target ----
  static const double minTouch = 48.0;

  // ---- Motion durations ----
  static const Duration dSpring = Duration(milliseconds: 320);
  static const Duration dEase = Duration(milliseconds: 220);
  static const Duration dCrossFade = Duration(milliseconds: 300);

  // ---- Type sizes (logical px; scale with OS dynamic-type, clamped) ----
  static const double tEyebrow = 11.0;
  static const double tCaption = 12.0;
  static const double tBody = 15.0;
  static const double tSubhead = 17.0;
  static const double tTitle = 23.0;
  static const double tHeroSmall = 34.0;
  static const double tHero = 44.0;

  // ---- Font family ----
  // SAFE DEFAULT: null => platform default font, so nothing can break before
  // Noto is bundled. The localization task flips these two constants only.
  static const String? fontFamily = null;
  static const List<String>? fontFallback = null;
}

/// Brand-tinted elevation. No blur (BackdropFilter is banned). Depth comes
/// from these + a hairline border + a tinted surface. Select by theme
/// brightness via `context.smSoft` / `context.smHeavy` (see sm_theme.dart).
class SmShadow {
  SmShadow._();

  // Light: cool green-black tint, lifted look (negative spread + downward offset).
  static const List<BoxShadow> softLight = [
    BoxShadow(
      color: Color(0x24103C2D),
      blurRadius: 24,
      spreadRadius: -12,
      offset: Offset(0, 10),
    ),
  ];
  static const List<BoxShadow> heavyLight = [
    BoxShadow(
      color: Color(0x33103C2D),
      blurRadius: 50,
      spreadRadius: -24,
      offset: Offset(0, 22),
    ),
  ];

  // Dark: deep black, larger and softer.
  static const List<BoxShadow> softDark = [
    BoxShadow(
      color: Color(0xA6000000),
      blurRadius: 30,
      spreadRadius: -16,
      offset: Offset(0, 12),
    ),
  ];
  static const List<BoxShadow> heavyDark = [
    BoxShadow(
      color: Color(0xC2000000),
      blurRadius: 60,
      spreadRadius: -28,
      offset: Offset(0, 26),
    ),
  ];
}

/// Semantic colour tokens, theme-aware via ThemeExtension.
/// Access in widgets as `context.sm.surface`, `context.sm.statusOpen`, etc.
@immutable
class SmColors extends ThemeExtension<SmColors> {
  final Color bg;
  final Color surface;
  final Color line;
  final Color soft;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color brand;
  final Color brandSolid;
  final Color onBrand;
  final Color statusOpen;
  final Color statusClosed;
  final Color statusUnsure;
  final Color star;
  final Color womenSafe;

  const SmColors({
    required this.bg,
    required this.surface,
    required this.line,
    required this.soft,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.brand,
    required this.brandSolid,
    required this.onBrand,
    required this.statusOpen,
    required this.statusClosed,
    required this.statusUnsure,
    required this.star,
    required this.womenSafe,
  });

  // ---- LIGHT (default — tuned for outdoor daylight legibility) ----
  static const SmColors light = SmColors(
    bg: Color(0xFFE9F0EC), // deepened so #FFFFFF cards pop in sun
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFDCE6E1), // stronger hairline for glare
    soft: Color(0xFFE6EEEA),
    ink: Color(0xFF0E1A16),
    ink2: Color(0xFF5C6E68),
    ink3: Color(0xFF94A39D),
    brand: Color(0xFF0E8C63),
    brandSolid: Color(0xFF11A06F),
    onBrand: Color(0xFFFFFFFF),
    statusOpen: Color(0xFF0E8C63),
    statusClosed: Color(0xFFD64545),
    statusUnsure: Color(0xFFB8800F),
    star: Color(0xFFE8A317),
    womenSafe: Color(0xFFD31884),
  );

  // ---- DARK (night) ----
  static const SmColors dark = SmColors(
    bg: Color(0xFF0C1311),
    surface: Color(0xFF141E1B),
    line: Color(0xFF21302B),
    soft: Color(0xFF1A2622),
    ink: Color(0xFFF1F6F4),
    ink2: Color(0xFF9BB0AA),
    ink3: Color(0xFF5F726C),
    brand: Color(0xFF2BD49A),
    brandSolid: Color(0xFF11A06F),
    onBrand: Color(0xFFFFFFFF),
    statusOpen: Color(0xFF2BD49A),
    statusClosed: Color(0xFFFF6B5E),
    statusUnsure: Color(0xFFF2B53C),
    star: Color(0xFFF2B53C),
    womenSafe: Color(0xFFFF63B4),
  );

  @override
  SmColors copyWith({
    Color? bg,
    Color? surface,
    Color? line,
    Color? soft,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? brand,
    Color? brandSolid,
    Color? onBrand,
    Color? statusOpen,
    Color? statusClosed,
    Color? statusUnsure,
    Color? star,
    Color? womenSafe,
  }) {
    return SmColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      line: line ?? this.line,
      soft: soft ?? this.soft,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      brand: brand ?? this.brand,
      brandSolid: brandSolid ?? this.brandSolid,
      onBrand: onBrand ?? this.onBrand,
      statusOpen: statusOpen ?? this.statusOpen,
      statusClosed: statusClosed ?? this.statusClosed,
      statusUnsure: statusUnsure ?? this.statusUnsure,
      star: star ?? this.star,
      womenSafe: womenSafe ?? this.womenSafe,
    );
  }

  @override
  SmColors lerp(ThemeExtension<SmColors>? other, double t) {
    if (other is! SmColors) return this;
    return SmColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      line: Color.lerp(line, other.line, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandSolid: Color.lerp(brandSolid, other.brandSolid, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      statusOpen: Color.lerp(statusOpen, other.statusOpen, t)!,
      statusClosed: Color.lerp(statusClosed, other.statusClosed, t)!,
      statusUnsure: Color.lerp(statusUnsure, other.statusUnsure, t)!,
      star: Color.lerp(star, other.star, t)!,
      womenSafe: Color.lerp(womenSafe, other.womenSafe, t)!,
    );
  }
}

/// Type scale — rule of three (800 hero, 600 buttons/status, 400/500 body).
/// Colour-free; apply colour at call site:
///   Text('566', style: SmText.hero.copyWith(color: context.sm.ink))
/// Heights are generous so Devanagari/Tamil matras never clip.
class SmText {
  SmText._();

  static TextStyle _s(
    double size,
    FontWeight w, {
    double ls = 0,
    double h = 1.4,
    bool tabular = false,
  }) {
    return TextStyle(
      fontFamily: SmTokens.fontFamily,
      fontFamilyFallback: SmTokens.fontFallback,
      fontSize: size,
      fontWeight: w,
      letterSpacing: ls,
      height: h,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static TextStyle get eyebrow =>
      _s(SmTokens.tEyebrow, FontWeight.w800, ls: 1.2, h: 1.25);
  static TextStyle get caption =>
      _s(SmTokens.tCaption, FontWeight.w500, h: 1.35);
  static TextStyle get body => _s(SmTokens.tBody, FontWeight.w500, h: 1.45);
  static TextStyle get bodyStrong =>
      _s(SmTokens.tBody, FontWeight.w700, h: 1.45);
  static TextStyle get subhead =>
      _s(SmTokens.tSubhead, FontWeight.w600, h: 1.4);
  static TextStyle get title =>
      _s(SmTokens.tTitle, FontWeight.w800, ls: -0.4, h: 1.25);
  static TextStyle get heroSmall =>
      _s(SmTokens.tHeroSmall, FontWeight.w800, ls: -0.8, h: 1.1, tabular: true);
  static TextStyle get hero =>
      _s(SmTokens.tHero, FontWeight.w800, ls: -1.0, h: 1.1, tabular: true);
}
