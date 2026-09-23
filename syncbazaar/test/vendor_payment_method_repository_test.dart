import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/remote/vendor_payment_method_api_mapper.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/vendor_payment_method_repository.dart';

/// A vendor's own payment methods: adding one, reusing the catalog rather
/// than duplicating it, and removing one for good.
///
/// The remove path is what the original bug report was about. A method used
/// to be chosen per venue from a *global* catalog, so a name typed on one
/// venue leaked onto every bazaar for every vendor, and removing it from that
/// one venue changed nothing, because nothing ever read the removal. Here a
/// method belongs to the vendor outright, so removing it is the whole
/// answer: no other list for it to still be on.
void main() {
  List<Map<String, dynamic>> catalog() => [
    {'id': 1, 'name': 'Cash', 'required_information_name': null},
    {'id': 2, 'name': 'GCash', 'required_information_name': 'Reference Number'},
  ];

  ({VendorPaymentMethodRepository repo, List<http.Request> requests}) harness({
    List<Map<String, dynamic>> vendorRows = const [],
    int createdCatalogId = 99,
    String createdName = 'QR PH',
    bool failCreate = false,
    bool failAdd = false,
  }) {
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;

        if (request.method == 'POST' && path.endsWith('/mode-of-payment/')) {
          if (failCreate) {
            return http.Response('{"detail": "nope"}', 400);
          }
          return http.Response(
            jsonEncode({
              'id': createdCatalogId,
              'name': createdName,
              'required_information_name': null,
            }),
            201,
          );
        }
        if (path.endsWith('/mode-of-payment/')) {
          return http.Response(jsonEncode(catalog()), 200);
        }
        if (request.method == 'POST' && path.endsWith('/payment-method/')) {
          if (failAdd) {
            return http.Response(
              jsonEncode({
                'mode_of_payment': ['already assigned'],
              }),
              400,
            );
          }
          return http.Response('{}', 201);
        }
        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }
        if (path.endsWith('/payment-method/')) {
          return http.Response(jsonEncode(vendorRows), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    return (
      repo: VendorPaymentMethodRepository(auth: auth),
      requests: requests,
    );
  }

  test('without a session there is nothing to manage', () async {
    final repo = VendorPaymentMethodRepository();

    expect(repo.isRemote, isFalse);
    expect(await repo.listMethods(), isEmpty);
  });

  group('adding a method', () {
    test('reuses a catalog entry rather than creating a duplicate', () async {
      final h = harness();

      await h.repo.addMethod(name: 'GCash');

      final created = h.requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/mode-of-payment/'),
      );
      expect(created, isEmpty, reason: 'GCash was already in the catalog');
      final assign = h.requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/payment-method/'),
      );
      expect(jsonDecode(assign.body), {'mode_of_payment': 2});
    });

    test('spacing and case do not create a second catalog row', () async {
      // The exact trap the original venue-editor fix was written for: the
      // catalog holds "GCash", somebody types "gcash".
      final h = harness();

      await h.repo.addMethod(name: 'gcash');

      expect(
        h.requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/mode-of-payment/'),
        ),
        isEmpty,
      );
    });

    test('a genuinely new name creates a catalog entry first', () async {
      final h = harness();

      await h.repo.addMethod(name: 'QR PH', label: 'Reference Number');

      final created = h.requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/mode-of-payment/'),
      );
      expect(jsonDecode(created.body), {
        'name': 'QR PH',
        'required_information_name': 'Reference Number',
      });
      final assign = h.requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/payment-method/'),
      );
      expect(jsonDecode(assign.body), {'mode_of_payment': 99});
    });

    test('a refused assignment is left to throw, not swallowed', () async {
      // Silently dropping this would be the exact bug being fixed one layer
      // up: a method that looks added and is not.
      final h = harness(failAdd: true);

      await expectLater(
        h.repo.addMethod(name: 'GCash'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a refused catalog create is left to throw', () async {
      final h = harness(failCreate: true);

      await expectLater(
        h.repo.addMethod(name: 'QR PH'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('removing a method', () {
    test('is the whole toggle -- nothing else to check afterward', () async {
      final h = harness(
        vendorRows: [
          {
            'id': 11,
            'mode_of_payment_name': 'GCash',
            'qr_code_image_url': null,
            'vendor': 1,
            'mode_of_payment': 2,
          },
        ],
      );
      final method = (await h.repo.listMethods()).single;

      await h.repo.removeMethod(method);

      final delete = h.requests.singleWhere((r) => r.method == 'DELETE');
      expect(delete.url.path, '/api/core/vendor/1/payment-method/11/');
    });

    test('offline changes nothing and lets the error out', () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'DELETE') {
            throw const SocketException('no route to host');
          }
          if (request.url.path.endsWith('/mode-of-payment/')) {
            return http.Response(jsonEncode(catalog()), 200);
          }
          return http.Response(
            jsonEncode([
              {
                'id': 11,
                'mode_of_payment_name': 'GCash',
                'qr_code_image_url': null,
                'vendor': 1,
                'mode_of_payment': 2,
              },
            ]),
            200,
          );
        }),
      );
      final auth = AuthRepository(apiClient: client)..vendorId = 1;
      final repo = VendorPaymentMethodRepository(auth: auth);
      final method = (await repo.listMethods()).single;

      await expectLater(
        repo.removeMethod(method),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
    });

    test('without a session there is nothing to remove from', () async {
      await expectLater(
        VendorPaymentMethodRepository().removeMethod(
          const VendorPaymentMethod(id: 1, modeOfPaymentId: 2, name: 'GCASH'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('uploading a QR', () {
    test('sends a multipart PATCH to that row\'s image endpoint', () async {
      final requests = <http.BaseRequest>[];
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'PATCH') {
            return http.Response(
              jsonEncode({'qr_code_image_url': 'https://cdn.example/new.png'}),
              200,
            );
          }
          if (request.url.path.endsWith('/mode-of-payment/')) {
            return http.Response(jsonEncode(catalog()), 200);
          }
          return http.Response(
            jsonEncode([
              {
                'id': 11,
                'mode_of_payment_name': 'GCash',
                'qr_code_image_url': null,
                'vendor': 1,
                'mode_of_payment': 2,
              },
            ]),
            200,
          );
        }),
      );
      final auth = AuthRepository(apiClient: client)..vendorId = 1;
      final repo = VendorPaymentMethodRepository(auth: auth);
      final method = (await repo.listMethods()).single;

      await repo.uploadQr(method: method, bytes: Uint8List.fromList([1, 2, 3]));

      final upload = requests.singleWhere((r) => r.method == 'PATCH');
      expect(upload.url.path, '/api/core/vendor/1/payment-method/11/image/');
      // MockClient hands the handler a finalized Request, not the original
      // MultipartRequest, so the multipart-ness is read off the wire form
      // instead: the content type it negotiated, and the field name inside
      // the body it encoded.
      expect(upload.headers['content-type'], contains('multipart/form-data'));
      expect((upload as http.Request).body, contains('name="qr_code_image"'));
    });

    test('without a session there is nothing to upload to', () async {
      await expectLater(
        VendorPaymentMethodRepository().uploadQr(
          method: const VendorPaymentMethod(
            id: 1,
            modeOfPaymentId: 2,
            name: 'GCASH',
          ),
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
