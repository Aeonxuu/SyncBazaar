import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbazaar/bloc/orders/orders_cubit.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/remote/vendor_payment_method_api_mapper.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/refund.dart';
import 'package:syncbazaar/ui/screens/orders/widgets/refund_dialog.dart';
import 'package:syncbazaar/ui/widgets/selectable_option_button.dart';

/// The refund dialog's states: what unlocks the button, what it sends, and what
/// it does with each way the server can answer.
void main() {
  const catalog = [
    ModeOfPaymentCatalogEntry(id: 1, name: 'Cash'),
    ModeOfPaymentCatalogEntry(
      id: 2,
      name: 'GCash',
      extraFieldLabel: 'GCash reference no.',
    ),
  ];

  BazaarEvent event() => BazaarEvent(
    id: 5,
    name: 'August Fair',
    companyId: 1,
    startDate: DateTime(2026, 10, 1),
    endDate: DateTime(2026, 10, 30),
    status: BazaarStatus.ongoing,
    customOtherMethods: const [
      BazaarPaymentMethod(
        name: 'GCash',
        extraFieldLabel: 'GCash reference no.',
      ),
    ],
  );

  TransactionRecord record({
    String method = 'GCASH',
    int? serverSaleId = 2302,
  }) => TransactionRecord(
    orderId: 1760000000123,
    serverSaleId: serverSaleId,
    customerName: 'Aaron Domingo',
    timestamp: DateTime(2026, 10, 2, 14, 32),
    productLabel: 'Nike Air Max SC (Color Black, Size 42)',
    unitPrice: 1900,
    quantity: 1,
    total: 1900,
    eventId: 5,
    paymentMethod: method,
    userId: 3,
  );

  Map<String, dynamic> refundJson(String clientUuid) => {
    'id': 12,
    'sale': 2302,
    'amount': '1900.00',
    'method': 2,
    'method_name': 'GCash',
    'reason': 'Wrong size',
    'issued_by': 3,
    'issued_by_name': 'Via',
    'authorized_by': 1,
    'authorized_by_name': 'Lalaine',
    'customer_name': 'Aaron Domingo',
    'created_at': '2026-10-02T06:30:00Z',
    'client_uuid': clientUuid,
  };

  late List<http.Request> posts;
  late Future<http.Response> Function(http.Request) answer;
  Refund? result;
  var closed = false;

  RefundRepository repo() {
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          posts.add(request);
          return answer(request);
        }
        return http.Response('[]', 200);
      }),
    );
    return RefundRepository(
      auth: AuthRepository(apiClient: client)..vendorId = 1,
    );
  }

  setUp(() {
    posts = [];
    result = null;
    closed = false;
    answer = (request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(refundJson(body['client_uuid'] as String)),
        201,
      );
    };
  });

  Future<void> open(
    WidgetTester tester, {
    String method = 'GCASH',
    int? serverSaleId = 2302,
    Future<List<ModeOfPaymentCatalogEntry>> Function()? loadMethods,
  }) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final refunds = repo();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showRefundDialog(
                    context: context,
                    record: record(method: method, serverSaleId: serverSaleId),
                    event: event(),
                    refunds: refunds,
                    loadMethods: loadMethods ?? () async => catalog,
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> typePassword(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(RefundApprovalField),
        matching: find.byType(TextFormField),
      ),
      text,
    );
    await tester.pump();
  }

  Future<void> pickReason(WidgetTester tester, String reason) async {
    await tester.tap(find.text(reason));
    await tester.pump();
  }

  Finder confirmButton() =>
      find.widgetWithText(ElevatedButton, 'Refund PHP 1,900.00');

  bool isEnabled(WidgetTester tester, Finder button) =>
      tester.widget<ElevatedButton>(button).onPressed != null;

  testWidgets('shows what is being refunded and what it will cost', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Aaron Domingo'), findsOneWidget);
    expect(find.text('Nike Air Max SC (Color Black, Size 42)'), findsOneWidget);
    // The summary line, and the first choice for where the money goes back.
    expect(find.text('GCASH'), findsNWidgets(2));
    expect(find.text('PHP 1,900.00'), findsOneWidget);
    expect(confirmButton(), findsOneWidget);
    expect(
      find.text("The item goes back to this bazaar's stock."),
      findsOneWidget,
    );
    expect(
      find.text(
        "Ask the owner or this bazaar's refund handler to enter their password.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('the button waits for a reason, a reference and a password', (
    tester,
  ) async {
    await open(tester);
    expect(isEnabled(tester, confirmButton()), isFalse);

    await typePassword(tester, 'secret');
    expect(isEnabled(tester, confirmButton()), isFalse, reason: 'no reason');

    await pickReason(tester, 'Wrong size');
    expect(
      isEnabled(tester, confirmButton()),
      isFalse,
      reason: 'a GCash refund needs the send-back reference',
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'GCash reference no.'),
      'GC-1',
    );
    await tester.pump();
    expect(isEnabled(tester, confirmButton()), isTrue);
  });

  testWidgets('a cash sale asks for no reference', (tester) async {
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    expect(find.text('Reference number'), findsNothing);
    expect(isEnabled(tester, confirmButton()), isTrue);
  });

  testWidgets('the money goes back the way it came, with nothing to choose', (
    tester,
  ) async {
    await open(tester);

    // Only the four reasons are choices. The method is stated, not offered:
    // there is no Cash option on a GCash sale.
    expect(
      find.byType(SelectableOptionButton),
      findsNWidgets(kRefundReasons.length),
    );
    expect(find.text('Refund via'), findsOneWidget);
    expect(find.text('GCASH'), findsNWidgets(2));
    expect(find.text('CASH'), findsNothing);
  });

  testWidgets('a sale whose method is not in the list cannot be refunded', (
    tester,
  ) async {
    await open(tester, method: 'MAYA', loadMethods: () async => catalog);
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    expect(isEnabled(tester, confirmButton()), isFalse);
    expect(
      find.textContaining('MAYA is not in the payment-method list'),
      findsOneWidget,
    );
  });

  testWidgets('the refund addresses the server sale, not the local number', (
    tester,
  ) async {
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    // The record's own id is 1760000000123, made up at the till.
    expect(posts.single.url.path, '/api/bazaar/event/5/sale/2302/refund/');
  });

  testWidgets('a sale the server has not confirmed cannot be sent', (
    tester,
  ) async {
    await open(tester, method: 'CASH', serverSaleId: null);
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    expect(isEnabled(tester, confirmButton()), isFalse);
  });

  testWidgets('Other needs words, and sends them after "Other:"', (
    tester,
  ) async {
    await open(tester, method: 'CASH');
    await typePassword(tester, 'secret');

    await pickReason(tester, 'Other');
    expect(isEnabled(tester, confirmButton()), isFalse);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'What happened?'),
      'Zipper broke',
    );
    await tester.pump();
    expect(isEnabled(tester, confirmButton()), isTrue);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(jsonDecode(posts.single.body)['reason'], 'Other: Zipper broke');
  });

  testWidgets('sends the sale total, the item return and the reference', (
    tester,
  ) async {
    await open(tester);
    await pickReason(tester, 'Wrong size');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'GCash reference no.'),
      'GC-77',
    );
    await typePassword(tester, 'secret');

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
    expect(posts.single.url.path, '/api/bazaar/event/5/sale/2302/refund/');
    expect(body['amount'], '1900.00');
    expect(body['method'], 2, reason: "the sale's own method by default");
    expect(body['return_item'], isTrue);
    expect(body['reference'], 'GC-77');
    expect(body['authorizer_password'], 'secret');
    expect(body['reason'], 'Wrong size');
  });

  testWidgets('while the request runs the dialog cannot be closed', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    answer = (_) => pending.future;
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    await tester.tap(confirmButton());
    await tester.pump();

    expect(find.text('Refunding…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    expect(
      isEnabled(tester, find.widgetWithText(ElevatedButton, 'Refunding…')),
      isFalse,
    );

    final uuid =
        (jsonDecode(posts.single.body) as Map)['client_uuid'] as String;
    pending.complete(http.Response(jsonEncode(refundJson(uuid)), 201));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('a refused password is cleared and explained in place', (
    tester,
  ) async {
    answer = (_) async => http.Response(
      '{"error": "No refund authorization available for this event."}',
      403,
    );
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'wrong');

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(closed, isFalse, reason: 'the dialog stays open');
    expect(find.text(kRefundPasswordRefused), findsOneWidget);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(RefundApprovalField),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, isEmpty);
    expect(isEnabled(tester, confirmButton()), isFalse);
  });

  testWidgets('trying again after a refusal reuses the same client uuid', (
    tester,
  ) async {
    var attempts = 0;
    answer = (request) async {
      attempts++;
      if (attempts == 1) {
        return http.Response('{"error": "no"}', 403);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(refundJson(body['client_uuid'] as String)),
        201,
      );
    };
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'wrong');
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    await typePassword(tester, 'right');
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    final uuids = posts
        .map((p) => (jsonDecode(p.body) as Map)['client_uuid'])
        .toSet();
    expect(posts, hasLength(2));
    expect(uuids, hasLength(1));
  });

  testWidgets('the server\'s own message is shown for any other failure', (
    tester,
  ) async {
    answer = (_) async => http.Response(
      '{"error": "Cannot return items on a finalized event."}',
      400,
    );
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(
      find.text('Cannot return items on a finalized event.'),
      findsOneWidget,
    );
    expect(closed, isFalse);
    expect(find.text(kRefundPasswordRefused), findsNothing);
  });

  testWidgets('no connection says refunds need one, and keeps the dialog', (
    tester,
  ) async {
    answer = (_) async => throw http.ClientException('down');
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(find.text(kRefundNeedsConnection), findsOneWidget);
    expect(closed, isFalse);
    expect(posts, hasLength(1), reason: 'nothing is queued behind its back');
  });

  testWidgets('success closes the dialog and hands back who approved it', (
    tester,
  ) async {
    await open(tester, method: 'CASH');
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result?.authorizedByName, 'Lalaine');
    expect(find.text('Refund sale'), findsNothing);
  });

  testWidgets('without the payment methods it cannot send', (tester) async {
    await open(
      tester,
      method: 'CASH',
      loadMethods: () async =>
          throw const ApiException(ApiErrorKind.network, 'down'),
    );
    await pickReason(tester, 'Defective');
    await typePassword(tester, 'secret');

    expect(isEnabled(tester, confirmButton()), isFalse);
    expect(find.textContaining('could not be loaded'), findsOneWidget);
  });

  testWidgets('fits a tablet screen, with the footer buttons always in view', (
    tester,
  ) async {
    await open(tester);
    tester.view.physicalSize = const Size(1280, 700);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no overflow stripes');
    final button = tester.getRect(confirmButton());
    expect(button.bottom, lessThanOrEqualTo(700));
    expect(button.top, greaterThan(0));
  });
}
