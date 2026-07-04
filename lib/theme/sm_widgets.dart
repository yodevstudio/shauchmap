// lib/theme/sm_widgets.dart
//
// Canonical UI building blocks that encode the agreed mockup exactly, built
// only from tokens (sm_tokens.dart) + theme accessors (sm_theme.dart).
//
// SAFE TO ADD: additive. No logic, no Firestore, no model. Screens import and
// reuse these so the redesign is pixel-consistent and cannot drift.
//
// Rules honoured: no .withOpacity (uses .withValues), no BackdropFilter/blur,
// depth via tinted shadow + hairline + surface only.

import 'package:flutter/material.dart';
import 'sm_tokens.dart';
import 'sm_theme.dart';

/// Tinted card: surface + hairline + soft brand-tinted shadow. Optional tap.
class SmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool heavy;
  const SmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SmTokens.s16),
    this.onTap,
    this.heavy = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SmTokens.rCard),
        border: Border.all(color: c.line, width: 1),
        boxShadow: heavy ? context.smHeavy : context.smSoft,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SmTokens.rCard),
          splashColor: Colors.transparent,
          highlightColor: c.soft,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The single hero action (Navigate / Add / Submit).
/// Depth via neutral shadow + subtle gradient bevel + press-sink.
/// NO colored glow — that is reserved for GO only.
class SmPrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const SmPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  });

  @override
  State<SmPrimaryButton> createState() => _SmPrimaryButtonState();
}

class _SmPrimaryButtonState extends State<SmPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topColor = Color.lerp(c.brandSolid, Colors.white, 0.06)!;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          constraints: const BoxConstraints(
            minHeight: SmTokens.minTouch,
            minWidth: double.infinity,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: SmTokens.s16,
            vertical: SmTokens.s12,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [topColor, c.brandSolid],
            ),
            borderRadius: BorderRadius.circular(SmTokens.rCard),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.18),
                width: 1,
              ),
            ),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: const Color(0x1F0E1A16),
                      blurRadius: _pressed ? 6 : 16,
                      spreadRadius: -6,
                      offset: Offset(0, _pressed ? 2 : 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: c.onBrand, size: 20),
                const SizedBox(width: SmTokens.s8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: SmText.subhead.copyWith(
                    color: c.onBrand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Secondary square icon button (Save / Share). Surface + hairline, 48dp target.
class SmIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const SmIconButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SmTokens.rSmall),
        border: Border.all(color: c.line, width: 1),
        boxShadow: context.smSoft,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SmTokens.rSmall),
          child: SizedBox(
            width: SmTokens.minTouch,
            height: SmTokens.minTouch,
            child: Center(child: Icon(icon, size: 20, color: c.ink2)),
          ),
        ),
      ),
    );
  }
}

/// Status values, colour-blind safe: always dot + word + icon, never colour alone.
enum SmStatus { open, closed, unsure }

class SmStatusLabel extends StatelessWidget {
  final SmStatus status;
  final String? text;
  const SmStatusLabel(this.status, {super.key, this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final (Color color, IconData icon, String label) = switch (status) {
      SmStatus.open => (
        c.statusOpen,
        Icons.check_circle_outline,
        text ?? 'Open',
      ),
      SmStatus.closed => (c.statusClosed, Icons.schedule, text ?? 'Closed'),
      SmStatus.unsure => (
        c.statusUnsure,
        Icons.help_outline,
        text ?? 'Needs check',
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: SmText.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: SmTokens.s4),
        Icon(icon, size: 14, color: color),
      ],
    );
  }
}

/// Filter pill: on = brand-solid, off = surface + hairline.
class SmFilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  const SmFilterChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final fg = selected ? c.brand : c.ink2;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(SmTokens.rPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: SmTokens.s12,
            vertical: SmTokens.s8,
          ),
          decoration: BoxDecoration(
            color: selected ? c.brandSolid.withValues(alpha: 0.10) : c.surface,
            borderRadius: BorderRadius.circular(SmTokens.rPill),
            border: Border.all(
              color: selected ? c.brandSolid : c.line,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: SmText.caption.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tracked, uppercase section label.
class SmEyebrow extends StatelessWidget {
  final String text;
  const SmEyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: SmText.eyebrow.copyWith(color: context.sm.ink3),
  );
}

/// One amenity row. true = Yes (teal), false = No (MUTED grey, never red),
/// null = Not sure (amber). Word always shown — never hidden (accessibility).
class SmAmenityValue extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool? value;
  const SmAmenityValue({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    final Color bg;
    final Color fg;
    final String t;
    if (value == true) {
      bg = c.statusOpen.withValues(alpha: 0.14);
      fg = c.statusOpen;
      t = 'Yes';
    } else if (value == false) {
      bg = c.soft; // MUTED — not red
      fg = c.ink3;
      t = 'No';
    } else {
      bg = c.statusUnsure.withValues(alpha: 0.16);
      fg = c.statusUnsure;
      t = 'Not sure';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SmTokens.s16,
        vertical: SmTokens.s12,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.ink2),
          const SizedBox(width: SmTokens.s12),
          Expanded(
            child: Text(
              label,
              style: SmText.body.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(SmTokens.rPill),
            ),
            child: Text(
              t,
              style: SmText.caption.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet surface decoration (apply to your sheet's container).
BoxDecoration smSheetDecoration(BuildContext context) => BoxDecoration(
  color: context.sm.surface,
  borderRadius: const BorderRadius.vertical(
    top: Radius.circular(SmTokens.rSheet),
  ),
  border: Border.all(color: context.sm.line, width: 1),
);

/// The little drag handle for sheets.
class SmGrabHandle extends StatelessWidget {
  const SmGrabHandle({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 5,
    margin: const EdgeInsets.symmetric(vertical: SmTokens.s8),
    decoration: BoxDecoration(
      color: context.sm.line,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}
