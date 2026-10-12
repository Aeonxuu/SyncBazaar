import '../../models/refund.dart';

/// Translates refunds and refund handlers between the API and the app.
class RefundApiMapper {
  const RefundApiMapper._();

  static Refund refundFromJson(
    Map<String, dynamic> json, {
    required int eventId,
  }) {
    return Refund(
      id: (json['id'] as num).toInt(),
      saleId: (json['sale'] as num).toInt(),
      eventId: eventId,
      amount: double.tryParse('${json['amount']}') ?? 0,
      methodId: (json['method'] as num?)?.toInt() ?? 0,
      methodName: (json['method_name'] as String? ?? '').toUpperCase(),
      reason: json['reason'] as String? ?? '',
      // Not stored by the server yet. Read if it is there, so the day it
      // starts coming back needs no app change.
      reference: json['reference'] as String? ?? '',
      issuedById: (json['issued_by'] as num?)?.toInt() ?? 0,
      issuedByName: json['issued_by_name'] as String? ?? '',
      authorizedById: (json['authorized_by'] as num?)?.toInt() ?? 0,
      authorizedByName: json['authorized_by_name'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      createdAt:
          DateTime.tryParse('${json['created_at']}')?.toLocal() ??
          DateTime.now(),
      clientUuid: json['client_uuid'] as String?,
    );
  }

  /// One bazaar's `GET event/<id>/refund/`.
  static List<Refund> refundsFromPayload(
    List<dynamic> payload, {
    required int eventId,
  }) => [
    for (final entry in payload)
      if (entry is Map<String, dynamic>)
        refundFromJson(entry, eventId: eventId),
  ];

  /// The body for `POST event/<id>/sale/<id>/refund/`.
  ///
  /// `return_item` is always true: a refund that leaves the item out of stock
  /// leaves the sale marked completed, so it would still count as revenue.
  /// [reference] is sent whenever there is one; the server ignores a field it
  /// does not know yet.
  static Map<String, dynamic> createBody({
    required double amount,
    required int methodId,
    required String reason,
    String? reference,
    required String clientUuid,
    required String authorizerPassword,
  }) => {
    'amount': moneyString(amount),
    'method': methodId,
    'reason': reason,
    if (reference != null && reference.trim().isNotEmpty)
      'reference': reference.trim(),
    'return_item': true,
    'authorizer_password': authorizerPassword,
    'client_uuid': clientUuid,
  };

  /// A decimal as the API's `DecimalField` wants it. Sent as text so a total
  /// like 1583.33 never travels as 1583.3299999999999.
  static String moneyString(double value) =>
      ((value * 100).round() / 100).toStringAsFixed(2);

  /// The body that asks for a refund handler. The server's own default status
  /// is pending, so none is sent.
  static Map<String, dynamic> grantRequestBody(int userId) => {
    'request_type': 'RA',
    'details_json': {'user_id': userId},
  };

  /// Every authorization row for a bazaar, revoked ones included.
  static RefundHandler? activeHandlerFromPayload(List<dynamic> payload) {
    for (final entry in payload) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      if (entry['revoked_at'] != null) {
        continue;
      }
      return RefundHandler(
        authorizationId: (entry['id'] as num).toInt(),
        userId: (entry['user'] as num).toInt(),
        userName: entry['user_name'] as String? ?? '',
        grantedAt: DateTime.tryParse('${entry['granted_at']}')?.toLocal(),
      );
    }
    return null;
  }
}
