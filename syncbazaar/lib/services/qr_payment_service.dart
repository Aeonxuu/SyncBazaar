import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';

/// Where a QR payment stands.
///
/// The server sends two-letter codes. Anything unrecognised is read as
/// [pending] rather than guessed at: a code this app has not heard of must
/// never be taken for payment received, and pending is the only reading that
/// leaves the cashier waiting rather than handing over goods.
enum QrPaymentStatus {
  pending,
  paid,
  expired,
  failed;

  static QrPaymentStatus fromCode(String? code) => switch (code) {
    'PA' => QrPaymentStatus.paid,
    'EX' => QrPaymentStatus.expired,
    'FL' => QrPaymentStatus.failed,
    _ => QrPaymentStatus.pending,
  };

  bool get isSettled => this != QrPaymentStatus.pending;
}

/// A QR the customer can scan, and what it takes to follow it up.
class QrPaymentIntent {
  const QrPaymentIntent({
    required this.intentId,
    required this.qrImageUrl,
    required this.status,
    this.testUrl,
  });

  final String intentId;

  /// A URL, not image bytes. Shown with `Image.network`.
  final String qrImageUrl;

  final QrPaymentStatus status;

  /// Present in test mode only. Opening it simulates payment, which is the
  /// only safe way to exercise this: PayMongo's test mode issues real QR
  /// codes, and scanning one moves real money.
  final String? testUrl;
}

/// What the server says about a payment, on one poll.
class QrPaymentUpdate {
  const QrPaymentUpdate({
    required this.status,
    this.referenceNumber,
    this.paidAt,
  });

  final QrPaymentStatus status;

  /// PayMongo's payment id, e.g. `pay_...`. Only set once paid.
  final String? referenceNumber;

  final DateTime? paidAt;
}

/// Talks to our own backend about QR payments. Never to PayMongo.
///
/// The PayMongo secret key lives on the server and only there. Anyone can
/// unpack an installed app and read what is inside it, which is the whole
/// reason this routes through our own API rather than calling the gateway.
class QrPaymentService {
  const QrPaymentService({required AuthRepository auth}) : _auth = auth;

  final AuthRepository _auth;

  static const String _createPath = '/api/bazaar/qr-intent/create/';

  /// Asks for a QR covering [amount] pesos.
  ///
  /// Sent as a decimal string rather than a number. The server reads pesos,
  /// and a bare double can serialise as `2300.5` or in scientific notation,
  /// neither of which is what a money field should receive.
  Future<QrPaymentIntent> create({required double amount}) async {
    final body =
        await _auth.api.post(
              _createPath,
              body: {'amount': amount.toStringAsFixed(2)},
            )
            as Map<String, dynamic>;

    final image = body['qr_image'] as String?;
    final intentId = body['intent_id'] as String?;
    if (image == null || image.isEmpty || intentId == null || intentId.isEmpty) {
      // Without a code there is nothing for the customer to scan, and without
      // an id there is no way to ask whether it was paid. Either one missing
      // is a failure however well-formed the rest of the response is, and it
      // has to surface as an ApiException: the dialog waits on one of those to
      // report the problem, and anything else leaves it preparing forever.
      throw const ApiException(
        ApiErrorKind.server,
        'The payment code could not be prepared. Try again.',
      );
    }

    return QrPaymentIntent(
      intentId: intentId,
      qrImageUrl: image,
      status: QrPaymentStatus.fromCode(body['status'] as String?),
      testUrl: body['test_url'] as String?,
    );
  }

  /// Asks whether it has been paid yet.
  ///
  /// Never served from the offline cache. A stale "pending" would cost a wait;
  /// a stale "paid" would complete a sale against money that never arrived.
  Future<QrPaymentUpdate> statusOf(String intentId) async {
    final body =
        await _auth.api.get(
              '/api/bazaar/qr-intent/$intentId/status/',
              useCache: false,
            )
            as Map<String, dynamic>;

    final paidAt = body['paid_at'] as String?;
    return QrPaymentUpdate(
      status: QrPaymentStatus.fromCode(body['status'] as String?),
      referenceNumber: body['reference_number'] as String?,
      paidAt: paidAt == null ? null : DateTime.tryParse(paidAt),
    );
  }
}
