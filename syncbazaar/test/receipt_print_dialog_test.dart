import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/receipt.dart';
import 'package:syncbazaar/services/receipt_saver.dart';
import 'package:syncbazaar/services/receipt_service.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/receipt_print_dialog.dart';

/// Drives the print dialog the way the POS does — by opening it — rather than
/// calling the service directly.
///
/// That distinction is the whole point of this file. `receipt_capture_test.dart`
/// hands `printReceipt` a context from a settled `Builder`, which is always
/// safe. The dialog starts the capture from its own `initState`, and the
/// capture reads `MediaQuery` off that context; reading an inherited widget
/// before `initState` returns is an error. It shipped, reached a real tablet,
/// and killed receipt printing outright — invisible here because nothing
/// exercised the dialog itself.
void main() {
  ReceiptData receipt() => ReceiptData(
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
    lines: const [
      ReceiptLine(
        name: 'Nike Air Force 1',
        variantLabel: 'Color Black, Size 42',
        qty: 2,
        unitPrice: 3500,
        lineTotal: 7000,
      ),
    ],
    subtotal: 7000,
    total: 7000,
  );

  /// Opens the dialog exactly as `pos_screen` does, over the real capture
  /// pipeline with only the filesystem faked out.
  Future<void> open(WidgetTester tester, ReceiptService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReceiptPrintDialog(
                context: context,
                data: receipt(),
                service: service,
              ),
              child: const Text('print'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('print'));
    // One frame builds the dialog, the next runs its post-frame callback.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('starting the print does not touch context too early', (
    tester,
  ) async {
    // The regression guard. With the capture kicked off straight from
    // initState this fails with "dependOnInheritedWidgetOfExactType<
    // MediaQuery>() ... was called before _ReceiptPrintDialogState.initState()
    // completed", which is verbatim what the tablet reported.
    await tester.runAsync(() async {
      await open(tester, ReceiptService(saver: _FakeSaver()));
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the printing state first', (tester) async {
    await tester.runAsync(() async {
      await open(tester, ReceiptService(saver: _SlowSaver()));
    });

    expect(find.text('Printing receipt…'), findsOneWidget);
    expect(find.text('Receipt printed'), findsNothing);
  });

  testWidgets('reaches the printed state and reports where it went', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await open(tester, ReceiptService(saver: _FakeSaver()));
      // The dialog holds a deliberate minimum duration so the pause reads as a
      // printer; wait past it, then settle.
      await Future<void>.delayed(const Duration(milliseconds: 3000));
      await tester.pump();
      await tester.pump();
    });

    expect(tester.takeException(), isNull);
    expect(find.text('Receipt printed'), findsOneWidget);
    expect(find.text('Saved to Photos'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Done'), findsOneWidget);
  });

  testWidgets('a save failure is reported, not swallowed', (tester) async {
    await tester.runAsync(() async {
      await open(tester, ReceiptService(saver: _ThrowingSaver()));
      await Future<void>.delayed(const Duration(milliseconds: 3000));
      await tester.pump();
      await tester.pump();
    });

    expect(find.text("Couldn't print receipt"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);
  });
}

class _FakeSaver implements ReceiptSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) async =>
      'Saved to Photos';
}

/// Never completes, pinning the dialog in its printing phase.
class _SlowSaver implements ReceiptSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) =>
      Completer<String>().future;
}

class _ThrowingSaver implements ReceiptSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) async =>
      throw StateError('no gallery permission');
}
