import 'package:milkful_app/features/wallet/data/razorpay_checkout.dart';

/// Returns a preset [RazorpayResult] from [open] — no native SDK, no
/// platform channel, safe in bloc/widget tests.
class FakeRazorpayCheckout implements RazorpayCheckout {
  RazorpayResult result = const RazorpayDismissed();
  RazorpayOptions? lastOptions;
  bool disposed = false;

  @override
  Future<RazorpayResult> open(RazorpayOptions options) async {
    lastOptions = options;
    return result;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
