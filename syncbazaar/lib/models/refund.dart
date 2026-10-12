/// Money handed back for one sale.
///
/// Kept apart from [Sale], which is what happened at the till. A refund is a
/// second event with its own time, its own method and its own approver, and
/// folding it into the sale would erase the fact that the money came in and
/// then went out.
class Refund {
  const Refund({
    required this.id,
    required this.saleId,
    required this.eventId,
    required this.amount,
    required this.methodId,
    required this.methodName,
    required this.reason,
    required this.reference,
    required this.issuedById,
    required this.issuedByName,
    required this.authorizedById,
    required this.authorizedByName,
    required this.customerName,
    required this.createdAt,
    this.clientUuid,
  });

  final int id;

  /// The sale this undoes. The server's sale JSON carries no refund info, so
  /// this is the only join key between the two lists.
  final int saleId;

  /// Which bazaar's list it came from. Not in the server's JSON; the fetch is
  /// per bazaar, so the caller knows it.
  final int eventId;

  /// Positive, as the server stores it. Display code negates it: the sign is a
  /// presentation choice about money leaving the till, not part of the fact.
  final double amount;

  final int methodId;
  final String methodName;
  final String reason;

  /// The reference of the money sent back by GCash or bank, empty for cash and
  /// for any refund made before the server stored one.
  final String reference;

  /// The logged-in user who tapped the button.
  final int issuedById;
  final String issuedByName;

  /// Whose password approved it: the owner, or the bazaar's refund handler.
  final int authorizedById;
  final String authorizedByName;

  final String customerName;
  final DateTime createdAt;
  final String? clientUuid;
}

/// The employee who may approve refunds at one bazaar, besides the owner.
class RefundHandler {
  const RefundHandler({
    required this.authorizationId,
    required this.userId,
    required this.userName,
    required this.grantedAt,
  });

  /// The `RefundAuthorization` row, which is what revoking addresses.
  final int authorizationId;
  final int userId;
  final String userName;
  final DateTime? grantedAt;
}
