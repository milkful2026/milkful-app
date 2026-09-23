import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../bloc/subscription_bloc.dart';
import '../bloc/subscription_event.dart';
import '../models/schedule.dart';
import '../models/subscription_status.dart';
import '../models/subscription_view.dart';

final _dateFormat = DateFormat('MMM d, yyyy');

/// MA-133 FR-5 — Pause / Resume / Stop / Skip / Edit, reached by tapping a
/// subscription card. `showModalBottomSheet` (matches MA-125's own
/// `_TopUpAmountSheet` pattern).
class SubscriptionDetailSheet extends StatelessWidget {
  const SubscriptionDetailSheet({required this.subscription, super.key});

  final SubscriptionView subscription;

  Future<void> _pickPauseRange(BuildContext context) async {
    final bloc = context.read<SubscriptionBloc>();
    final indefinite = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pause deliveries'),
        content: const Text('Pause indefinitely, or choose a specific date range?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Choose dates'),
          ),
          TextButton(
            key: const Key('subscription-pause-indefinite'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Pause indefinitely'),
          ),
        ],
      ),
    );
    if (indefinite == null) return;
    if (indefinite) {
      bloc.add(PauseRequested(subscription.id));
      if (context.mounted) Navigator.of(context).pop();
      return;
    }
    if (!context.mounted) return;
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (range == null) return;
    bloc.add(PauseRequested(subscription.id, from: range.start, until: range.end));
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmStop(BuildContext context) async {
    final bloc = context.read<SubscriptionBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop this subscription?'),
        content: const Text("You'll need to subscribe again to resume it."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('subscription-stop-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      bloc.add(StopRequested(subscription.id));
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _confirmSkip(BuildContext context, DateTime date) async {
    final bloc = context.read<SubscriptionBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skip next delivery?'),
        content: Text('Skip the delivery on ${_dateFormat.format(date)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('subscription-skip-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      bloc.add(SkipRequested(subscription.id, date));
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _openEditForm(BuildContext context) async {
    final bloc = context.read<SubscriptionBloc>();
    final result = await showModalBottomSheet<({int quantity, Schedule? schedule})>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _EditForm(subscription: subscription),
    );
    if (result != null) {
      bloc.add(EditRequested(subscription.id, quantity: result.quantity, schedule: result.schedule));
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('subscription-detail-sheet'),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subscription.productName ?? subscription.productId,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(subscription.schedule.label()),
          const SizedBox(height: 20),
          if (subscription.status == SubscriptionStatus.active)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('subscription-pause-button'),
                onPressed: () => _pickPauseRange(context),
                child: const Text('Pause'),
              ),
            ),
          if (subscription.status == SubscriptionStatus.paused)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('subscription-resume-button'),
                onPressed: () {
                  context.read<SubscriptionBloc>().add(ResumeRequested(subscription.id));
                  Navigator.of(context).pop();
                },
                child: const Text('Resume'),
              ),
            ),
          const SizedBox(height: 8),
          if (subscription.status == SubscriptionStatus.active &&
              subscription.nextDeliveryDate != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('subscription-skip-button'),
                onPressed: () => _confirmSkip(context, subscription.nextDeliveryDate!),
                child: const Text('Skip next delivery'),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('subscription-edit-button'),
              onPressed: () => _openEditForm(context),
              child: const Text('Edit quantity / schedule'),
            ),
          ),
          const SizedBox(height: 8),
          if (subscription.status != SubscriptionStatus.stopped)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('subscription-stop-button'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => _confirmStop(context),
                child: const Text('Stop subscription'),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditForm extends StatefulWidget {
  const _EditForm({required this.subscription});

  final SubscriptionView subscription;

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late int _quantity;
  late Set<int> _selectedDays;

  bool get _showWeekdayToggles =>
      widget.subscription.schedule.type == ScheduleType.weekly ||
      widget.subscription.schedule.type == ScheduleType.customDays;

  @override
  void initState() {
    super.initState();
    _quantity = widget.subscription.quantity;
    _selectedDays = (widget.subscription.schedule.daysOfWeek ?? const []).toSet();
  }

  void _submit() {
    Schedule? schedule;
    if (_showWeekdayToggles) {
      schedule = Schedule(type: widget.subscription.schedule.type, daysOfWeek: _selectedDays.toList()..sort());
    }
    Navigator.of(context).pop((quantity: _quantity, schedule: schedule));
  }

  @override
  Widget build(BuildContext context) {
    const dayLabels = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit subscription', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Quantity')),
              IconButton(
                key: const Key('subscription-edit-quantity-decrease'),
                icon: const Icon(Icons.remove),
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              Text('$_quantity', key: const Key('subscription-edit-quantity-value')),
              IconButton(
                key: const Key('subscription-edit-quantity-increase'),
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _quantity++),
              ),
            ],
          ),
          if (_showWeekdayToggles) ...[
            const SizedBox(height: 12),
            const Text('Delivery days'),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in dayLabels.entries)
                  FilterChip(
                    key: Key('subscription-edit-day-${entry.key}'),
                    label: Text(entry.value),
                    selected: _selectedDays.contains(entry.key),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedDays.add(entry.key);
                      } else {
                        _selectedDays.remove(entry.key);
                      }
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('subscription-edit-submit'),
              onPressed: (_showWeekdayToggles && _selectedDays.isEmpty) ? null : _submit,
              child: const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}
