import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/id_generator.dart';
import '../../auth/data/profile_repository.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../../onboarding/data/registration_repository.dart';
import '../data/subscription_repository.dart';
import '../models/schedule.dart';

const _dayLabels = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

/// MA-133 FR-7 — the smallest addition that makes `WEEKLY`/`CUSTOM_DAYS`
/// reachable at all, since `ProductConfigScreen`'s own frequency selector
/// (FR-6) deliberately stays narrow (`DAILY`/`ALTERNATE_DAYS` only, MA-131
/// §6). A lightweight product picker → weekday-toggle form → the same
/// slot chip row FR-6 adds (same `getDeliverySlots(zoneId)` source) →
/// `SubscriptionRepository.create` directly — no bloc of its own; this is
/// a short-lived, self-contained form, same shape as `_TopUpAmountSheet`/
/// `_EditForm` elsewhere in this app. Pops `true` on a successful create
/// so the caller (`SubscriptionsScreen`) knows to refresh its list.
class CustomScheduleSheet extends StatefulWidget {
  const CustomScheduleSheet({super.key});

  @override
  State<CustomScheduleSheet> createState() => _CustomScheduleSheetState();
}

enum _LoadStatus { loading, loaded, failed }

class _CustomScheduleSheetState extends State<CustomScheduleSheet> {
  _LoadStatus _productsStatus = _LoadStatus.loading;
  List<Product> _products = const [];
  Product? _selectedProduct;

  int _quantity = 1;
  final Set<int> _selectedDays = {};

  _LoadStatus _slotsStatus = _LoadStatus.loading;
  List<DeliverySlot> _slots = const [];
  String? _slotId;

  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await context.read<CatalogRepository>().search();
      if (!mounted) return;
      setState(() {
        _products = products.where((p) => p.subscriptionEligible).toList();
        _productsStatus = _LoadStatus.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _productsStatus = _LoadStatus.failed);
    }
  }

  Future<void> _selectProduct(Product product) async {
    setState(() {
      _selectedProduct = product;
      _slotsStatus = _LoadStatus.loading;
    });
    // Same source as ProductConfigScreen's own slot picker (FR-6) — the
    // user's own default address zone, never RegistrationBloc's ephemeral
    // draft.zoneId (null outside an active registration session).
    // Both repositories are read before the first `await` (not via
    // `context.read` after one) — a `BuildContext` lookup is safe to make
    // synchronously but not across an async gap.
    final profileRepository = context.read<ProfileRepository>();
    final registrationRepository = context.read<RegistrationRepository>();
    try {
      final profile = await profileRepository.getMe();
      final zoneId = profile.defaultAddressZoneId;
      if (zoneId == null) {
        if (!mounted) return;
        setState(() {
          _slots = const [];
          _slotsStatus = _LoadStatus.loaded;
        });
        return;
      }
      final slots = await registrationRepository.getDeliverySlots(zoneId);
      if (!mounted) return;
      String? firstAvailable;
      for (final slot in slots) {
        if (slot.available) {
          firstAvailable = slot.id;
          break;
        }
      }
      setState(() {
        _slots = slots;
        _slotId = firstAvailable;
        _slotsStatus = _LoadStatus.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slots = const [];
        _slotsStatus = _LoadStatus.failed;
      });
    }
  }

  bool get _canSubmit =>
      _selectedProduct != null && _selectedDays.isNotEmpty && _slotId != null && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final days = _selectedDays.toList()..sort();
      await context.read<SubscriptionRepository>().create(
        productId: _selectedProduct!.id,
        quantity: _quantity,
        // A single selected day reads as "weekly on {Day}"; two or more
        // as an arbitrary custom-day pattern — Subscription Service
        // itself treats WEEKLY/CUSTOM_DAYS identically (both just need
        // daysOfWeek), this split only picks the more natural label
        // (schedule.dart's own Schedule.label()).
        schedule: Schedule(
          type: days.length == 1 ? ScheduleType.weekly : ScheduleType.customDays,
          daysOfWeek: days,
        ),
        startDate: DateTime.now(),
        slotId: _slotId!,
        idempotencyKey: newHexId(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      key: const Key('custom-schedule-sheet'),
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => _selectedProduct == null
          ? _ProductPicker(
              status: _productsStatus,
              products: _products,
              scrollController: scrollController,
              onSelect: _selectProduct,
              onRetry: () {
                setState(() => _productsStatus = _LoadStatus.loading);
                _loadProducts();
              },
            )
          : _ScheduleForm(
              product: _selectedProduct!,
              scrollController: scrollController,
              quantity: _quantity,
              onQuantityChanged: (q) => setState(() => _quantity = q),
              selectedDays: _selectedDays,
              onDayToggled: (day, selected) => setState(() {
                if (selected) {
                  _selectedDays.add(day);
                } else {
                  _selectedDays.remove(day);
                }
              }),
              slotsStatus: _slotsStatus,
              slots: _slots,
              selectedSlotId: _slotId,
              onSlotSelected: (id) => setState(() => _slotId = id),
              onBack: () => setState(() => _selectedProduct = null),
              canSubmit: _canSubmit,
              submitting: _submitting,
              submitError: _submitError,
              onSubmit: _submit,
            ),
    );
  }
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({
    required this.status,
    required this.products,
    required this.scrollController,
    required this.onSelect,
    required this.onRetry,
  });

  final _LoadStatus status;
  final List<Product> products;
  final ScrollController scrollController;
  final ValueChanged<Product> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _LoadStatus.loading:
        return const Center(
          key: Key('custom-schedule-products-loading'),
          child: CircularProgressIndicator(),
        );
      case _LoadStatus.failed:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't load products"),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('custom-schedule-products-retry'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      case _LoadStatus.loaded:
        if (products.isEmpty) {
          return const Center(
            key: Key('custom-schedule-products-empty'),
            child: Text('No subscription-eligible products available'),
          );
        }
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Choose a product', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    key: Key('custom-schedule-product-${product.id}'),
                    title: Text(product.name),
                    subtitle: Text(product.unit),
                    onTap: () => onSelect(product),
                  );
                },
              ),
            ),
          ],
        );
    }
  }
}

class _ScheduleForm extends StatelessWidget {
  const _ScheduleForm({
    required this.product,
    required this.scrollController,
    required this.quantity,
    required this.onQuantityChanged,
    required this.selectedDays,
    required this.onDayToggled,
    required this.slotsStatus,
    required this.slots,
    required this.selectedSlotId,
    required this.onSlotSelected,
    required this.onBack,
    required this.canSubmit,
    required this.submitting,
    required this.submitError,
    required this.onSubmit,
  });

  final Product product;
  final ScrollController scrollController;
  final int quantity;
  final ValueChanged<int> onQuantityChanged;
  final Set<int> selectedDays;
  final void Function(int day, bool selected) onDayToggled;
  final _LoadStatus slotsStatus;
  final List<DeliverySlot> slots;
  final String? selectedSlotId;
  final ValueChanged<String> onSlotSelected;
  final VoidCallback onBack;
  final bool canSubmit;
  final bool submitting;
  final String? submitError;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('custom-schedule-form'),
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('custom-schedule-back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(product.name, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Text('Quantity')),
            IconButton(
              key: const Key('custom-schedule-quantity-decrease'),
              icon: const Icon(Icons.remove),
              onPressed: quantity > 1 ? () => onQuantityChanged(quantity - 1) : null,
            ),
            Text('$quantity', key: const Key('custom-schedule-quantity-value')),
            IconButton(
              key: const Key('custom-schedule-quantity-increase'),
              icon: const Icon(Icons.add),
              onPressed: () => onQuantityChanged(quantity + 1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Delivery days'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in _dayLabels.entries)
              FilterChip(
                key: Key('custom-schedule-day-${entry.key}'),
                label: Text(entry.value),
                selected: selectedDays.contains(entry.key),
                onSelected: (selected) => onDayToggled(entry.key, selected),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (slotsStatus == _LoadStatus.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (slotsStatus == _LoadStatus.failed || slots.isEmpty) ...[
          const Text('Select Delivery Slot'),
          const SizedBox(height: 8),
          Text(
            "Couldn't load delivery slots for your address",
            key: const Key('custom-schedule-slots-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ] else ...[
          const Text('Select Delivery Slot'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in slots)
                ChoiceChip(
                  key: Key('custom-schedule-slot-${slot.id}'),
                  label: Text(slot.label),
                  selected: selectedSlotId == slot.id,
                  onSelected: slot.available ? (_) => onSlotSelected(slot.id) : null,
                ),
            ],
          ),
        ],
        if (submitError != null) ...[
          const SizedBox(height: 16),
          Text(
            submitError!,
            key: const Key('custom-schedule-submit-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('custom-schedule-submit'),
          onPressed: canSubmit ? onSubmit : null,
          child: submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create Subscription'),
        ),
      ],
    );
  }
}
