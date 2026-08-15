import '../../models/approval_request.dart';
import '../remote/api_client.dart';
import '../remote/approval_api_mapper.dart';
import 'auth_repository.dart';
import 'event_repository.dart';

/// Stock requests waiting on an owner's decision.
///
/// Held on the server rather than in this list, because an approval is a
/// conversation between two people on two devices: an employee raises it on
/// the tablet at the stall and an owner answers it somewhere else. While these
/// lived in memory the owner never saw them at all, and they did not survive
/// the app closing.
///
/// The API offers approvals only per event, so listing them means asking each
/// bazaar in turn. Only unapproved ones are asked: a pending request exists to
/// decide whether its bazaar happens, so it cannot be attached to a bazaar
/// that has already been agreed.
class ApprovalsRepository {
  ApprovalsRepository({AuthRepository? auth, EventRepository? events})
    : _auth = auth,
      _events = events;

  final AuthRepository? _auth;
  final EventRepository? _events;

  /// The no-session build, where there is no server to hold these.
  final List<ApprovalRequest> _local = [];

  bool get _isRemote => _auth?.vendorId != null && _events != null;

  Future<List<ApprovalRequest>> listPending() async {
    if (!_isRemote) {
      return _local.where((r) => r.status == ApprovalStatus.pending).toList();
    }

    final auth = _auth!;
    final proposals = await _events!.proposalEventIds();
    final pending = <ApprovalRequest>[];
    for (final eventId in proposals) {
      try {
        final payload =
            await auth.api.get('/api/bazaar/event/$eventId/approval/') as List;
        pending.addAll(
          payload
              .cast<Map<String, dynamic>>()
              .map(ApprovalApiMapper.fromJson)
              .where((r) => r.status == ApprovalStatus.pending),
        );
      } on ApiException {
        // One bazaar's requests failing should not empty the whole screen.
        // The others are still worth showing, and a decision the owner cannot
        // see is a decision that does not get made.
        continue;
      }
    }
    // Oldest first: the request that has been waiting longest is the one
    // holding somebody up.
    pending.sort((a, b) => a.id.compareTo(b.id));
    return pending;
  }

  /// Raises a request against the bazaar it proposes.
  Future<ApprovalRequest> add(ApprovalRequest request) async {
    if (!_isRemote) {
      _local.add(request);
      return request;
    }

    final created =
        await _auth!.api.post(
              '/api/bazaar/event/${request.eventId}/approval/',
              body: ApprovalApiMapper.createBody(
                type: request.type,
                detailsJson: request.detailsJson,
              ),
            )
            as Map<String, dynamic>;
    return ApprovalApiMapper.fromJson(created);
  }

  /// Records the owner's answer.
  ///
  /// The request is kept rather than deleted, so a bazaar that was turned down
  /// leaves a trace of who asked and what was refused. Only its status moves,
  /// which is what takes it out of [listPending].
  Future<void> decide({
    required ApprovalRequest request,
    required ApprovalStatus status,
  }) async {
    if (!_isRemote) {
      _local.removeWhere(
        (r) => r.id == request.id && r.status == ApprovalStatus.pending,
      );
      return;
    }

    await _auth!.api.patch(
      '/api/bazaar/event/${request.eventId}/approval/${request.id}/',
      body: ApprovalApiMapper.decisionBody(status),
    );
  }
}
