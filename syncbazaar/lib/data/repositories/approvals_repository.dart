import '../../models/approval_request.dart';

class ApprovalsRepository {
  final List<ApprovalRequest> _requests = [
    const ApprovalRequest(
      id: 1,
      type: ApprovalType.stock,
      eventId: 1,
      requesterId: 3,
      status: ApprovalStatus.pending,
      detailsJson:
          '{"event":"March Campus Bazaar","items":[{"name":"Runner Pro","qty":8}]}',
      synced: false,
    ),
  ];

  Future<List<ApprovalRequest>> listPending() async {
    return _requests.where((r) => r.status == ApprovalStatus.pending).toList();
  }

  Future<void> add(ApprovalRequest request) async => _requests.add(request);
}
