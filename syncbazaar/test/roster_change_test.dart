import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';

/// Saving an edit to a bazaar must remove exactly the people taken off it.
///
/// During refund testing an employee (Missy) dropped off a bazaar's staff and
/// her sales stopped uploading, because the server refuses a batch from someone
/// who is not assigned. These pin down that neither the roster save nor the
/// refund-handler revoke that follows it can take off anyone but the person
/// asked for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Via 10, Missy 11, Tessa 12. Assignment row ids are deliberately unlike the
  // user ids, so deleting by the wrong number is visible.
  const roster = {10: 910, 11: 911, 12: 912};

  ({AuthRepository auth, RefundRepository refunds, List<http.Request> sent})
  harness({int? handlerUser, bool failDeleteOf = false, int failRow = -1}) {
    final sent = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        sent.add(request);
        final path = request.url.path;
        if (request.method == 'GET' &&
            path.endsWith('/refund-authorization/')) {
          return http.Response(
            jsonEncode([
              if (handlerUser != null)
                {
                  'id': 70 + handlerUser,
                  'user': handlerUser,
                  'user_name': 'E$handlerUser',
                  'granted_at': '2026-10-01T01:00:00Z',
                  'revoked_at': null,
                },
            ]),
            200,
          );
        }
        if (request.method == 'DELETE' && path.endsWith('/$failRow/')) {
          return http.Response('{"detail": "gone"}', 500);
        }
        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }
        return http.Response('{}', 201);
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    return (auth: auth, refunds: RefundRepository(auth: auth), sent: sent);
  }

  List<String> deletes(List<http.Request> sent) => [
    for (final r in sent)
      if (r.method == 'DELETE') r.url.path,
  ];

  List<dynamic> assigned(List<http.Request> sent) => [
    for (final r in sent)
      if (r.method == 'POST' && r.url.path.endsWith('/assignment/'))
        jsonDecode(r.body)['user'],
  ];

  test('removing one person deletes only their own assignment row', () async {
    final h = harness();

    final change = await h.auth.changeRoster(
      eventId: 5,
      current: roster,
      wanted: {10, 12}, // Missy taken off
    );

    expect(change.removed, {11});
    expect(deletes(h.sent), ['/api/bazaar/event/5/assignment/911/']);
  });

  test('removing the first or the last in the list removes that one', () async {
    final first = harness();
    await first.auth.changeRoster(
      eventId: 5,
      current: roster,
      wanted: {11, 12},
    );
    expect(deletes(first.sent), ['/api/bazaar/event/5/assignment/910/']);

    final last = harness();
    await last.auth.changeRoster(eventId: 5, current: roster, wanted: {10, 11});
    expect(deletes(last.sent), ['/api/bazaar/event/5/assignment/912/']);
  });

  test('saving without touching the staff sends nothing', () async {
    final h = harness();

    final change = await h.auth.changeRoster(
      eventId: 5,
      current: roster,
      wanted: {10, 11, 12},
    );

    expect(change.removed, isEmpty);
    expect(change.added, isEmpty);
    expect(h.sent, isEmpty);
  });

  test('adding a person adds only them', () async {
    final h = harness();

    final change = await h.auth.changeRoster(
      eventId: 5,
      current: roster,
      wanted: {10, 11, 12, 13},
    );

    expect(change.added, {13});
    expect(assigned(h.sent), [13]);
    expect(deletes(h.sent), isEmpty);
  });

  test('swapping one person for another touches only those two', () async {
    final h = harness();

    final change = await h.auth.changeRoster(
      eventId: 5,
      current: roster,
      wanted: {10, 12, 13}, // Missy out, someone new in
    );

    expect(change.removed, {11});
    expect(change.added, {13});
    expect(deletes(h.sent), ['/api/bazaar/event/5/assignment/911/']);
    expect(assigned(h.sent), [13]);
  });

  test('a roster that was never loaded cannot remove anyone', () async {
    // The roster read failing leaves nothing to compare against; saving then
    // must not be mistaken for "everyone was removed".
    final h = harness();

    final change = await h.auth.changeRoster(
      eventId: 5,
      current: const {},
      wanted: {10},
    );

    expect(change.removed, isEmpty);
    expect(deletes(h.sent), isEmpty);
  });

  group('with a refund handler', () {
    Future<void> save(
      ({AuthRepository auth, RefundRepository refunds, List<http.Request> sent})
      h,
      Set<int> wanted,
    ) => h.auth.changeRoster(
      eventId: 5,
      current: roster,
      wanted: wanted,
      onRemoved: (removed) async {
        await h.refunds.revokeHandlerIfRemoved(5, removed);
      },
    );

    List<String> revokes(List<http.Request> sent) => [
      for (final r in sent)
        if (r.method == 'POST' && r.url.path.endsWith('/revoke/')) r.url.path,
    ];

    test(
      'removing the handler revokes the handler and removes only them',
      () async {
        final h = harness(handlerUser: 10);

        await save(h, {11, 12});

        expect(deletes(h.sent), ['/api/bazaar/event/5/assignment/910/']);
        expect(revokes(h.sent), [
          '/api/bazaar/event/5/refund-authorization/80/revoke/',
        ]);
      },
    );

    test('removing someone else leaves the handler on and authorized', () async {
      // Missy is taken off; Via is the handler and must keep both her place and
      // her authority.
      final h = harness(handlerUser: 10);

      await save(h, {10, 12});

      expect(deletes(h.sent), ['/api/bazaar/event/5/assignment/911/']);
      expect(revokes(h.sent), isEmpty);
    });

    test('revoking never touches anyone\'s place on the roster', () async {
      final h = harness(handlerUser: 11);

      await save(h, {10, 12}); // the handler, Missy, is the one removed

      expect(deletes(h.sent), ['/api/bazaar/event/5/assignment/911/']);
      expect(
        h.sent.where((r) => r.url.path.endsWith('/revoke/')),
        hasLength(1),
      );
    });

    test(
      'a failed removal still revokes those already gone, and reports it',
      () async {
        // Via (910) is removed first; Missy's row (911) then fails.
        final h = harness(handlerUser: 10, failRow: 911);

        await expectLater(save(h, {12}), throwsA(isA<ApiException>()));

        expect(
          revokes(h.sent),
          ['/api/bazaar/event/5/refund-authorization/80/revoke/'],
          reason: 'the handler who was removed is not left authorized',
        );
      },
    );
  });
}
