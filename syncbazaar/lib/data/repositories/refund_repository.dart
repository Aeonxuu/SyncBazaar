import 'package:flutter/foundation.dart';

import '../../models/refund.dart';
import '../remote/api_client.dart';
import '../remote/refund_api_mapper.dart';
import 'auth_repository.dart';
import 'sales_repository.dart';

/// Issuing refunds, and choosing who besides the owner may approve them.
///
/// Online only. A refund is accepted by the server or it did not happen, and
/// nothing here is queued: money handed over the counter on the strength of a
/// request that later fails is worse than telling the cashier to wait.
///
/// Without a session this has no server to talk to, and [isRemote] says so.
/// The refund button keys off that rather than being handed a null repository,
/// matching how the other repositories behave in the demo build.
class RefundRepository {
  RefundRepository({AuthRepository? auth, SalesRepository? sales})
    : _auth = auth,
      _sales = sales;

  final AuthRepository? _auth;
  final SalesRepository? _sales;

  bool get isRemote => _auth?.vendorId != null;

  /// Whether the last read was served from the saved copy because the server
  /// could not be reached. The same signal the dashboard and the till use for
  /// their offline notice; there is no connectivity package to ask instead.
  bool get isOffline => _auth?.api.servingCacheFrom != null;

  /// The one place a refund gets approved.
  ///
  /// Today approval means the server checks [password] against the owner and
  /// the bazaar's refund handler. It is a single method on purpose: an
  /// approval that works without the server will be a second path in here,
  /// and the dialog and everything after the call should not have to change.
  ///
  /// On a 403 the server does not say whether the password was wrong or the
  /// caller lacked permission, so neither does this; the caller shows one
  /// message for both.
  ///
  /// A repeated [clientUuid] that meets "already refunded" is a retry whose
  /// first answer was lost, not a second refund. The refunds are reloaded and
  /// the one carrying this uuid is returned. If none carries it, somebody else
  /// refunded the sale first and the error stands.
  Future<Refund> approveRefund({
    required int eventId,
    required int saleId,
    required double amount,
    required int methodId,
    required String reason,
    String? reference,
    required String clientUuid,
    required String password,
  }) async {
    final auth = _requireSession();
    final path = '/api/bazaar/event/$eventId/sale/$saleId/refund/';
    final Refund refund;
    try {
      final created =
          await auth.api.post(
                path,
                body: RefundApiMapper.createBody(
                  amount: amount,
                  methodId: methodId,
                  reason: reason,
                  reference: reference,
                  clientUuid: clientUuid,
                  authorizerPassword: password,
                ),
              )
              as Map<String, dynamic>;
      final returned = RefundApiMapper.refundFromJson(
        created,
        eventId: eventId,
      );
      // The server does not store the reference yet and so does not send it
      // back. The receipt still has to print what the person typed, so it is
      // put back on the refund; a server that does return one wins.
      final typed = reference?.trim() ?? '';
      refund = returned.reference.isEmpty && typed.isNotEmpty
          ? returned.withReference(typed)
          : returned;
    } on ApiException catch (error) {
      // The address, never the body: that carries the approver's password.
      debugPrint(
        'RefundRepository: POST $path failed '
        '(${error.kind}, status ${error.statusCode}): ${error.message}',
      );
      final earlier = await _earlierAttempt(
        error,
        saleId: saleId,
        clientUuid: clientUuid,
      );
      if (earlier != null) {
        return earlier;
      }
      rethrow;
    }

    await _reloadAfterWrite();
    return refund;
  }

  Future<Refund?> _earlierAttempt(
    ApiException error, {
    required int saleId,
    required String clientUuid,
  }) async {
    final alreadyRefunded =
        error.kind == ApiErrorKind.badRequest &&
        error.message.toLowerCase().contains('already been refunded');
    if (!alreadyRefunded) {
      return null;
    }
    try {
      await _sales?.refresh();
      final refunds = await _sales?.listRefunds() ?? const <Refund>[];
      return refunds
          .where((r) => r.saleId == saleId && r.clientUuid == clientUuid)
          .firstOrNull;
    } on ApiException {
      // Could not check, so it cannot be called a success.
      return null;
    }
  }

  /// Brings the sales and refunds back after a write.
  ///
  /// The write already succeeded, so a reload that fails must not turn it into
  /// an error: the customer has their money back either way, and the next
  /// refresh catches the screen up.
  Future<void> _reloadAfterWrite() async {
    try {
      await _sales?.refresh();
    } on ApiException {
      // See above.
    }
  }

  /// Who the bazaar's refund handler is right now, or null for nobody.
  ///
  /// Owner and admin only on the server. Never read from the saved copy: a
  /// handler who was removed an hour ago must not still be shown as in place.
  Future<RefundHandler?> currentHandler(int eventId) async {
    final auth = _auth;
    if (auth == null || !isRemote) {
      return null;
    }
    final payload =
        await auth.api.get(
              '/api/bazaar/event/$eventId/refund-authorization/',
              useCache: false,
            )
            as List;
    return RefundApiMapper.activeHandlerFromPayload(payload);
  }

  /// Makes [userId] the bazaar's refund handler.
  ///
  /// One direct call. The server refuses with a 400 -- and says why -- when the
  /// person is not in the vendor, is not assigned to the bazaar, or another
  /// employee is already the handler. The last needs a revoke first; see
  /// [changeHandler].
  Future<void> grantRefundHandler(int eventId, int userId) async {
    final auth = _requireSession();
    await auth.api.post(
      '/api/bazaar/event/$eventId/refund-authorization/',
      body: RefundApiMapper.grantBody(userId),
    );
  }

  Future<void> revokeRefundHandler(int eventId, int authorizationId) async {
    final auth = _requireSession();
    await auth.api.post(
      '/api/bazaar/event/$eventId/refund-authorization/$authorizationId/revoke/',
      body: <String, dynamic>{},
    );
  }

  /// Sets the bazaar's handler to [userId], or to nobody for null.
  ///
  /// The server allows one at a time, so a change is a revoke followed by a
  /// grant. If the grant then fails, the previous handler is put back: leaving
  /// the bazaar with no handler because a pick failed would be a worse outcome
  /// than the one the person was trying to change.
  Future<void> changeHandler(int eventId, {required int? userId}) async {
    final current = await currentHandler(eventId);
    if (current?.userId == userId) {
      return;
    }
    if (current != null) {
      await revokeRefundHandler(eventId, current.authorizationId);
    }
    if (userId == null) {
      return;
    }
    try {
      await grantRefundHandler(eventId, userId);
    } on ApiException {
      if (current != null) {
        try {
          await grantRefundHandler(eventId, current.userId);
        } on ApiException {
          // Could not restore either; the original error is the one to show.
        }
      }
      rethrow;
    }
  }

  /// Takes the refund handler's authority away when they have just been taken
  /// off the bazaar. Returns whether anyone was revoked.
  ///
  /// The server does not do this itself yet: removing an employee from a
  /// bazaar leaves their authorization active, so their password would still
  /// approve refunds there. Called after the removal succeeds.
  Future<bool> revokeHandlerIfRemoved(
    int eventId,
    Set<int> removedUserIds,
  ) async {
    if (removedUserIds.isEmpty || !isRemote) {
      return false;
    }
    final current = await currentHandler(eventId);
    if (current == null || !removedUserIds.contains(current.userId)) {
      return false;
    }
    await revokeRefundHandler(eventId, current.authorizationId);
    return true;
  }

  AuthRepository _requireSession() {
    final auth = _auth;
    if (auth == null || !isRemote) {
      throw StateError('Refunds need a server to talk to.');
    }
    return auth;
  }
}
