import '../../models/approval_request.dart';

class ApprovalsRepository {
  final List<ApprovalRequest> _requests = [];

  Future<List<ApprovalRequest>> listPending() async {
    return _requests.where((r) => r.status == ApprovalStatus.pending).toList();
  }

  Future<void> add(ApprovalRequest request) async => _requests.add(request);

  Future<void> removePendingRequest(int requestId) async {
    _requests.removeWhere(
      (request) =>
          request.id == requestId && request.status == ApprovalStatus.pending,
    );
  }
}
