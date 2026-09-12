import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1600, 1000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
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

  group('showing the code', () {
    // A 1x1 PNG, which is what the gateway sends inline.
    const dataUri =
        'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
        'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    testWidgets('an inline code is drawn from memory, not fetched', (
      tester,
    ) async {
      await open(tester, _FakeService(qrImage: dataUri));

      // Image.network in a test renders nothing and the till showed "the code
      // could not be loaded", which is how this was found in the first place.
      expect(find.byType(Image), findsOneWidget);
      expect(
        (tester.widget<Image>(find.byType(Image)).image),
        isA<MemoryImage>(),
      );
      expect(find.text('The code could not be loaded.'), findsNothing);
    });

    testWidgets('an addressed code is still fetched', (tester) async {
      // The other form has to keep working: it is what the field name claims,
      // and what a different gateway would send.
      await open(tester, _FakeService());

      expect(
        (tester.widget<Image>(find.byType(Image)).image),
        isA<NetworkImage>(),
      );
    });
  });

  group('the simulator link', () {
    // Scanning a test QR with a real wallet moves real money, so this link is
    // the only safe way to pay the code on screen. A dialog that mentions
    // simulating payment without offering it is worse than one that says
    // nothing.
    testWidgets('is offered while a test code is waiting', (tester) async {
      await open(tester, _FakeService());

      expect(
        find.text('Test mode. Do not scan. Tap to copy the simulator link.'),
        findsOneWidget,
      );
    });

    testWidgets('is absent in live mode, where there is nothing to copy', (
      tester,
    ) async {
      await open(tester, _FakeService(testUrl: null));

      expect(find.textContaining('Test mode'), findsNothing);
    });

    testWidgets('puts the link on the clipboard and says so', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await open(tester, _FakeService());
      await tester.tap(
        find.text('Test mode. Do not scan. Tap to copy the simulator link.'),
      );
      await tester.pump();

      expect(copied, 'https://test.example/simulate');
      // The confirmation has to be in the dialog itself. A SnackBar would sit
      // behind the modal barrier, dimmed.
      expect(
        find.text('Link copied. Paste it in a browser to simulate payment.'),
        findsOneWidget,
      );
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
      await tester.tap(find.widgetWithText(ElevatedButton, 'Payment Received'));
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
    this.qrImage = 'https://cdn.example/qr.png',
    this.testUrl = 'https://test.example/simulate',
  });

  /// Present in test mode only. Live mode sends nothing here.
  final String? testUrl;

  /// What the gateway put in the picture field. PayMongo sends a base64 data
  /// URI here despite calling it `image_url`.
  final String qrImage;

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
    return QrPaymentIntent(
      intentId: 'pi_abc',
      qrImage: qrImage,
      status: QrPaymentStatus.pending,
      testUrl: testUrl,
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
