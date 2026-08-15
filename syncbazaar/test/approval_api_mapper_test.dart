import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/approval_api_mapper.dart';
import 'package:syncbazaar/models/approval_request.dart';

/// Approvals cross the wire as two-letter codes and a real JSON column, while
/// the client holds words and a string. Both translations have a way of going
/// quietly wrong: a mistranslated status shows a denied request as still
/// awaiting a decision, and a details blob that does not round-trip loses the
/// entire proposal an owner is being asked to approve.
void main() {
  group('reading', () {
    test('reads the fields an approvals list needs', () {
      final request = ApprovalApiMapper.fromJson({
        'id': 7,
        'event': 166,
        'requester': 3,
        'request_type': 'ST',
        'status': 'PD',
        'details_json': {'eventName': 'Stardew Valley Crop Fest'},
        'request_date': '2026-08-15T10:00:00Z',
      });

      expect(request.id, 7);
      expect(request.eventId, 166);
      expect(request.requesterId, 3);
      expect(request.type, ApprovalType.stock);
      expect(request.status, ApprovalStatus.pending);
      expect(request.synced, isTrue);
    });

    test('every status code maps to its own state', () {
      ApprovalStatus statusOf(String code) => ApprovalApiMapper.fromJson({
        'id': 1,
        'status': code,
        'details_json': const <String, dynamic>{},
      }).status;

      expect(statusOf('PD'), ApprovalStatus.pending);
      expect(statusOf('AP'), ApprovalStatus.approved);
      expect(statusOf('DN'), ApprovalStatus.rejected);
    });

    test('an unknown status is left for a human rather than assumed', () {
      final request = ApprovalApiMapper.fromJson({
        'id': 1,
        'status': 'ZZ',
        'details_json': const <String, dynamic>{},
      });

      // Pending is the reading that puts it in front of somebody.
      expect(request.status, ApprovalStatus.pending);
    });

    test('the proposal survives the round trip', () {
      // This is the whole payload of a stock request: lose it and the owner
      // is approving a blank.
      const written =
          '{"eventName":"Crop Fest","companyId":2,'
          '"allocationsByAllocationKey":{"1-2-3":5}}';

      final body = ApprovalApiMapper.createBody(
        type: ApprovalType.stock,
        detailsJson: written,
      );
      // The server stores it decoded, and hands it back the same way.
      final readBack = ApprovalApiMapper.fromJson({
        'id': 1,
        'status': 'PD',
        'details_json': body['details_json'],
      });

      expect(jsonDecode(readBack.detailsJson), jsonDecode(written));
    });

    test('a missing details column reads as empty, not as a crash', () {
      final request = ApprovalApiMapper.fromJson({'id': 1, 'status': 'PD'});

      expect(jsonDecode(request.detailsJson), isEmpty);
    });
  });

  group('writing', () {
    test('sends the proposal as JSON, not as a string of JSON', () {
      final body = ApprovalApiMapper.createBody(
        type: ApprovalType.stock,
        detailsJson: '{"eventName":"Crop Fest"}',
      );

      // A string here would store {"eventName":"Crop Fest"} *as text* in a
      // JSON column, and nothing server-side could read into it.
      expect(body['details_json'], isA<Map<String, dynamic>>());
      expect((body['details_json'] as Map)['eventName'], 'Crop Fest');
    });

    test('details that are not JSON are kept rather than dropped', () {
      final body = ApprovalApiMapper.createBody(
        type: ApprovalType.stock,
        detailsJson: 'not json at all',
      );

      expect((body['details_json'] as Map)['raw'], 'not json at all');
    });

    test('a new request is created pending', () {
      final body = ApprovalApiMapper.createBody(
        type: ApprovalType.stock,
        detailsJson: '{}',
      );

      expect(body['status'], 'PD');
      expect(body['request_type'], 'ST');
    });

    test('event and requester are left to the server', () {
      // Both are read-only on the serializer and filled by the view from the
      // URL and the signed-in user. Sending them is ignored at best.
      final body = ApprovalApiMapper.createBody(
        type: ApprovalType.stock,
        detailsJson: '{}',
      );

      expect(body.containsKey('event'), isFalse);
      expect(body.containsKey('requester'), isFalse);
    });

    test('a decision sends only the new status', () {
      expect(ApprovalApiMapper.decisionBody(ApprovalStatus.approved), {
        'status': 'AP',
      });
      expect(ApprovalApiMapper.decisionBody(ApprovalStatus.rejected), {
        'status': 'DN',
      });
    });
  });
}
