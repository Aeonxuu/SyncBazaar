import 'dart:convert';
import 'dart:typed_data';

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

/// The bytes inside a `data:image/...;base64,...` value.
///
/// Returns null for anything else, including an ordinary `https://` address,
/// which is the caller's signal to fetch it over the network instead.
///
/// Also returns null for a data URI whose payload will not decode, rather than
/// throwing: a damaged picture should leave the cashier looking at "the code
/// could not be loaded" with the manual fallback beside it, not at a crash in
/// the middle of taking payment.
Uint8List? decodeDataUriImage(String value) {
  if (!value.startsWith('data:image')) {
    return null;
  }
  final comma = value.indexOf(',');
  if (comma == -1) {
    return null;
  }
  // Only base64 payloads. A data URI can also carry percent-encoded text, and
  // decoding one of those as base64 would produce nonsense bytes.
  if (!value.substring(0, comma).contains(';base64')) {
    return null;
  }
  try {
    // Whitespace is legal inside a base64 payload and common when one has been
    // wrapped across lines, but `base64Decode` rejects it.
    return base64Decode(
      value.substring(comma + 1).replaceAll(RegExp(r'\s'), ''),
    );
  } on FormatException {
    return null;
  }
}

/// A QR the customer can scan, and what it takes to follow it up.
class QrPaymentIntent {
  const QrPaymentIntent({
    required this.intentId,
    required this.qrImage,
    required this.status,
    this.testUrl,
  });

  final String intentId;

  /// The QR picture, in whichever of the two forms the gateway sent.
  ///
  /// PayMongo calls this field `image_url` and then puts a
  /// `data:image/png;base64,...` value in it, which our backend passes through
  /// untouched. Treating it as an address is what made the till say the code
  /// could not be loaded. Both forms are handled: see [qrImageBytes].
  final String qrImage;

  /// [qrImage] decoded, when it arrived as a data URI, and null when it is a
  /// plain address to be fetched instead.
  Uint8List? get qrImageBytes => decodeDataUriImage(qrImage);

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
    if (image == null ||
        image.isEmpty ||
        intentId == null ||
        intentId.isEmpty) {
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
      qrImage: image,
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
