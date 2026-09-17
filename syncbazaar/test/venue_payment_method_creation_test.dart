import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/models/company.dart';

/// A payment method typed into a venue has to reach the server.
///
/// It used to not. Saving a venue kept only the method names that already
/// matched a server row and dropped the rest silently, so a cashier could add
/// "QR PH", save, see it in the list, restart the app, and find it gone. The
/// venue had come back from the server, which had never been told about it.
///
/// `ModeOfPayment` is one global table shared by every vendor, so the matching
/// also has to be forgiving: adding a second row that differs only in spacing
/// is a mess everyone sees, and the backend already carries a command to prune
/// duplicates left by exactly that.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The venue list the server returns, with whatever methods it accepts.
  String establishmentsJson(List<int> methodIds) => jsonEncode([
    {
      'id': 7,
      'name': 'MSEUF Campus',
      'address': 'Lucena City',
      'contact': '0917',
      'incentive_percent': 8,
      'buffer_percent': 10,
      'accepted_payment_methods': methodIds,
    },
  ]);

  const venue = Company(
    id: 7,
    name: 'MSEUF Campus',
    address: 'Lucena City',
    contact: '0917',
    incentivePercent: 8,
    bufferPercent: 10,
  );

  /// Records every request so a test can assert what the server was told.
  ({SettingsRepository settings, List<http.Request> requests}) harness({
    required String methodsJson,
    int createdId = 99,
    String createdName = 'QR PH',
    bool failCreate = false,
  }) {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final path = request.url.path;

      if (request.method == 'POST' && path.endsWith('/mode-of-payment/')) {
        if (failCreate) {
          return http.Response('{"detail": "nope"}', 400);
        }
        return http.Response(
          jsonEncode({
            'id': createdId,
            'name': createdName,
            'required_information_name': 'Reference Number',
          }),
          201,
        );
      }
      if (path.endsWith('/mode-of-payment/')) {
        return http.Response(methodsJson, 200);
      }
      if (path.contains('/establishment/') && request.method == 'PUT') {
        return http.Response('{}', 200);
      }
      if (path.endsWith('/establishment/')) {
        return http.Response(establishmentsJson(const [1]), 200);
      }
      return http.Response('[]', 200);
    });

    final auth = AuthRepository(apiClient: ApiClient(httpClient: client))
      ..vendorId = 4;
    return (settings: SettingsRepository(auth: auth), requests: requests);
  }

  /// What the venue PUT said the venue accepts.
  List<int> acceptedIdsIn(List<http.Request> requests) {
    final put = requests.lastWhere((r) => r.method == 'PUT');
    final body = jsonDecode(put.body) as Map<String, dynamic>;
    return (body['accepted_payment_methods'] as List).cast<int>();
  }

  test('a method the server has never heard of is created, not dropped', () async {
    final h = harness(
      methodsJson: jsonEncode([
        {'id': 1, 'name': 'Cash', 'required_information_name': null},
      ]),
    );

    await h.settings.upsertCompanyConfiguration(
      company: venue,
      paymentMethods: const [
        PaymentMethodMeta(name: 'CASH'),
        PaymentMethodMeta(name: 'QR PH', extraFieldLabel: 'Reference Number'),
      ],
    );

    final created = h.requests.where(
      (r) => r.method == 'POST' && r.url.path.endsWith('/mode-of-payment/'),
    );
    expect(created, hasLength(1), reason: 'QR PH had to be created');
    expect(jsonDecode(created.first.body)['name'], 'QR PH');
    // The label travels with it, or the reference never reaches the export.
    expect(
      jsonDecode(created.first.body)['required_information_name'],
      'Reference Number',
    );
    // And the venue is saved accepting it, which is what survives a restart.
    expect(acceptedIdsIn(h.requests), containsAll(<int>[1, 99]));
  });

  test('spacing and case do not create a second row', () async {
    // The exact trap: the server holds "QRPH", somebody types "QR PH".
    final h = harness(
      methodsJson: jsonEncode([
        {'id': 1, 'name': 'Cash', 'required_information_name': null},
        {'id': 5, 'name': 'QRPH', 'required_information_name': 'Ref No.'},
      ]),
    );

    await h.settings.upsertCompanyConfiguration(
      company: venue,
      paymentMethods: const [PaymentMethodMeta(name: 'qr-ph')],
    );

    expect(
      h.requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/mode-of-payment/'),
      ),
      isEmpty,
      reason: 'it should have matched the row already there',
    );
    expect(acceptedIdsIn(h.requests), [5]);
  });

  test('a second venue reuses the row just created', () async {
    // Creating it twice in one session would be the duplicate this is meant to
    // avoid, arriving by a different door.
    final h = harness(
      methodsJson: jsonEncode([
        {'id': 1, 'name': 'Cash', 'required_information_name': null},
      ]),
    );

    for (var i = 0; i < 2; i++) {
      await h.settings.upsertCompanyConfiguration(
        company: venue,
        paymentMethods: const [PaymentMethodMeta(name: 'QR PH')],
      );
    }

    expect(
      h.requests
          .where(
            (r) =>
                r.method == 'POST' && r.url.path.endsWith('/mode-of-payment/'),
          )
          .length,
      1,
    );
  });

  test('one method the server refuses does not lose the others', () async {
    final h = harness(
      methodsJson: jsonEncode([
        {'id': 1, 'name': 'Cash', 'required_information_name': null},
      ]),
      failCreate: true,
    );

    await expectLater(
      h.settings.upsertCompanyConfiguration(
        company: venue,
        paymentMethods: const [
          PaymentMethodMeta(name: 'CASH'),
          PaymentMethodMeta(name: 'QR PH'),
        ],
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
