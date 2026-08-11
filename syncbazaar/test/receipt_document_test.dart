import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/receipt.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/receipt_document.dart';

/// The receipt is captured detached from the app, at a pinned width and an
/// unbounded height, so the properties worth pinning are dimensional: it must
/// stay exactly as wide as the capture expects, and it must get *taller* with
/// the basket — that growth is the whole feature.
void main() {
  ReceiptData receiptWith({
    int lineCount = 1,
    List<ReceiptDetail> paymentDetails = const [],
    String customerName = 'Walk-in',
  }) {
    return ReceiptData(
      storeName: 'SV KICKz',
      venueName: 'SM City Lucena',
      venueAddress: 'Lucena City, Quezon',
      venueContact: '0917-200-3000',
      eventName: 'Summer Fair 2026',
      receiptNo: 'SB-260810-144233',
      cashierName: 'Lalaine',
      customerName: customerName,
      paymentMethod: 'CASH',
      timestamp: DateTime(2026, 8, 10, 14, 42, 33),
      lines: List.generate(
        lineCount,
        (i) => ReceiptLine(
          name: 'Nike Air Force ${i + 1}',
          variantLabel: 'Color Black, Size 42',
          qty: 2,
          unitPrice: 3500,
          lineTotal: 7000,
        ),
      ),
      subtotal: 7000.0 * lineCount,
      total: 7000.0 * lineCount,
      paymentDetails: paymentDetails,
    );
  }

  /// Lays the document out under the same constraints the capture uses:
  /// width pinned, height unbounded.
  ///
  /// A vertical [SingleChildScrollView] is the harness rather than a plain
  /// box because it hands its child an infinite height budget — the same
  /// budget `captureFromLongWidget` gives it — while still letting a receipt
  /// taller than the 600px test viewport lay out without overflowing it.
  Future<Size> layout(WidgetTester tester, ReceiptData data) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          // Align, because the scroll view hands its child a *tight* viewport
          // width; without loosening it first, SizedBox's 380 is clamped back
          // up to 800 by BoxConstraints.enforce.
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: ReceiptDocument.width,
              child: ReceiptDocument(data: data),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byType(ReceiptDocument));
  }

  testWidgets('renders at exactly the width the capture pins', (tester) async {
    final size = await layout(tester, receiptWith());
    expect(size.width, ReceiptDocument.width);
  });

  testWidgets('grows taller as line items are added', (tester) async {
    final short = await layout(tester, receiptWith(lineCount: 2));
    final long = await layout(tester, receiptWith(lineCount: 12));

    expect(
      long.height,
      greaterThan(short.height),
      reason: 'a bigger basket must produce a longer receipt',
    );

    // Ten extra lines should add roughly ten line-blocks of height, not a
    // rounding error — this catches a layout that silently clips or scrolls.
    expect(long.height - short.height, greaterThan(200));
  });

  testWidgets('never lays out wider than its pinned width', (tester) async {
    // A long product name and a long customer name are the realistic ways a
    // receipt would try to push past its roll width.
    final data = ReceiptData(
      storeName: 'SV KICKz',
      venueName: 'SM City Lucena Grand Central Mall Annex Building',
      venueAddress: 'Diversion Road corner Maharlika Highway, Lucena City',
      venueContact: '0917-200-3000',
      eventName: 'Summer Fair 2026 Grand Anniversary Weekend Sale',
      receiptNo: 'SB-260810-144233',
      cashierName: 'Lalaine Jannah Dela Cruz',
      customerName: 'Maria Clara de los Santos-Buenaventura',
      paymentMethod: 'CASH',
      timestamp: DateTime(2026, 8, 10, 14, 42, 33),
      lines: const [
        ReceiptLine(
          name: 'Nike Air Force 1 Low Retro Premium Anniversary Edition',
          variantLabel: 'Color Midnight Navy Metallic, Size 42 Extra Wide',
          qty: 2,
          unitPrice: 3500,
          lineTotal: 7000,
        ),
      ],
      subtotal: 7000,
      total: 7000,
    );

    final size = await layout(tester, data);
    expect(size.width, ReceiptDocument.width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prints the payment rows its section contributed', (
    tester,
  ) async {
    await layout(
      tester,
      receiptWith(
        paymentDetails: const [
          ReceiptDetail(label: 'Cash', value: 'PHP 20,000.00'),
          ReceiptDetail(label: 'Change', value: 'PHP 13,000.00', emphasize: true),
        ],
      ),
    );

    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('PHP 20,000.00'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('PHP 13,000.00'), findsOneWidget);
  });

  testWidgets('omits the payment block entirely when a method adds none', (
    tester,
  ) async {
    await layout(tester, receiptWith());

    expect(find.text('Cash'), findsNothing);
    expect(find.text('Change'), findsNothing);
    // The fixed part of the receipt is still there.
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
  });

  testWidgets('prints money through the shared formatters', (tester) async {
    await layout(tester, receiptWith(lineCount: 2));

    // formatPeso, with thousands separators — not toStringAsFixed(2).
    expect(find.text('PHP 14,000.00'), findsNWidgets(2)); // subtotal + total
  });

  testWidgets('shows store and venue as separate identities', (tester) async {
    await layout(tester, receiptWith());

    expect(find.text('SV KICKZ'), findsOneWidget); // uppercased header
    expect(find.text('SM City Lucena'), findsOneWidget);
  });

  testWidgets('omits the customer row for an unnamed walk-in', (tester) async {
    await layout(tester, receiptWith(customerName: ''));
    expect(find.text('Customer'), findsNothing);

    await layout(tester, receiptWith(customerName: 'Ana'));
    expect(find.text('Customer'), findsOneWidget);
  });
}
