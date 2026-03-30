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

  ApprovalRequest copyWith({
    int? id,
    ApprovalType? type,
    int? eventId,
    int? requesterId,
    ApprovalStatus? status,
    String? detailsJson,
    bool? synced,
  }) {
    return ApprovalRequest(
      id: id ?? this.id,
      type: type ?? this.type,
      eventId: eventId ?? this.eventId,
      requesterId: requesterId ?? this.requesterId,
      status: status ?? this.status,
      detailsJson: detailsJson ?? this.detailsJson,
      synced: synced ?? this.synced,
    );
  }
}
