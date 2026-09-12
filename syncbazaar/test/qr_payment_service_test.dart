import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/services/qr_payment_service.dart';

/// Talking to our own backend about a QR payment.
///
/// Two things here are about money rather than plumbing: the amount has to
/// leave as a decimal string in pesos, and a status this app does not recognise
/// must never be read as paid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  QrPaymentService serviceReplying(
    Object body, {
    int status = 200,
    void Function(http.Request request)? onRequest,
  }) => QrPaymentService(
    auth: AuthRepository(
      apiClient: ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          onRequest?.call(request);
          return http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    ),
  );

  const created = {
    'intent_id': 'pi_abc',
    'qr_image': 'https://cdn.example/qr.png',
    'test_url': 'https://test.example/simulate',
    'status': 'PD',
    'amount': '2300.50',
  };

  group('reading the picture', () {
    // A 1x1 PNG. Real enough to prove the bytes survive the round trip.
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
        'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    test('a data URI comes back as bytes', () {
      // What PayMongo actually sends, in a field it calls image_url.
      final bytes = decodeDataUriImage('data:image/png;base64,$pngBase64');

      expect(bytes, isNotNull);
      // The PNG magic number, so this is the real picture and not a prefix
      // that happened to decode.
      expect(bytes!.take(4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('an ordinary address is left alone', () {
      // Null is the caller's signal to fetch it over the network instead.
      expect(decodeDataUriImage('https://cdn.example/qr.png'), isNull);
    });

    test('a payload wrapped across lines still decodes', () {
      final wrapped =
          'data:image/png;base64,${pngBase64.substring(0, 20)}\n'
          '${pngBase64.substring(20)}';

      expect(decodeDataUriImage(wrapped), isNotNull);
    });

    test('a damaged payload gives up quietly rather than throwing', () {
      // Mid-sale is the worst possible moment for an uncaught exception. The
      // cashier should see the fallback message and the manual button.
      expect(
        decodeDataUriImage('data:image/png;base64,not valid base64!!'),
        isNull,
      );
    });

    test('a data URI that is not base64 is refused', () {
      // Percent-encoded text, which would decode to nonsense as base64.
      expect(decodeDataUriImage('data:image/svg+xml,%3Csvg%3E'), isNull);
    });

    test('the intent exposes the same decoding', () {
      const intent = QrPaymentIntent(
        intentId: 'pi_abc',
        qrImage: 'data:image/png;base64,$pngBase64',
        status: QrPaymentStatus.pending,
      );

      expect(intent.qrImageBytes, isNotNull);
    });
  });

  group('asking for a code', () {
    test('sends the amount as a decimal string in pesos', () async {
      Map<String, dynamic>? sent;
      final service = serviceReplying(
        created,
        onRequest: (r) => sent = jsonDecode(r.body) as Map<String, dynamic>,
      );

      await service.create(amount: 2300.5);

      // Not 2300.5, and not centavos. The server reads pesos, and a bare
      // double can serialise in ways a money field should never receive.
      expect(sent!['amount'], '2300.50');
    });

    test('a whole amount still carries two decimal places', () async {
      Map<String, dynamic>? sent;
      final service = serviceReplying(
        created,
        onRequest: (r) => sent = jsonDecode(r.body) as Map<String, dynamic>,
      );

      await service.create(amount: 2300);

      expect(sent!['amount'], '2300.00');
    });

    test('reads back the code, the id and the test link', () async {
      final intent = await serviceReplying(created).create(amount: 2300.5);

      expect(intent.intentId, 'pi_abc');
      expect(intent.qrImage, 'https://cdn.example/qr.png');
      expect(intent.testUrl, 'https://test.example/simulate');
      expect(intent.status, QrPaymentStatus.pending);
    });

    test('a response with no code is a failure, not a blank screen', () async {
      final service = serviceReplying({
        'intent_id': 'pi_abc',
        'qr_image': null,
        'status': 'PD',
      });

      expect(() => service.create(amount: 100), throwsA(isA<ApiException>()));
    });

    test('a response with no id is a failure too', () async {
      // Without an id there is no way to ask whether it was paid, so a code
      // on screen would be one nobody could ever follow up.
      final service = serviceReplying({
        'intent_id': null,
        'qr_image': 'https://cdn.example/qr.png',
        'status': 'PD',
      });

      expect(() => service.create(amount: 100), throwsA(isA<ApiException>()));
    });
  });

  group('asking whether it is paid', () {
    test('pending reads as pending', () async {
      final update = await serviceReplying({
        'intent_id': 'pi_abc',
        'status': 'PD',
        'reference_number': null,
        'paid_at': null,
      }).statusOf('pi_abc');

      expect(update.status, QrPaymentStatus.pending);
      expect(update.status.isSettled, isFalse);
      expect(update.referenceNumber, isNull);
    });

    test('paid carries the reference and the time', () async {
      final update = await serviceReplying({
        'intent_id': 'pi_abc',
        'status': 'PA',
        'reference_number': 'pay_123',
        'paid_at': '2026-09-12T14:02:11Z',
      }).statusOf('pi_abc');

      expect(update.status, QrPaymentStatus.paid);
      expect(update.referenceNumber, 'pay_123');
      expect(update.paidAt, isNotNull);
    });

    test('expired and failed are distinguished', () async {
      expect(
        (await serviceReplying({'status': 'EX'}).statusOf('pi_abc')).status,
        QrPaymentStatus.expired,
      );
      expect(
        (await serviceReplying({'status': 'FL'}).statusOf('pi_abc')).status,
        QrPaymentStatus.failed,
      );
    });

    test('an unknown code is read as pending, never as paid', () async {
      // A status this app has not heard of must leave the cashier waiting.
      // Guessing in the other direction hands over goods for nothing.
      for (final unknown in ['ZZ', '', 'paid', 'SUCCEEDED']) {
        final update = await serviceReplying({
          'status': unknown,
        }).statusOf('pi_abc');
        expect(update.status, QrPaymentStatus.pending, reason: unknown);
      }
    });

    test('a missing status is read as pending', () async {
      final update = await serviceReplying({
        'intent_id': 'pi_abc',
      }).statusOf('pi_abc');

      expect(update.status, QrPaymentStatus.pending);
    });
  });

  group('the status poll is never served from the offline cache', () {
    test('a cached answer is not replayed when the server is gone', () async {
      var online = true;
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          if (!online) {
            throw http.ClientException('offline');
          }
          return http.Response(
            jsonEncode({'status': 'PA', 'reference_number': 'pay_123'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final service = QrPaymentService(auth: AuthRepository(apiClient: client));

      await service.statusOf('pi_abc');
      online = false;

      // A stale "pending" would only cost a wait. A stale "paid" would
      // complete a sale against money that never arrived, so this must fail
      // rather than answer from what it saw a moment ago.
      await expectLater(
        service.statusOf('pi_abc'),
        throwsA(isA<ApiException>()),
      );
    });

    test('ordinary reads still use the cache', () async {
      var online = true;
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          if (!online) {
            throw http.ClientException('offline');
          }
          return http.Response(
            jsonEncode([
              {'id': 1},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.get('/api/core/establishment/');
      online = false;

      expect(await client.get('/api/core/establishment/'), hasLength(1));
    });
  });
}
