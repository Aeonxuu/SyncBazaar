import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbazaar/bloc/orders/orders_cubit.dart';
import 'package:syncbazaar/core/constants/colors.dart';
import 'package:syncbazaar/core/constants/motion.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/remote/vendor_payment_method_api_mapper.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/refund.dart';
import 'package:syncbazaar/ui/screens/orders/widgets/refund_dialog.dart';
import 'package:syncbazaar/ui/widgets/app_dropdown.dart';

import 'support/load_app_fonts.dart';

/// The refund dialog: step one asks what and why, step two shows the
/// consequence and asks for the approver's password.
void main() {
  // The app's own font, so the heights and wraps measured here are the real
  // ones. The test default is a block font far wider than Inter.
  setUpAll(loadAppFonts);

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
    String customer = 'Aaron Domingo',
    bool withParts = true,
  }) => TransactionRecord(
    orderId: 1760000000123,
    serverSaleId: serverSaleId,
    customerName: customer,
    timestamp: DateTime(2026, 10, 2, 14, 32),
    productLabel: 'Adidas Samba OG (Color Cloud White/Core Black/Gum, Size 38)',
    productName: withParts ? 'Adidas Samba OG' : null,
    variantDetail: withParts ? 'Cloud White/Core Black/Gum · Size 38' : null,
    stockLabel: withParts ? 'Adidas Samba OG, Size 38' : null,
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
    String customer = 'Aaron Domingo',
    bool withParts = true,
    Size size = const Size(1280, 800),
    Future<List<ModeOfPaymentCatalogEntry>> Function()? loadMethods,
  }) async {
    tester.view.physicalSize = size;
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
                    record: record(
                      method: method,
                      serverSaleId: serverSaleId,
                      customer: customer,
                      withParts: withParts,
                    ),
                    event: event(),
                    refunds: refunds,
                    loadMethods: loadMethods ?? () async => catalog,
                    soldByName: 'Missy',
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

  Future<void> chooseReason(WidgetTester tester, String reason) async {
    await tester.tap(find.byType(AppDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(reason).last);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String text) async {
    await tester.enterText(find.widgetWithText(TextFormField, label), text);
    await tester.pump();
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

  Finder continueButton() => find.widgetWithText(ElevatedButton, 'Continue');
  Finder refundButton() =>
      find.widgetWithText(ElevatedButton, 'Refund PHP 1,900.00');

  bool isEnabled(WidgetTester tester, Finder button) =>
      tester.widget<ElevatedButton>(button).onPressed != null;

  /// Cash needs only a reason; GCash also needs its reference.
  Future<void> completeStepOne(
    WidgetTester tester, {
    bool cash = true,
    String reason = 'Wrong size',
  }) async {
    await chooseReason(tester, reason);
    if (!cash) {
      await fill(tester, 'GCash reference no.', 'GC-77');
    }
    await tester.tap(continueButton());
    await tester.pumpAndSettle();
  }

  group('step one', () {
    testWidgets('is titled "Refund sale", with no icon beside the title', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Refund sale'), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.byIcon(Icons.undo_rounded), findsNothing);
    });

    testWidgets('groups every fact about the sale in one summary', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Adidas Samba OG'), findsOneWidget);
      expect(find.text('Cloud White/Core Black/Gum · Size 38'), findsOneWidget);
      expect(find.text('PHP 1,900.00'), findsOneWidget);
      expect(find.text('Aaron Domingo'), findsOneWidget);
      expect(find.text('Oct 2, 2026 · 2:32 PM'), findsOneWidget);
      expect(find.text('Missy'), findsOneWidget);
      expect(find.text('GCash (same as payment)'), findsOneWidget);
    });

    testWidgets('names the product in bold and the variant quietly beneath', (
      tester,
    ) async {
      await open(tester);

      final name = tester.widget<Text>(find.text('Adidas Samba OG'));
      final variant = tester.widget<Text>(
        find.text('Cloud White/Core Black/Gum · Size 38'),
      );
      expect(name.style?.fontWeight, FontWeight.w700);
      expect(variant.style?.color, Colors.black54);
      expect(
        tester.getTopLeft(find.text('Cloud White/Core Black/Gum · Size 38')).dy,
        greaterThan(tester.getTopLeft(find.text('Adidas Samba OG')).dy),
      );
    });

    testWidgets('has one place for the method, not two', (tester) async {
      await open(tester);

      expect(find.text('PAID WITH'), findsNothing);
      expect(find.text('Paid with'), findsNothing);
      expect(find.text('Refund via'), findsNothing);
      expect(find.text('REFUND VIA'), findsOneWidget);
    });

    testWidgets('asks for no password and says nothing about stock yet', (
      tester,
    ) async {
      await open(tester);

      expect(find.byType(RefundApprovalField), findsNothing);
      expect(find.textContaining('goes back'), findsNothing);
    });

    testWidgets('uses a dropdown for the reason, not a row of buttons', (
      tester,
    ) async {
      await open(tester);

      expect(find.byType(AppDropdown<String>), findsOneWidget);
      expect(find.text('Select a reason'), findsOneWidget);
      expect(find.text('Wrong size'), findsNothing, reason: 'menu is closed');

      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();
      for (final reason in kRefundReasons) {
        expect(find.text(reason), findsOneWidget);
      }
    });

    testWidgets('Continue waits for a reason and the reference', (
      tester,
    ) async {
      await open(tester);
      expect(isEnabled(tester, continueButton()), isFalse);

      await chooseReason(tester, 'Wrong size');
      expect(
        isEnabled(tester, continueButton()),
        isFalse,
        reason: 'a GCash refund needs the send-back reference',
      );

      await fill(tester, 'GCash reference no.', 'GC-1');
      expect(isEnabled(tester, continueButton()), isTrue);
    });

    testWidgets('a cash sale asks for no reference', (tester) async {
      await open(tester, method: 'CASH');

      expect(find.text('Reference number'), findsNothing);
      expect(find.text('Reference of the money sent back'), findsNothing);

      await chooseReason(tester, 'Defective');
      expect(isEnabled(tester, continueButton()), isTrue);
    });

    testWidgets('a GCash sale asks for its reference, with a short helper', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('GCash reference no.'), findsOneWidget);
      expect(find.text('Reference of the money sent back'), findsOneWidget);
    });

    testWidgets('Other reveals a required field right below, in place', (
      tester,
    ) async {
      await open(tester, method: 'CASH');
      expect(find.text('Describe the reason'), findsNothing);

      await chooseReason(tester, 'Other');

      expect(find.text('Describe the reason'), findsOneWidget);
      expect(isEnabled(tester, continueButton()), isFalse);
      expect(
        tester.getTopLeft(find.text('Describe the reason')).dy,
        greaterThan(tester.getBottomLeft(find.byType(AppDropdown<String>)).dy),
      );

      await fill(tester, 'Describe the reason', 'Zipper broke');
      expect(isEnabled(tester, continueButton()), isTrue);
      expect(find.byType(Dialog), findsOneWidget, reason: 'no second dialog');
    });

    testWidgets('picking another reason takes the extra field away again', (
      tester,
    ) async {
      await open(tester, method: 'CASH');
      await chooseReason(tester, 'Other');

      await chooseReason(tester, 'Defective');

      expect(find.text('Describe the reason'), findsNothing);
      expect(isEnabled(tester, continueButton()), isTrue);
    });

    testWidgets('fits a 1280x800 tablet without scrolling, even fully open', (
      tester,
    ) async {
      // The worst case: a GCash sale (reference field) with Other chosen.
      await open(tester);
      await chooseReason(tester, 'Other');

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, 0);
      expect(tester.takeException(), isNull);
      final dialog = tester.getRect(find.byType(Dialog));
      expect(dialog.top, greaterThanOrEqualTo(0));
      expect(dialog.bottom, lessThanOrEqualTo(800));
    });

    testWidgets('Cancel leaves, and is apart from Continue', (tester) async {
      await open(tester);

      final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
      final next = tester.getRect(continueButton());
      expect(cancel.right, lessThan(next.left - 100));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
      expect(posts, isEmpty);
    });

    testWidgets('a product with no pieces is split from its label', (
      tester,
    ) async {
      await open(tester, withParts: false);

      expect(find.text('Adidas Samba OG'), findsOneWidget);
      expect(
        find.text('Color Cloud White/Core Black/Gum, Size 38'),
        findsOneWidget,
      );
    });

    testWidgets('a sale the server has not got cannot continue', (
      tester,
    ) async {
      await open(tester, method: 'CASH', serverSaleId: null);
      await chooseReason(tester, 'Defective');

      expect(isEnabled(tester, continueButton()), isFalse);
    });

    testWidgets('a method missing from the list cannot continue', (
      tester,
    ) async {
      await open(tester, method: 'MAYA');
      await chooseReason(tester, 'Defective');
      await fill(tester, 'Reference number', 'x');

      expect(isEnabled(tester, continueButton()), isFalse);
      expect(
        find.textContaining('MAYA is not in the payment-method list'),
        findsOneWidget,
      );
    });

    testWidgets('payment methods that cannot be loaded block Continue', (
      tester,
    ) async {
      await open(
        tester,
        method: 'CASH',
        loadMethods: () async =>
            throw const ApiException(ApiErrorKind.network, 'down'),
      );
      await chooseReason(tester, 'Defective');

      expect(isEnabled(tester, continueButton()), isFalse);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });
  });

  group('step two', () {
    testWidgets('names the consequence, in a sentence with an action verb', (
      tester,
    ) async {
      await open(tester, method: 'CASH', customer: 'Walk-in');
      await completeStepOne(tester);

      expect(find.text('Confirm refund'), findsOneWidget);
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(
        find.text('Refund PHP 1,900.00 in cash to Walk-in.'),
        findsOneWidget,
      );
      expect(
        find.text(
          "The Adidas Samba OG, Size 38 goes back to this bazaar's stock.",
        ),
        findsOneWidget,
      );
      expect(find.text("This can't be undone."), findsOneWidget);
    });

    testWidgets('a GCash refund says it goes back by GCash', (tester) async {
      await open(tester, customer: 'Aaron Domingo');
      await completeStepOne(tester, cash: false);

      expect(
        find.text('Refund PHP 1,900.00 via GCash to Aaron Domingo.'),
        findsOneWidget,
      );
    });

    testWidgets('asks for the password and offers no coaching about whose', (
      tester,
    ) async {
      await open(tester, method: 'CASH');
      await completeStepOne(tester);

      expect(find.text('Owner or refund handler password'), findsOneWidget);
      expect(find.textContaining('Ask the owner'), findsNothing);
    });

    testWidgets('the password field has the keyboard waiting', (tester) async {
      await open(tester, method: 'CASH');
      await completeStepOne(tester);

      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(RefundApprovalField),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('the destructive button waits for the password', (
      tester,
    ) async {
      await open(tester, method: 'CASH');
      await completeStepOne(tester);

      expect(isEnabled(tester, refundButton()), isFalse);
      final style = tester.widget<ElevatedButton>(refundButton()).style;
      expect(style?.backgroundColor?.resolve({}), AppColors.error);

      await typePassword(tester, 'secret');
      expect(isEnabled(tester, refundButton()), isTrue);
    });

    testWidgets('Back returns to step one with every choice kept', (
      tester,
    ) async {
      await open(tester);
      await chooseReason(tester, 'Other');
      await fill(tester, 'Describe the reason', 'Zipper broke');
      await fill(tester, 'GCash reference no.', 'GC-77');
      await tester.tap(continueButton());
      await tester.pumpAndSettle();
      await typePassword(tester, 'secret');

      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();

      expect(find.text('Refund sale'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget, reason: 'the reason shown');
      expect(find.text('Zipper broke'), findsOneWidget);
      expect(find.text('GC-77'), findsOneWidget);
      expect(isEnabled(tester, continueButton()), isTrue);
    });

    testWidgets('swaps content in the same dialog, with the motion tokens', (
      tester,
    ) async {
      await open(tester, method: 'CASH');
      await chooseReason(tester, 'Defective');

      await tester.tap(continueButton());
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
      final switcher = tester.widget<AnimatedSwitcher>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(AnimatedSwitcher),
        ),
      );
      expect(switcher.duration, AppMotion.entrance);
      expect(switcher.switchInCurve, AppMotion.easeOut);

      // Mid-swap both steps are on the way; neither is a second dialog.
      await tester.pump(AppMotion.entrance ~/ 2);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Confirm refund'), findsOneWidget);
    });

    testWidgets(
      'keeps the password and the button in view with the keyboard up',
      (tester) async {
        await open(tester, method: 'CASH');
        await completeStepOne(tester);

        // A tablet keyboard in landscape covers about half of 800.
        tester.view.viewInsets = const FakeViewPadding(bottom: 400);
        await tester.pumpAndSettle();

        const visible = 800 - 400;
        final viewport = tester.getRect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final field = tester.getRect(find.byType(RefundApprovalField));
        final button = tester.getRect(refundButton());
        // Inside the area the content scrolls in, not merely on screen: a field
        // half hidden behind the footer is not visible.
        expect(field.top, greaterThanOrEqualTo(viewport.top));
        expect(field.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(button.bottom, lessThanOrEqualTo(visible));
        expect(button.top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('sends the sale total, the item return and the reference', (
      tester,
    ) async {
      await open(tester);
      await completeStepOne(tester, cash: false);
      await typePassword(tester, 'secret');

      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
      expect(posts.single.url.path, '/api/bazaar/event/5/sale/2302/refund/');
      expect(body['amount'], '1900.00');
      expect(body['method'], 2, reason: "the sale's own method");
      expect(body['return_item'], isTrue);
      expect(body['reference'], 'GC-77');
      expect(body['authorizer_password'], 'secret');
      expect(body['reason'], 'Wrong size');
    });

    testWidgets('Other is sent as "Other: <text>"', (tester) async {
      await open(tester, method: 'CASH');
      await chooseReason(tester, 'Other');
      await fill(tester, 'Describe the reason', 'Zipper broke');
      await tester.tap(continueButton());
      await tester.pumpAndSettle();
      await typePassword(tester, 'secret');

      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      expect(jsonDecode(posts.single.body)['reason'], 'Other: Zipper broke');
    });

    testWidgets('while the request runs nothing can be closed or changed', (
      tester,
    ) async {
      final pending = Completer<http.Response>();
      answer = (_) => pending.future;
      await open(tester, method: 'CASH');
      await completeStepOne(tester);
      await typePassword(tester, 'secret');

      await tester.tap(refundButton());
      await tester.pump();

      expect(find.text('Refunding…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
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

    testWidgets('a refused password is cleared and explained under the field', (
      tester,
    ) async {
      answer = (_) async => http.Response(
        '{"error": "No refund authorization available for this event."}',
        403,
      );
      await open(tester, method: 'CASH');
      await completeStepOne(tester);
      await typePassword(tester, 'wrong');

      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      expect(closed, isFalse, reason: 'the dialog stays open');
      expect(find.text(kRefundPasswordRefused), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(kRefundPasswordRefused)).dy,
        greaterThan(
          tester.getBottomLeft(find.byType(RefundApprovalField)).dy - 40,
        ),
      );
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(RefundApprovalField),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, isEmpty);
      expect(isEnabled(tester, refundButton()), isFalse);
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
      await completeStepOne(tester);
      await typePassword(tester, 'wrong');
      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      await typePassword(tester, 'right');
      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      final uuids = posts
          .map((p) => (jsonDecode(p.body) as Map)['client_uuid'])
          .toSet();
      expect(posts, hasLength(2));
      expect(uuids, hasLength(1));
    });

    testWidgets("a trip back to step one and forward keeps the uuid too", (
      tester,
    ) async {
      var attempts = 0;
      answer = (request) async {
        attempts++;
        if (attempts == 1) return http.Response('{"error": "no"}', 403);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(refundJson(body['client_uuid'] as String)),
          201,
        );
      };
      await open(tester, method: 'CASH');
      await completeStepOne(tester);
      await typePassword(tester, 'wrong');
      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();
      await tester.tap(continueButton());
      await tester.pumpAndSettle();
      await typePassword(tester, 'right');
      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      expect(
        posts.map((p) => (jsonDecode(p.body) as Map)['client_uuid']).toSet(),
        hasLength(1),
      );
    });

    testWidgets("the server's own message is shown for any other failure", (
      tester,
    ) async {
      answer = (_) async => http.Response(
        '{"error": "Cannot return items on a finalized event."}',
        400,
      );
      await open(tester, method: 'CASH');
      await completeStepOne(tester);
      await typePassword(tester, 'secret');

      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      expect(
        find.text('Cannot return items on a finalized event.'),
        findsOneWidget,
      );
      expect(closed, isFalse);
      expect(find.text(kRefundPasswordRefused), findsNothing);
    });

    testWidgets('no connection says refunds need one, and queues nothing', (
      tester,
    ) async {
      answer = (_) async => throw http.ClientException('down');
      await open(tester, method: 'CASH');
      await completeStepOne(tester);
      await typePassword(tester, 'secret');

      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      expect(find.text(kRefundNeedsConnection), findsOneWidget);
      expect(closed, isFalse);
      expect(posts, hasLength(1));
    });

    testWidgets('success closes the dialog and hands back who approved it', (
      tester,
    ) async {
      await open(tester, method: 'CASH');
      await completeStepOne(tester);
      await typePassword(tester, 'secret');

      await tester.tap(refundButton());
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result?.authorizedByName, 'Lalaine');
      expect(find.text('Confirm refund'), findsNothing);
    });
  });
}
