import 'dart:convert';

import '../../models/approval_request.dart';

/// Translates approval requests between the API and [ApprovalRequest].
///
/// Two things need care here. The server stores `details_json` as a real JSON
/// column, so it arrives decoded while the client holds it as a string — the
/// proposal is opaque to everything except the code that wrote it, and keeping
/// it as text means neither side has to agree on its shape. And the status and
/// type are two-letter codes rather than words, so a mistranslation would show
/// a denied request as pending.
class ApprovalApiMapper {
  const ApprovalApiMapper._();

  static ApprovalRequest fromJson(Map<String, dynamic> json) {
    return ApprovalRequest(
      id: (json['id'] as num).toInt(),
      type: _typeFrom(json['request_type'] as String?),
      eventId: (json['event'] as num?)?.toInt() ?? 0,
      requesterId: (json['requester'] as num?)?.toInt() ?? 0,
      status: _statusFrom(json['status'] as String?),
      detailsJson: _detailsToString(json['details_json']),
      // Read back from the server, so by definition it is on the server.
      synced: true,
    );
  }

  /// The body for creating a request.
  ///
  /// `event` and `requester` are omitted deliberately: the serializer marks
  /// both read-only and the view fills them from the URL and the signed-in
  /// user, so sending them is at best ignored and at worst a 400.
  static Map<String, dynamic> createBody({
    required ApprovalType type,
    required String detailsJson,
  }) => {
    'request_type': _typeCode(type),
    'status': _statusCode(ApprovalStatus.pending),
    'details_json': _detailsToJson(detailsJson),
  };

  /// The body for deciding a request. Only the status changes.
  static Map<String, dynamic> decisionBody(ApprovalStatus status) => {
    'status': _statusCode(status),
  };

  /// The client holds the proposal as text; the column is real JSON.
  ///
  /// Re-encoded rather than passed through so the value round-trips: a request
  /// read back and shown in the approvals list has to carry the same string
  /// the pre-bazaar form wrote, or the fields parsed out of it come back null.
  static String _detailsToString(Object? raw) {
    if (raw == null) {
      return '{}';
    }
    if (raw is String) {
      return raw;
    }
    return jsonEncode(raw);
  }

  /// Sent as an object where it parses as one, so the column holds structured
  /// JSON rather than a string containing JSON — the difference between
  /// `{"eventName": "x"}` and `"{\"eventName\": \"x\"}"` in the database.
  static Object _detailsToJson(String details) {
    try {
      return jsonDecode(details) as Object;
    } on FormatException {
      // Not JSON at all. Wrapped rather than dropped: whatever it is, losing
      // it silently is worse than storing it under a key.
      return {'raw': details};
    }
  }

  static ApprovalType _typeFrom(String? code) => switch (code) {
    'ST' => ApprovalType.stock,
    'SA' => ApprovalType.soa,
    // The server's own default is SA, so an unknown code reads as that
    // rather than throwing a whole approvals screen away.
    _ => ApprovalType.soa,
  };

  static String _typeCode(ApprovalType type) => switch (type) {
    ApprovalType.stock => 'ST',
    ApprovalType.soa => 'SA',
  };

  static ApprovalStatus _statusFrom(String? code) => switch (code) {
    'AP' => ApprovalStatus.approved,
    'DN' => ApprovalStatus.rejected,
    'PD' => ApprovalStatus.pending,
    // Anything unrecognised is treated as still needing a decision, which is
    // the reading that puts it in front of a human rather than hiding it.
    _ => ApprovalStatus.pending,
  };

  static String _statusCode(ApprovalStatus status) => switch (status) {
    ApprovalStatus.approved => 'AP',
    ApprovalStatus.rejected => 'DN',
    ApprovalStatus.pending => 'PD',
  };
}
