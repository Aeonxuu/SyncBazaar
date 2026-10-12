import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/ui/screens/pos/pos_screen.dart';
import 'package:syncbazaar/ui/screens/pre_bazaar/widgets/bazaar_details_step.dart';
import 'package:syncbazaar/ui/widgets/refund_handler_field.dart';

/// Choosing the one employee besides the owner who may approve refunds.
void main() {
  const staff = [MapEntry(10, 'Via'), MapEntry(11, 'Missy')];

  Future<void> pumpField(
    WidgetTester tester, {
    List<MapEntry<int, String>> candidates = staff,
    int? selectedId,
    ValueChanged<int?>? onChanged,
    bool busy = false,
    String? errorText,
  }) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: RefundHandlerField(
              candidates: candidates,
              selectedId: selectedId,
              onChanged: onChanged ?? (_) {},
              busy: busy,
              errorText: errorText,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.verified_user_outlined));
    await tester.pumpAndSettle();
  }

  group('the field', () {
    testWidgets('offers None and each assigned employee, and nobody else', (
      tester,
    ) async {
      await pumpField(tester);
      await openMenu(tester);

      expect(find.text('None'), findsWidgets);
      expect(find.text('Via'), findsOneWidget);
      expect(find.text('Missy'), findsOneWidget);
      expect(find.text('Lalaine'), findsNothing);
    });

    testWidgets('says "None" until someone is chosen', (tester) async {
      await pumpField(tester);

      expect(find.text('None'), findsOneWidget);
    });

    testWidgets('shows who is chosen', (tester) async {
      await pumpField(tester, selectedId: 11);

      expect(find.text('Missy'), findsOneWidget);
    });

    testWidgets('choosing someone reports their id', (tester) async {
      int? chosen = -1;
      await pumpField(tester, onChanged: (id) => chosen = id);
      await openMenu(tester);

      await tester.tap(find.text('Missy'));
      await tester.pumpAndSettle();

      expect(chosen, 11);
    });

    testWidgets('choosing None reports null, not zero', (tester) async {
      int? chosen = -1;
      await pumpField(tester, selectedId: 10, onChanged: (id) => chosen = id);
      await openMenu(tester);

      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();

      expect(chosen, isNull);
    });

    testWidgets('with nobody assigned there is nothing to pick yet', (
      tester,
    ) async {
      await pumpField(tester, candidates: const []);

      expect(find.text('Assign an employee first'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.verified_user_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Via'), findsNothing);
    });

    testWidgets('states the one-handler rule', (tester) async {
      await pumpField(tester);

      expect(find.text('Refund handler'), findsOneWidget);
      expect(
        find.text(
          'Besides the owner, this person can approve refunds at this bazaar.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows a spinner while busy and the error when it failed', (
      tester,
    ) async {
      await pumpField(tester, busy: true, errorText: 'No can do.');

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No can do.'), findsOneWidget);
    });
  });

  group('in the bazaar info dialog', () {
    BazaarEvent event() => BazaarEvent(
      id: 5,
      name: 'August Fair',
      companyId: 1,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 30),
      status: BazaarStatus.ongoing,
    );

    Future<void> open(WidgetTester tester, {RefundHandlerSetup? setup}) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => BazaarInfoDialog(
                    event: event(),
                    venue: 'SM City Lucena',
                    staff: const ['Via', 'Missy'],
                    remainingUnits: 10,
                    formatDate: (d) => '${d.month}/${d.day}',
                    refundHandler: setup,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    RefundHandlerSetup setup({
      int? currentId,
      required Future<void> Function(int?) onChange,
      String? loadError,
    }) => RefundHandlerSetup(
      candidates: staff,
      currentId: currentId,
      onChange: onChange,
      loadError: loadError,
    );

    testWidgets('an employee is not shown the choice', (tester) async {
      await open(tester);

      expect(find.byType(RefundHandlerField), findsNothing);
    });

    testWidgets('the owner sees it, set to the current handler', (
      tester,
    ) async {
      await open(tester, setup: setup(currentId: 10, onChange: (_) async {}));

      expect(find.byType(RefundHandlerField), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RefundHandlerField),
          matching: find.text('Via'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a pick is sent at once, with a spinner while it runs', (
      tester,
    ) async {
      final pending = Completer<void>();
      final sent = <int?>[];
      await open(
        tester,
        setup: setup(
          onChange: (id) {
            sent.add(id);
            return pending.future;
          },
        ),
      );

      await openMenu(tester);
      await tester.tap(find.text('Missy'));
      await tester.pump();

      expect(sent, [11]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RefundHandlerField),
          matching: find.text('Missy'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a refusal shows the reason and keeps the old handler', (
      tester,
    ) async {
      await open(
        tester,
        setup: setup(
          currentId: 10,
          onChange: (_) async => throw const ApiException(
            ApiErrorKind.badRequest,
            'An employee is already authorized for this event.',
          ),
        ),
      );

      await openMenu(tester);
      await tester.tap(find.text('Missy'));
      await tester.pumpAndSettle();

      expect(
        find.text('An employee is already authorized for this event.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(RefundHandlerField),
          matching: find.text('Via'),
        ),
        findsOneWidget,
        reason: 'the field did not move to someone the server refused',
      );
    });

    testWidgets('offline it says a connection is needed', (tester) async {
      await open(
        tester,
        setup: setup(
          onChange: (_) async => throw const ApiException(
            ApiErrorKind.network,
            'Cannot reach the server.',
          ),
        ),
      );

      await openMenu(tester);
      await tester.tap(find.text('Via'));
      await tester.pumpAndSettle();

      expect(
        find.text('Changing the refund handler needs a connection.'),
        findsOneWidget,
      );
    });

    testWidgets('when the handler cannot be read the choice is not offered', (
      tester,
    ) async {
      await open(
        tester,
        setup: setup(
          onChange: (_) async {},
          loadError: 'Needs a connection to load.',
        ),
      );

      expect(find.byType(RefundHandlerField), findsNothing);
      expect(find.text('Needs a connection to load.'), findsOneWidget);
    });
  });

  group('removing the handler from a bazaar', () {
    ({RefundRepository repo, List<http.Request> requests}) harness(
      List<Map<String, dynamic>> authorizations,
    ) {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(jsonEncode(authorizations), 200);
          }
          return http.Response('{}', 200);
        }),
      );
      return (
        repo: RefundRepository(
          auth: AuthRepository(apiClient: client)..vendorId = 1,
        ),
        requests: requests,
      );
    }

    Map<String, dynamic> row(int id, int user, {String? revokedAt}) => {
      'id': id,
      'user': user,
      'user_name': 'E$user',
      'granted_at': '2026-10-01T01:00:00Z',
      'revoked_at': revokedAt,
    };

    test('revokes the handler when they are the one removed', () async {
      final h = harness([row(2, 10)]);

      final revoked = await h.repo.revokeHandlerIfRemoved(5, {10, 12});

      expect(revoked, isTrue);
      expect(
        h.requests.last.url.path,
        '/api/bazaar/event/5/refund-authorization/2/revoke/',
      );
    });

    test('leaves the handler alone when somebody else is removed', () async {
      final h = harness([row(2, 10)]);

      final revoked = await h.repo.revokeHandlerIfRemoved(5, {12});

      expect(revoked, isFalse);
      expect(h.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    test(
      'does nothing when there is no handler, or nobody was removed',
      () async {
        final none = harness([row(2, 10, revokedAt: '2026-10-01T02:00:00Z')]);
        expect(await none.repo.revokeHandlerIfRemoved(5, {10}), isFalse);

        final nobody = harness([row(2, 10)]);
        expect(await nobody.repo.revokeHandlerIfRemoved(5, {}), isFalse);
        expect(nobody.requests, isEmpty, reason: 'no need to ask the server');
      },
    );
  });

  group('in the Preparations form', () {
    Future<void> pumpStep(
      WidgetTester tester, {
      required bool showRefundHandler,
      List<MapEntry<int, String>> assigned = staff,
      int? handlerId,
      ValueChanged<int?>? onChanged,
    }) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BazaarDetailsStep(
                eventNameController: TextEditingController(),
                locations: const [],
                selectedCompanyId: null,
                onCompanyChanged: (_) {},
                dateRange: null,
                onPickDates: () {},
                configuredPaymentMethods: const [],
                employees: const [],
                assignedEmployees: assigned,
                onAssignEmployee: (_) {},
                onRemoveAssignedEmployee: (_) {},
                showEmployeeAssignment: true,
                showRefundHandler: showRefundHandler,
                refundHandlerId: handlerId,
                onRefundHandlerChanged: onChanged ?? (_) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the owner and admin get the choice under the staff', (
      tester,
    ) async {
      await pumpStep(tester, showRefundHandler: true);

      expect(find.byType(RefundHandlerField), findsOneWidget);
    });

    testWidgets('an employee proposing a bazaar does not', (tester) async {
      await pumpStep(tester, showRefundHandler: false);

      expect(find.byType(RefundHandlerField), findsNothing);
      expect(find.text('Refund handler'), findsNothing);
    });

    testWidgets('only the people assigned can be picked', (tester) async {
      await pumpStep(
        tester,
        showRefundHandler: true,
        assigned: const [MapEntry(11, 'Missy')],
      );

      await openMenu(tester);

      expect(find.text('Missy'), findsWidgets);
      expect(find.text('Via'), findsNothing);
    });

    testWidgets('picking reports the id to the form', (tester) async {
      int? picked;
      await pumpStep(
        tester,
        showRefundHandler: true,
        onChanged: (id) => picked = id,
      );

      await openMenu(tester);
      await tester.tap(find.text('Via').last);
      await tester.pumpAndSettle();

      expect(picked, 10);
    });
  });
}
