import 'package:flutter/material.dart';

import '../../domain/order_status_copy.dart';

/// Colours for a [ChipTone], from the theme's colour scheme (no hex
/// literals), shared by the list chip and the detail banner.
({Color background, Color foreground}) toneColors(BuildContext context, ChipTone tone) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    ChipTone.neutral => (
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
    ),
    ChipTone.error => (background: scheme.errorContainer, foreground: scheme.onErrorContainer),
    ChipTone.warning => (
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    ),
    ChipTone.primary => (
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    ),
  };
}

IconData? chipIconData(ChipIcon? icon) => switch (icon) {
  ChipIcon.checkCircle => Icons.check_circle_outline,
  ChipIcon.schedule => Icons.schedule,
  ChipIcon.errorOutline => Icons.error_outline,
  ChipIcon.cancel => Icons.cancel_outlined,
  ChipIcon.info => Icons.info_outline,
  ChipIcon.calendar => Icons.event,
  null => null,
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.spec, {super.key});

  final StatusChipSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(context, spec.tone);
    final icon = chipIconData(spec.icon);
    return Semantics(
      label: 'Status: ${spec.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.foreground),
              const SizedBox(width: 4),
            ],
            Text(
              spec.label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.foreground),
            ),
          ],
        ),
      ),
    );
  }
}
