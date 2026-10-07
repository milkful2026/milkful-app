import 'package:flutter/material.dart';

import '../../bloc/order_detail_cubit.dart';
import '../../domain/cancel_copy.dart';
import '../../models/order_summary.dart';

/// MA-155 FR-2 — the cancel sheet: policy, optional reason, Keep / Cancel.
/// Pops with the [CancelOutcome] once the request settles, except on a
/// plain failure, where it stays open with an inline error and the chosen
/// reason kept. While the request runs nothing can dismiss it.
class CancelOrderSheet extends StatefulWidget {
  const CancelOrderSheet({super.key, required this.order, required this.onConfirm});

  final OrderSummary order;
  final Future<CancelOutcome?> Function(CancelReason? reason) onConfirm;

  @override
  State<CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<CancelOrderSheet> {
  CancelReason? _reason;
  bool _submitting = false;
  bool _failed = false;

  Future<void> _confirm() async {
    setState(() {
      _submitting = true;
      _failed = false;
    });
    final outcome = await widget.onConfirm(_reason);
    if (!mounted) return;
    if (outcome == CancelOutcome.failed) {
      setState(() {
        _submitting = false;
        _failed = true;
      });
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return PopScope(
      canPop: !_submitting,
      child: SafeArea(
        child: Padding(
          key: const Key('cancelOrder.sheet'),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cancel this order?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(sheetPolicy(widget.order), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              Text('Reason (optional)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in CancelReason.values)
                    ChoiceChip(
                      key: Key('cancelOrder.reason.${reason.wire}'),
                      label: Text(reasonLabel(reason)),
                      selected: _reason == reason,
                      // Tapping the selected chip again clears it.
                      onSelected: _submitting
                          ? null
                          : (selected) => setState(() => _reason = selected ? reason : null),
                    ),
                ],
              ),
              if (_failed) ...[
                const SizedBox(height: 12),
                Text(
                  cancelFailedMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(color: error),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('cancelOrder.keep'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Keep order'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // The spinner replaces the label, so a screen reader still
                    // hears the button's name while it's busy (MA-152 pattern).
                    child: Semantics(
                      button: true,
                      enabled: !_submitting,
                      label: 'Cancel order',
                      excludeSemantics: _submitting,
                      child: FilledButton(
                        key: const Key('cancelOrder.confirm'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                        onPressed: _submitting ? null : _confirm,
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Cancel order'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
