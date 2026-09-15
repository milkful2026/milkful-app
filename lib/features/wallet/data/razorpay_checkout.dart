import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../models/payment_method.dart';

/// What [RazorpayCheckout.open] needs to launch the sheet for one
/// recharge attempt (MA-125 FR-6).
class RazorpayOptions {
  const RazorpayOptions({
    required this.razorpayKeyId,
    required this.razorpayOrderId,
    required this.amountPaise,
    required this.method,
    this.contact,
    this.email,
  });

  final String razorpayKeyId;
  final String razorpayOrderId;
  final int amountPaise;
  final PaymentMethod method;
  final String? contact;
  final String? email;
}

/// Razorpay's three outcomes, normalised away from the SDK's own
/// callback-based shape into one awaitable result.
sealed class RazorpayResult {
  const RazorpayResult();
}

class RazorpaySuccess extends RazorpayResult {
  const RazorpaySuccess({
    required this.razorpayPaymentId,
    required this.razorpayOrderId,
    required this.razorpaySignature,
  });

  final String razorpayPaymentId;
  final String razorpayOrderId;
  final String razorpaySignature;
}

class RazorpayFailure extends RazorpayResult {
  const RazorpayFailure({required this.code, required this.description});

  final String code;
  final String description;
}

class RazorpayDismissed extends RazorpayResult {
  const RazorpayDismissed();
}

/// Wraps `package:razorpay_flutter` behind an interface so bloc/widget
/// tests never touch the real SDK (which needs native platform channels
/// unavailable in a test harness) — see `FakeRazorpayCheckout`.
abstract class RazorpayCheckout {
  Future<RazorpayResult> open(RazorpayOptions options);

  /// Releases the underlying SDK instance's listeners. Call once per
  /// [RazorpayCheckout] when the owning widget is disposed.
  void dispose();
}

/// Thrown by [RealRazorpayCheckout.open] when [RazorpayOptions.razorpayKeyId]
/// is empty — prevents a confusing native SDK error surfacing instead
/// (MA-125 §9).
class RazorpayNotConfiguredError extends StateError {
  RazorpayNotConfiguredError() : super('Payments aren\'t configured in this build');
}

class RealRazorpayCheckout implements RazorpayCheckout {
  RealRazorpayCheckout() : _razorpay = Razorpay();

  final Razorpay _razorpay;

  @override
  Future<RazorpayResult> open(RazorpayOptions options) {
    if (options.razorpayKeyId.isEmpty) {
      throw RazorpayNotConfiguredError();
    }
    final completer = Completer<RazorpayResult>();

    void onSuccess(PaymentSuccessResponse response) {
      if (completer.isCompleted) return;
      completer.complete(
        RazorpaySuccess(
          razorpayPaymentId: response.paymentId ?? '',
          razorpayOrderId: response.orderId ?? options.razorpayOrderId,
          razorpaySignature: response.signature ?? '',
        ),
      );
    }

    void onError(PaymentFailureResponse response) {
      if (completer.isCompleted) return;
      // The SDK reports a user-dismissed sheet as an "error" with this
      // specific code, not a distinct event — MA-125 FR-6 treats it as a
      // benign cancel, same as EVENT_EXTERNAL_WALLET below, not a failure.
      if (response.code == Razorpay.PAYMENT_CANCELLED) {
        completer.complete(const RazorpayDismissed());
        return;
      }
      completer.complete(
        RazorpayFailure(
          code: response.code?.toString() ?? 'UNKNOWN_ERROR',
          description: response.message ?? 'Payment could not be completed',
        ),
      );
    }

    void onExternalWallet(ExternalWalletResponse response) {
      if (completer.isCompleted) return;
      completer.complete(const RazorpayDismissed());
    }

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);

    _razorpay.open({
      'key': options.razorpayKeyId,
      'amount': options.amountPaise,
      'currency': 'INR',
      'name': 'Milkful',
      'description': 'Wallet top-up',
      'order_id': options.razorpayOrderId,
      'prefill': {
        if (options.contact != null) 'contact': options.contact,
        if (options.email != null) 'email': options.email,
      },
      'method': {
        options.method == PaymentMethod.upi ? 'upi' : 'card': true,
      },
    });

    return completer.future;
  }

  @override
  void dispose() {
    _razorpay.clear();
  }
}
