import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/services/qr_payment_service.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/qr_auto_payment_dialog.dart';

/// Waiting for a QR payment to arrive.
///
/// The cashier no longer types a reference, so the dialog has to be honest
/// about what it knows: it must not report payment it has not seen, and it must
/// not leave a till stuck with a customer waiting.
void main() {
  // A landscape tablet, which is what this app runs on. The default 800x600
  // test surface is shorter than the dialog, so the footer lands under the
  // barrier and its buttons cannot be tapped.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1600, 1000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  QrPaymentResult? result;

  Future<void> open(
    WidgetTester tester,
    QrPaymentService service, {
    String? extraFieldLabel = 'GCash Ref No.',
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showQrAutoPaymentDialog(
                  context: context,
                  paymentMethod: 'GCASH',
                  amount: 2300.5,
                  service: service,
                  extraFieldLabel: extraFieldLabel,
                );
              },
              child: const Text('pay'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pay'));
    // One frame builds the dialog, the next runs its post-frame callback.
    await tester.pump();
    await tester.pump();
  }

  group('waiting for payment', () {
    testWidgets('shows the amount and asks the customer to scan', (
      tester,
    ) async {
      await open(tester, _FakeService());
      await tester.pump();

      expect(find.text('Pay with GCASH'), findsOneWidget);
      expect(find.text('PHP 2,300.50'), findsOneWidget);
      expect(find.textContaining('scan this code'), findsOneWidget);
    });

    testWidgets('closes with the reference once paid', (tester) async {
      final service = _FakeService(paidAfterPolls: 1);
      await open(tester, service);
      await tester.pump();

      // One poll interval, then the hold that lets the confirmation be seen.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.reference, 'pay_123');
      expect(result!.source, ReferenceSource.automatic);
    });

    testWidgets('stops asking once it has an answer', (tester) async {
      final service = _FakeService(paidAfterPolls: 1);
      await open(tester, service);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      final asked = service.statusCalls;
      await tester.pump(const Duration(seconds: 30));

      expect(service.statusCalls, asked, reason: 'it kept polling after paid');
    });

    testWidgets('closing it stops the polling', (tester) async {
      // The one that matters. A timer left running keeps asking the server
      // about a payment nobody is waiting for, for the rest of the shift.
      final service = _FakeService();
      await open(tester, service);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      final asked = service.statusCalls;
      await tester.pump(const Duration(seconds: 30));

      expect(service.statusCalls, asked);
      expect(result, isNull, reason: 'cancelling must not take payment');
    });
  });

  group('when things go wrong', () {
    testWidgets('a lost connection keeps the code up and says so', (
      tester,
    ) async {
      final service = _FakeService(offlineAfterPolls: 1);
      await open(tester, service);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      // The customer may have paid already, so this is a note, not a failure.
      expect(find.textContaining('Reconnecting'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('an expired code offers a new one', (tester) async {
      final service = _FakeService(expiredAfterPolls: 1);
      await open(tester, service);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.textContaining('expired'), findsWidgets);
      expect(find.widgetWithText(TextButton, 'New code'), findsOneWidget);
    });

    testWidgets('a failure to prepare reports the reason', (tester) async {
      await open(tester, _FakeService(failToCreate: true));
      await tester.pump();

      expect(find.textContaining('could not'), findsWidgets);
    });
  });

  group('the manual way out', () {
    testWidgets('is offered the whole time it is waiting', (tester) async {
      await open(tester, _FakeService());
      await tester.pump();

      // Not only after a failure: if the connection stays down, this is how a
      // cashier finishes the sale rather than standing at a till.
      expect(
        find.widgetWithText(TextButton, 'Enter reference manually'),
        findsOneWidget,
      );
    });

    testWidgets('returns what was typed, marked as manual', (tester) async {
      await open(tester, _FakeService());
      await tester.pump();

      await tester.tap(
        find.widgetWithText(TextButton, 'Enter reference manually'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  9988776655  ');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Payment Received'),
      );
      await tester.pumpAndSettle();

      expect(result!.reference, '9988776655');
      expect(result!.source, ReferenceSource.manual);
    });

    testWidgets('switching to manual stops the polling', (tester) async {
      final service = _FakeService();
      await open(tester, service);
      await tester.pump();

      await tester.tap(
        find.widgetWithText(TextButton, 'Enter reference manually'),
      );
      await tester.pumpAndSettle();

      final asked = service.statusCalls;
      await tester.pump(const Duration(seconds: 30));

      expect(service.statusCalls, asked);
    });

    testWidgets('will not confirm an empty reference when one is required', (
      tester,
    ) async {
      await open(tester, _FakeService());
      await tester.pump();
      await tester.tap(
        find.widgetWithText(TextButton, 'Enter reference manually'),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Payment Received'),
      );
      expect(button.onPressed, isNull);
    });
  });
}

/// Stands in for the backend, so nothing here touches the network.
class _FakeService implements QrPaymentService {
  _FakeService({
    this.paidAfterPolls,
    this.expiredAfterPolls,
    this.offlineAfterPolls,
    this.failToCreate = false,
  });

  final int? paidAfterPolls;
  final int? expiredAfterPolls;
  final int? offlineAfterPolls;
  final bool failToCreate;

  int statusCalls = 0;

  @override
  Future<QrPaymentIntent> create({required double amount}) async {
    if (failToCreate) {
      throw const ApiException(
        ApiErrorKind.server,
        'The payment code could not be prepared. Try again.',
      );
    }
    return const QrPaymentIntent(
      intentId: 'pi_abc',
      qrImageUrl: 'https://cdn.example/qr.png',
      status: QrPaymentStatus.pending,
      testUrl: 'https://test.example/simulate',
    );
  }

  @override
  Future<QrPaymentUpdate> statusOf(String intentId) async {
    statusCalls++;
    if (offlineAfterPolls != null && statusCalls >= offlineAfterPolls!) {
      throw const ApiException(
        ApiErrorKind.network,
        'Cannot reach the server. Check your connection.',
      );
    }
    if (expiredAfterPolls != null && statusCalls >= expiredAfterPolls!) {
      return const QrPaymentUpdate(status: QrPaymentStatus.expired);
    }
    if (paidAfterPolls != null && statusCalls >= paidAfterPolls!) {
      return QrPaymentUpdate(
        status: QrPaymentStatus.paid,
        referenceNumber: 'pay_123',
        paidAt: DateTime(2026, 9, 12, 14, 2, 11),
      );
    }
    return const QrPaymentUpdate(status: QrPaymentStatus.pending);
  }
}
