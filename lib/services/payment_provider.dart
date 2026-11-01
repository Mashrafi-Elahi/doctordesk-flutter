enum PaymentChannel {
  bkash,
  nagad,
  manualMfs,
}

class PaymentSubmission {
  final String consultationId;
  final double amount;
  final PaymentChannel channel;
  final String transactionId;
  final String senderPhone;

  PaymentSubmission({
    required this.consultationId,
    required this.amount,
    required this.channel,
    required this.transactionId,
    required this.senderPhone,
  });
}

class PaymentProcessResult {
  final bool success;
  final String? transactionId;
  final String? errorMessage;
  final bool requiresManualVerification;

  PaymentProcessResult({
    required this.success,
    this.transactionId,
    this.errorMessage,
    this.requiresManualVerification = false,
  });
}

/// Clean abstract payment interface allowing seamless future migration
/// from manual MFS TrxID verification to an automated SSLCommerz, bKash PGW,
/// or PortPos payment gateway.
abstract class PaymentProvider {
  String get providerName;

  Future<PaymentProcessResult> initiatePayment(PaymentSubmission submission);

  Future<bool> verifyPayment({
    required String transactionId,
    required double expectedAmount,
  });
}

/// Manual bKash / Nagad TrxID submission provider for demo context.
class ManualMfsPaymentProvider implements PaymentProvider {
  @override
  String get providerName => 'Manual MFS (bKash/Nagad)';

  @override
  Future<PaymentProcessResult> initiatePayment(PaymentSubmission submission) async {
    final cleanTrx = submission.transactionId.trim();
    if (cleanTrx.isEmpty || cleanTrx.length < 6) {
      return PaymentProcessResult(
        success: false,
        errorMessage: 'Invalid transaction ID. Must be at least 6 alphanumeric characters.',
      );
    }

    return PaymentProcessResult(
      success: true,
      transactionId: cleanTrx,
      requiresManualVerification: true,
    );
  }

  @override
  Future<bool> verifyPayment({
    required String transactionId,
    required double expectedAmount,
  }) async {
    return transactionId.trim().length >= 6;
  }
}
