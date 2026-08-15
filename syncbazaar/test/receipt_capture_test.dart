import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/receipt.dart';
import 'package:syncbazaar/services/receipt_saver.dart';
import 'package:syncbazaar/services/receipt_service.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/receipt_document.dart';

/// End-to-end over the real capture pipeline, stopping just short of the disk.
///
/// The widget test in `receipt_document_test.dart` pins the *layout*; this pins
/// the **exported PNG**, which is the thing the feature actually promises. They
/// are not the same check: the capture runs the document through a detached
/// render tree at a chosen pixel ratio, and a receipt that lays out correctly
/// can still export cropped — which is exactly the reported Impeller failure
/// mode this guards against.
void main() {
  /// PNG stores width and height as big-endian uint32s in the IHDR chunk, at a
  /// fixed offset: 8-byte signature, 4-byte length, 4-byte "IHDR", then the
  /// two dimensions.
  ({int width, int height}) pngSize(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    expect(bytes.sublist(1, 4), [
      0x50,
      0x4E,
      0x47,
    ], reason: 'expected a PNG signature');
    return (width: data.getUint32(16), height: data.getUint32(20));
  }

  ReceiptData receiptWith(int lineCount) => ReceiptData(
    storeName: 'SV KICKz',
    venueName: 'SM City Lucena',
    venueAddress: 'Lucena City, Quezon',
    venueContact: '0917-200-3000',
    eventName: 'Summer Fair 2026',
    receiptNo: 'SB-260810-144233',
    cashierName: 'Lalaine',
    customerName: 'Walk-in',
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
    paymentDetails: const [
      ReceiptDetail(label: 'Cash', value: 'PHP 20,000.00'),
      ReceiptDetail(label: 'Change', value: 'PHP 6,000.00', emphasize: true),
    ],
  );

  /// Captures without touching the filesystem or a platform channel.
  ///
  /// Runs inside [WidgetTester.runAsync] because the capture does real
  /// asynchronous work — `Future.delayed` between paint retries, and
  /// `toImage`'s GPU round trip — which the fake clock a widget test normally
  /// installs would stall forever.
  Future<Uint8List> capture(WidgetTester tester, ReceiptData data) async {
    Uint8List? captured;
    final service = ReceiptService(
      saver: _CapturingSaver((bytes) => captured = bytes),
    );

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.runAsync(() => service.printReceipt(data, context: context));

    expect(captured, isNotNull, reason: 'the capture never reached the saver');
    return captured!;
  }

  testWidgets('exports a PNG at the pinned document width', (tester) async {
    final size = pngSize(await capture(tester, receiptWith(3)));
    expect(size.width, 380 * 3, reason: '380pt at the preferred 3x ratio');
  });

  testWidgets('exported PNG grows with the number of items', (tester) async {
    // Compared in logical units, not raw pixels: the service lowers the pixel
    // ratio as a receipt gets longer, so a 20-item PNG can be *narrower* than
    // a 2-item one while representing far more paper.
    double logicalHeight(({int width, int height}) size) =>
        size.height / (size.width / ReceiptDocument.width);

    final small = logicalHeight(pngSize(await capture(tester, receiptWith(2))));
    final large = logicalHeight(
      pngSize(await capture(tester, receiptWith(20))),
    );

    expect(
      large,
      greaterThan(small * 2),
      reason: '18 extra line items should more than double a short receipt',
    );
  });

  testWidgets('drops the pixel ratio rather than truncating a long receipt', (
    tester,
  ) async {
    // At 3x a 60-item receipt would be ~10,800px tall, well past the 4096px
    // texture ceiling that makes Impeller return a cropped capture. The
    // service must scale the ratio down instead.
    final size = pngSize(await capture(tester, receiptWith(60)));

    expect(size.height, lessThanOrEqualTo(4096));
    expect(size.width, lessThan(380 * 3));
  });

  testWidgets('height estimate never falls below the real layout', (
    tester,
  ) async {
    // The estimate picks the pixel ratio, so an under-estimate picks a ratio
    // too high and reintroduces the truncation it exists to prevent. Checked
    // across the range because the failure is silent — a receipt that is
    // merely a bit too tall still exports, just cropped.
    for (final lineCount in [0, 1, 2, 10, 20, 60]) {
      final data = receiptWith(lineCount);
      final ratio = _pixelRatioUsed(pngSize(await capture(tester, data)).width);
      final realHeight = pngSize(await capture(tester, data)).height / ratio;

      expect(
        ReceiptDocument.estimateHeight(data),
        greaterThanOrEqualTo(realHeight),
        reason: 'estimate must not undershoot at $lineCount lines',
      );
    }
  });
}

/// Recovers the ratio the service chose from the exported width.
double _pixelRatioUsed(int exportedWidth) =>
    exportedWidth / ReceiptDocument.width;

/// Stands in for the real saver so the capture can be inspected without
/// writing to disk or hitting a platform channel that does not exist in tests.
class _CapturingSaver extends ReceiptSaver {
  const _CapturingSaver(this.onBytes);

  final void Function(Uint8List bytes) onBytes;

  @override
  Future<String> save(Uint8List bytes, String fileName) async {
    onBytes(bytes);
    return 'captured';
  }
}
