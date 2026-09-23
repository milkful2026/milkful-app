import 'package:flutter/material.dart';

import '../../features/onboarding/data/registration_repository.dart';

/// The delivery-slot `ChoiceChip` picker shared by the cart (MA-120 FR-6)
/// and custom-schedule (MA-133 FR-7) subscribe flows — same `DeliverySlot`
/// source, same chip row, one place to keep style/behavior in sync.
class DeliverySlotChipRow extends StatelessWidget {
  const DeliverySlotChipRow({
    required this.slots,
    required this.selectedSlotId,
    required this.onSlotSelected,
    required this.keyPrefix,
    super.key,
  });

  final List<DeliverySlot> slots;
  final String? selectedSlotId;
  final ValueChanged<String> onSlotSelected;

  /// Distinguishes each call site's widget keys (existing widget tests key
  /// off e.g. `product-config-slot-*` vs `custom-schedule-slot-*`).
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final slot in slots)
          ChoiceChip(
            key: Key('$keyPrefix-${slot.id}'),
            label: Text(slot.label),
            selected: selectedSlotId == slot.id,
            onSelected: slot.available ? (_) => onSlotSelected(slot.id) : null,
            disabledColor: theme.colorScheme.surfaceContainerHighest,
          ),
      ],
    );
  }
}
