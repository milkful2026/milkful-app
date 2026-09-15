import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/wallet/data/wallet_repository.dart';
import 'package:milkful_app/features/wallet/models/payment_method.dart';
import 'package:milkful_app/features/wallet/models/payment_view.dart';
import 'package:milkful_app/features/wallet/models/recharge_order.dart';
import 'package:milkful_app/features/wallet/models/wallet_view.dart';

class FakeCreateRechargeCall {
  FakeCreateRechargeCall({
    required this.amountPaise,
    required this.method,
    required this.idempotencyKey,
  });

  final int amountPaise;
  final PaymentMethod method;
  final String idempotencyKey;
}

class FakeWalletRepository implements WalletRepository {
  FakeWalletRepository({this.getWalletResult, this.getWalletException});

  WalletView? getWalletResult;
  Object? getWalletException;

  RechargeOrder? createRechargeResult;
  Object? createRechargeException;

  Object? confirmRechargeException;

  /// Queue of results returned by successive `getPayment` calls — lets a
  /// test script "CONFIRMING then CONFIRMED" polling sequences. If empty,
  /// falls back to [getPaymentResult].
  final List<PaymentView> getPaymentResults = [];
  PaymentView? getPaymentResult;
  Object? getPaymentException;

  Object? retryProvisionException;

  final List<FakeCreateRechargeCall> createRechargeCalls = [];
  final List<String> confirmRechargePaymentIds = [];
  int getWalletCallCount = 0;
  int getPaymentCallCount = 0;
  int retryProvisionCallCount = 0;

  @override
  Future<WalletView> getWallet() async {
    getWalletCallCount++;
    if (getWalletException != null) throw getWalletException!;
    if (getWalletResult == null) {
      throw const ApiException(errorCode: 'NOT_CONFIGURED', message: 'no getWalletResult set');
    }
    return getWalletResult!;
  }

  @override
  Future<PaymentView> getPayment(String paymentId) async {
    getPaymentCallCount++;
    if (getPaymentException != null) throw getPaymentException!;
    if (getPaymentResults.isNotEmpty) {
      return getPaymentResults.length > 1 ? getPaymentResults.removeAt(0) : getPaymentResults.first;
    }
    if (getPaymentResult == null) {
      throw const ApiException(errorCode: 'NOT_CONFIGURED', message: 'no getPaymentResult set');
    }
    return getPaymentResult!;
  }

  @override
  Future<RechargeOrder> createRecharge({
    required int amountPaise,
    required PaymentMethod method,
    required String idempotencyKey,
  }) async {
    createRechargeCalls.add(
      FakeCreateRechargeCall(amountPaise: amountPaise, method: method, idempotencyKey: idempotencyKey),
    );
    if (createRechargeException != null) throw createRechargeException!;
    return createRechargeResult ??
        RechargeOrder(
          paymentId: 'pay_fake',
          razorpayOrderId: 'order_fake',
          razorpayKeyId: 'rzp_test_fake',
          amountPaise: amountPaise,
          currency: 'INR',
        );
  }

  @override
  Future<void> confirmRecharge({
    required String paymentId,
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  }) async {
    confirmRechargePaymentIds.add(paymentId);
    if (confirmRechargeException != null) throw confirmRechargeException!;
  }

  @override
  Future<void> retryProvision() async {
    retryProvisionCallCount++;
    if (retryProvisionException != null) throw retryProvisionException!;
  }
}
