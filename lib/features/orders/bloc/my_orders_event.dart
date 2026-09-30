import 'dart:async';

import 'package:equatable/equatable.dart';

sealed class MyOrdersEvent extends Equatable {
  const MyOrdersEvent();

  @override
  List<Object?> get props => [];
}

class MyOrdersOpened extends MyOrdersEvent {
  const MyOrdersOpened();
}

/// Pull-to-refresh. [completer] resolves when the refresh settles, so the
/// `RefreshIndicator` spinner stays up for exactly as long as it runs.
class MyOrdersRefreshed extends MyOrdersEvent {
  MyOrdersRefreshed({Completer<void>? completer}) : completer = completer ?? Completer<void>();

  final Completer<void> completer;

  @override
  List<Object?> get props => [completer];
}

/// The Past Orders tab scrolled near its end (MA-145 FR-10).
class PastPageRequested extends MyOrdersEvent {
  const PastPageRequested();
}

/// "Retry" on a failure banner — reloads only the source(s) that failed.
class RetryFailedSources extends MyOrdersEvent {
  const RetryFailedSources();
}
