enum ApprovalType { stock, soa }

enum ApprovalStatus { pending, approved, rejected }

class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.type,
    required this.eventId,
    required this.requesterId,
    required this.status,
    required this.detailsJson,
    required this.synced,
  });

  final int id;
  final ApprovalType type;
  final int eventId;
  final int requesterId;
  final ApprovalStatus status;
  final String detailsJson;
  final bool synced;
}
