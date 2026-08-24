import 'package:equatable/equatable.dart';

import '../../catalog/models/product.dart';
import '../models/frequency.dart';

sealed class ProductConfigEvent extends Equatable {
  const ProductConfigEvent();

  @override
  List<Object?> get props => [];
}

/// Fired once on screen open. [product] is whatever the catalog card
/// passed via the route's `extra:` (seeds the initial render only — see
/// MA-120 §9); this event also kicks off the stale-stock re-fetch and,
/// for a subscription-eligible product, the wallet-balance read.
class ProductConfigStarted extends ProductConfigEvent {
  const ProductConfigStarted(this.product);

  final Product product;

  @override
  List<Object?> get props => [product];
}

class FrequencyChanged extends ProductConfigEvent {
  const FrequencyChanged(this.frequency);

  final Frequency frequency;

  @override
  List<Object?> get props => [frequency];
}

class StartDateChanged extends ProductConfigEvent {
  const StartDateChanged(this.date);

  final DateTime date;

  @override
  List<Object?> get props => [date];
}

class QuantityChanged extends ProductConfigEvent {
  const QuantityChanged(this.quantity);

  final int quantity;

  @override
  List<Object?> get props => [quantity];
}

class AddToCartRequested extends ProductConfigEvent {
  const AddToCartRequested();
}

/// Internal — fired by the three selection-changing events above (after
/// each updates `state.selection`) rather than requested directly by the
/// screen. Funnels every quote-triggering change through one event type so
/// a single `restartable()` transformer (see product_config_bloc.dart)
/// covers frequency changes racing quantity changes, not just repeated
/// instances of the same event type the way CatalogBloc's per-event
/// `restartable()` registrations do.
class QuoteRequested extends ProductConfigEvent {
  const QuoteRequested();
}
