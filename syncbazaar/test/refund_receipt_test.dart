import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbazaar/bloc/orders/orders_cubit.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/company.dart';
import 'package:syncbazaar/models/receipt.dart';
import 'package:syncbazaar/models/refund.dart';
import 'package:syncbazaar/services/receipt_saver.dart';
import 'package:syncbazaar/services/receipt_service.dart';
import 'package:syncbazaar/services/refund_receipt_builder.dart';
import 'package:syncbazaar/ui/screens/orders/widgets/refund_receipt_dialog.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/receipt_document.dart';

import 'support/load_app_fonts.dart';

/// The receipt handed over when money goes back: what is on it, that it exports
/// whole, and the offer to save it.
void main() {
  setUpAll(loadAppFonts);

  Refund refund({
    String reference = '',
    String reason = 'Wrong size',
    String method = 'GCASH',
  }) => Refund(
    id: 12,
    saleId: 2302,
    eventId: 5,
    amount: 1900,
    methodId: 2,
    methodName: method,
    reason: reason,
    reference: reference,
    issuedById: 3,
    issuedByName: 'Missy',
    authorizedById: 1,
    authorizedByName: 'Lalaine',
    customerName: 'Aaron Domingo',
    createdAt: DateTime(2026, 10, 13, 1, 55, 30),
  );

  TransactionRecord sale({
    String label = 'Adidas Samba OG (Color Black, Size 42)',
  }) => TransactionRecord(
    orderId: 1,
    serverSaleId: 2302,
    customerName: 'Aaron Domingo',
    timestamp: DateTime(2026, 10, 12, 14, 32),
    productLabel: label,
    unitPrice: 1900,
    quantity: 1,
    total: 1900,
    eventId: 5,
    paymentMethod: 'GCASH',
    userId: 3,
  );

  BazaarEvent event() => BazaarEvent(
    id: 5,
    name: 'Summer Fair 2026',
    companyId: 1,
    startDate: DateTime(2026, 10, 1),
    endDate: DateTime(2026, 10, 30),
    status: BazaarStatus.ongoing,
  );

  const venue = Company(
    id: 1,
    name: 'SM City Lucena',
    address: 'Lucena City, Quezon',
    contact: '0917-200-3000',
    incentivePercent: 10,
    bufferPercent: 10,
  );

  RefundReceiptData data({
    String reference = '',
    String reason = 'Wrong size',
    String label = 'Adidas Samba OG (Color Black, Size 42)',
  }) => buildRefundReceipt(
    refund: refund(reference: reference, reason: reason),
    sale: sale(label: label),
    event: event(),
    storeName: 'SV KICKz',
    venue: venue,
  );

  group('what goes on it', () {
    test('names the store, the venue and the bazaar like a sale receipt', () {
      final d = data();

      expect(d.storeName, 'SV KICKz');
      expect(d.venueName, 'SM City Lucena');
      expect(d.venueAddress, 'Lucena City, Quezon');
      expect(d.venueContact, '0917-200-3000');
      expect(d.eventName, 'Summer Fair 2026');
    });

    test('has its own number, which cannot be mistaken for a sale\'s', () {
      expect(
        refundReceiptNo(DateTime(2026, 10, 13, 1, 55, 30)),
        'RF-261013-015530',
      );
      expect(data().receiptNo, 'RF-261013-015530');
      expect(data().fileName, 'refund-RF-261013-015530');
    });

    test('says who tapped it and whose password approved it', () {
      final d = data();

      expect(d.cashierName, 'Missy');
      expect(d.approvedByName, 'Lalaine');
    });

    test('carries the sale being undone and the money going back', () {
      final d = data(reference: 'GC-77');

      expect(d.itemName, 'Adidas Samba OG');
      expect(d.itemVariantLabel, 'Color Black, Size 42');
      expect(d.qty, 1);
      expect(d.unitPrice, 1900);
      expect(d.soldAt, DateTime(2026, 10, 12, 14, 32));
      expect(d.soldPaymentMethod, 'GCASH');
      expect(d.refundAmount, 1900);
      expect(d.refundMethod, 'GCASH');
      expect(d.reference, 'GC-77');
      expect(d.reason, 'Wrong size');
      expect(d.refundedAt, DateTime(2026, 10, 13, 1, 55, 30));
    });

    test('a product with no variant has none to print', () {
      expect(data(label: 'Tote Bag').itemName, 'Tote Bag');
      expect(data(label: 'Tote Bag').itemVariantLabel, isEmpty);
    });

    test('a missing venue costs the heading, not the receipt', () {
      final d = buildRefundReceipt(
        refund: refund(),
        sale: sale(),
        event: event(),
        storeName: 'SV KICKz',
      );

      expect(d.venueName, isEmpty);
      expect(d.itemName, 'Adidas Samba OG');
    });

    test('falls back to the sale where the refund leaves a gap', () {
      final blankCustomer = Refund(
        id: 1,
        saleId: 1,
        eventId: 5,
        amount: 1900,
        methodId: 1,
        methodName: '',
        reason: 'x',
        reference: '',
        issuedById: 1,
        issuedByName: 'Missy',
        authorizedById: 1,
        authorizedByName: 'Lalaine',
        customerName: '',
        createdAt: DateTime(2026, 10, 13),
      );

      final d = buildRefundReceipt(
        refund: blankCustomer,
        sale: sale(),
        event: event(),
        storeName: 'S',
      );

      expect(d.customerName, 'Aaron Domingo');
      expect(d.refundMethod, 'GCASH', reason: 'the method it came in by');
    });
  });

  group('the document', () {
    Future<void> show(WidgetTester tester, RefundReceiptData d) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: RefundReceiptDocument(data: d)),
          ),
        ),
      );
    }

    testWidgets('is titled REFUND and prints the money going out', (
      tester,
    ) async {
      await show(tester, data());

      expect(find.text('REFUND'), findsNWidgets(2), reason: 'title and total');
      expect(find.text('-PHP 1,900.00'), findsOneWidget);
      expect(find.text('Refunded via'), findsOneWidget);
      expect(
        find.text('GCASH'),
        findsNWidgets(2),
        reason: 'paid with, refunded via',
      );
    });

    testWidgets(
      'shows customer, item, sale time and method, reason and approver',
      (tester) async {
        await show(tester, data());

        expect(find.text('Aaron Domingo'), findsOneWidget);
        expect(find.text('Adidas Samba OG'), findsOneWidget);
        expect(find.text('Color Black, Size 42'), findsOneWidget);
        expect(find.text('2026-10-12 2:32 PM'), findsOneWidget);
        expect(find.text('Wrong size'), findsOneWidget);
        expect(find.text('Approved by'), findsOneWidget);
        expect(find.text('Lalaine'), findsOneWidget);
        expect(find.text('Missy'), findsOneWidget);
        expect(find.text('2026-10-13 1:55 AM'), findsOneWidget);
      },
    );

    testWidgets('prints the reference only when there is one', (tester) async {
      await show(tester, data());
      expect(find.text('Reference'), findsNothing);

      await show(tester, data(reference: 'GC-77'));
      expect(find.text('Reference'), findsOneWidget);
      expect(find.text('GC-77'), findsOneWidget);
    });

    testWidgets('says the item went back to stock', (tester) async {
      await show(tester, data());

      expect(
        find.text("The item was returned to this bazaar's stock."),
        findsOneWidget,
      );
    });

    testWidgets('keeps the thermal-roll width', (tester) async {
      await show(tester, data());

      expect(
        tester.getSize(find.byType(RefundReceiptDocument)).width,
        ReceiptDocument.width,
      );
    });

    testWidgets('the height estimate never falls below the real layout', (
      tester,
    ) async {
      // The estimate picks the capture's pixel ratio, so an under-estimate
      // picks one too high and the bottom of the receipt is lost.
      for (final d in [
        data(label: 'Tote Bag'),
        data(),
        data(reference: 'GC-77'),
        data(
          reference: 'GC-77',
          reason:
              'Other: The zipper broke the very first time and the customer is upset',
        ),
      ]) {
        await show(tester, d);
        final actual = tester
            .getSize(find.byType(RefundReceiptDocument))
            .height;
        expect(
          RefundReceiptDocument.estimateHeight(d),
          greaterThanOrEqualTo(actual),
          reason: '${d.itemVariantLabel} / ${d.reference} / ${d.reason}',
        );
        expect(
          RefundReceiptDocument.estimateHeight(d),
          lessThan(actual * 1.3),
          reason: 'and not so tall that the receipt is exported soft',
        );
      }
    });
  });

  group('exporting', () {
    testWidgets(
      'renders a whole PNG at the roll width and saves it under its own name',
      (tester) async {
        Uint8List? bytes;
        String? name;
        final service = ReceiptService(
          saver: _Saver((b, n) {
            bytes = b;
            name = n;
          }),
        );
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        await tester.runAsync(
          () => service.printRefundReceipt(
            data(reference: 'GC-77'),
            context: context,
          ),
        );

        expect(name, 'refund-RF-261013-015530');
        final png = ByteData.sublistView(bytes!);
        expect(bytes!.sublist(1, 4), [0x50, 0x4E, 0x47]);
        final width = png.getUint32(16);
        final height = png.getUint32(20);
        expect(width, 380 * 3);
        // Whole, not cropped: at least as tall as the real layout (588 at 3x
        // within a hair), which a truncated capture would not be.
        expect(height, greaterThan(588 * 3 - 30));
      },
    );
  });

  group('the offer', () {
    Future<void> open(WidgetTester tester, ReceiptService service) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showRefundReceiptDialog(
                  context: context,
                  data: data(reference: 'GC-77'),
                  service: service,
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

    testWidgets(
      'confirms the refund, names the approver and shows the receipt',
      (tester) async {
        await open(tester, ReceiptService(saver: _Saver((_, __) {})));

        expect(find.text('Refund issued'), findsOneWidget);
        expect(find.text('Approved by Lalaine'), findsOneWidget);
        expect(find.byType(RefundReceiptDocument), findsOneWidget);
      },
    );

    testWidgets('offers to save rather than saving by itself', (tester) async {
      var saves = 0;
      await open(tester, ReceiptService(saver: _Saver((_, __) => saves++)));

      expect(saves, 0);
      expect(
        find.widgetWithText(ElevatedButton, 'Save receipt'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
    });

    testWidgets('Close leaves without saving', (tester) async {
      var saves = 0;
      await open(tester, ReceiptService(saver: _Saver((_, __) => saves++)));

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Refund issued'), findsNothing);
      expect(saves, 0);
    });

    testWidgets('saving reports where it went, then offers Done', (
      tester,
    ) async {
      await open(
        tester,
        ReceiptService(saver: _Saver((_, __) {}, where: 'Saved to Photos')),
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('Save receipt'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await tester.pump();
      });
      await tester.pumpAndSettle();

      expect(find.text('Saved to Photos'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Done'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
    });

    testWidgets('cannot be closed while it is saving', (tester) async {
      await open(tester, ReceiptService(saver: _SlowSaver()));

      await tester.runAsync(() async {
        await tester.tap(find.text('Save receipt'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await tester.pump();
      });

      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a failed save says so and offers another try', (tester) async {
      await open(tester, ReceiptService(saver: _ThrowingSaver()));

      await tester.runAsync(() async {
        await tester.tap(find.text('Save receipt'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await tester.pump();
      });
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't save the receipt"), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Close'),
        findsOneWidget,
        reason: 'the refund is done; the dialog can always be left',
      );
    });

    testWidgets('fits a 1280x800 tablet with the buttons in view', (
      tester,
    ) async {
      await open(tester, ReceiptService(saver: _Saver((_, __) {})));

      expect(tester.takeException(), isNull);
      final button = tester.getRect(
        find.widgetWithText(ElevatedButton, 'Save receipt'),
      );
      expect(button.bottom, lessThanOrEqualTo(800));
      expect(button.top, greaterThan(0));
    });
  });

  group('the reference on the refund', () {
    RefundRepository repo(Map<String, dynamic> reply) {
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((r) async {
          if (r.method == 'POST') {
            return http.Response(
              '{"id": 1, "sale": 2302, "amount": "1900.00", "method": 2, '
              '"method_name": "GCash", "reason": "Wrong size", '
              '"issued_by": 3, "issued_by_name": "Missy", '
              '"authorized_by": 1, "authorized_by_name": "Lalaine", '
              '"customer_name": "Aaron", "created_at": "2026-10-13T01:55:30Z"'
              '${reply['reference'] != null ? ', "reference": "${reply['reference']}"' : ''}}',
              201,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      return RefundRepository(
        auth: AuthRepository(apiClient: client)..vendorId = 1,
      );
    }

    Future<Refund> issue(RefundRepository r, {String? reference}) =>
        r.approveRefund(
          eventId: 5,
          saleId: 2302,
          amount: 1900,
          methodId: 2,
          reason: 'Wrong size',
          reference: reference,
          clientUuid: 'u',
          password: 'p',
        );

    test(
      'the one typed is put back when the server does not send it',
      () async {
        final refund = await issue(repo({}), reference: ' GC-77 ');

        expect(refund.reference, 'GC-77');
      },
    );

    test('a reference the server sends wins', () async {
      final refund = await issue(
        repo({'reference': 'SERVER-1'}),
        reference: 'GC-77',
      );

      expect(refund.reference, 'SERVER-1');
    });

    test('a cash refund has none', () async {
      expect((await issue(repo({}))).reference, isEmpty);
    });
  });
}

class _Saver extends ReceiptSaver {
  const _Saver(this.onSave, {this.where = 'Saved to Photos'});

  final void Function(Uint8List bytes, String name) onSave;
  final String where;

  @override
  Future<String> save(Uint8List bytes, String fileName) async {
    onSave(bytes, fileName);
    return where;
  }
}

class _SlowSaver extends ReceiptSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) =>
      Completer<String>().future;
}

class _ThrowingSaver extends ReceiptSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) async =>
      throw StateError('disk full');
}
