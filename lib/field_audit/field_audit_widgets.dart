// Field Audit — shared field-fast UI bits. Large tap targets, tokenised colours.

import 'package:flutter/material.dart';

import '../theme/sm_theme.dart';
import '../theme/sm_tokens.dart';

/// One selectable option in a choice row.
class AuditOption<T> {
  const AuditOption(
    this.value,
    this.label, {
    this.emphasis = AuditEmphasis.neutral,
  });
  final T value;
  final String label;
  final AuditEmphasis emphasis;
}

enum AuditEmphasis { neutral, good, bad, unknown }

/// A labelled horizontal set of large chips. `not_checked` / `unknown` options
/// are always present and are the default selection.
class AuditChoiceRow<T> extends StatelessWidget {
  const AuditChoiceRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final T value;
  final List<AuditOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SmTokens.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: SmText.body.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: SmText.caption.copyWith(color: c.ink3)),
          ],
          const SizedBox(height: SmTokens.s8),
          Wrap(
            spacing: SmTokens.s8,
            runSpacing: SmTokens.s8,
            children: [
              for (final o in options)
                _AuditChip(
                  label: o.label,
                  selected: o.value == value,
                  emphasis: o.emphasis,
                  onTap: () => onChanged(o.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuditChip extends StatelessWidget {
  const _AuditChip({
    required this.label,
    required this.selected,
    required this.emphasis,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AuditEmphasis emphasis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sm;
    Color accent;
    switch (emphasis) {
      case AuditEmphasis.good:
        accent = c.statusOpen;
        break;
      case AuditEmphasis.bad:
        accent = c.statusClosed;
        break;
      case AuditEmphasis.unknown:
        accent = c.statusUnsure;
        break;
      case AuditEmphasis.neutral:
        accent = c.brandSolid;
        break;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(SmTokens.rSmall),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: SmTokens.s16,
            vertical: SmTokens.s12,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : c.surface,
            borderRadius: BorderRadius.circular(SmTokens.rSmall),
            border: Border.all(
              color: selected ? accent : c.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: SmText.body.copyWith(
              color: selected ? accent : c.ink2,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class AuditSectionHeader extends StatelessWidget {
  const AuditSectionHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: SmTokens.s24, bottom: SmTokens.s4),
    child: Text(
      text.toUpperCase(),
      style: SmText.eyebrow.copyWith(color: context.sm.ink3),
    ),
  );
}
