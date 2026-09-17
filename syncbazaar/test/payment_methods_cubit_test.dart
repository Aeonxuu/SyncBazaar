import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbazaar/bloc/settings/payment_methods_cubit.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/vendor_payment_method_repository.dart';

/// The cubit behind the Payment Methods screen.
///
/// Every write reloads afterward rather than patching state by hand -- the
/// server is the only thing allowed to say what is actually there, the same
/// rule the quick-edit dialog follows. What is worth pinning here is the
/// failure path: a caught error lands in state rather than throwing through
/// the widget tree, and a failed add tells the dialog to stay open rather
/// than closing on a method that was never created.
void main() {
  List<Map<String, dynamic>> catalog() => [
    {'id': 1, 'name': 'Cash', 'required_information_name': null},
    {'id': 2, 'name': 'GCash', 'required_information_name': 'Reference Number'},
  ];

  ({PaymentMethodsCubit cubit, void Function() goOffline}) harness({
    List<Map<String, dynamic>> vendorRows = const [],
    bool failAdd = false,
  }) {
    var online = true;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        if (!online) {
          throw const SocketException('no route to host');
        }
        final path = request.url.path;
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
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode({'qr_code_image_url': 'https://cdn.example/new.png'}),
            200,
          );
        }
        if (path.endsWith('/mode-of-payment/')) {
          return http.Response(jsonEncode(catalog()), 200);
        }
        return http.Response(jsonEncode(vendorRows), 200);
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    return (
      cubit: PaymentMethodsCubit(VendorPaymentMethodRepository(auth: auth)),
      goOffline: () => online = false,
    );
  }

  test('without a session the state says so, and nothing crashes', () async {
    final cubit = PaymentMethodsCubit(VendorPaymentMethodRepository());

    await cubit.load();

    expect(cubit.state.isRemote, isFalse);
    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.methods, isEmpty);
  });

  test(
    'load carries the vendor\'s methods and the catalog into state',
    () async {
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

      await h.cubit.load();

      expect(h.cubit.state.isRemote, isTrue);
      expect(h.cubit.state.methods.single.name, 'GCASH');
      expect(
        h.cubit.state.catalog.map((e) => e.name),
        containsAll(['Cash', 'GCash']),
      );
    },
  );

  group('adding a method', () {
    test('a success reloads and returns true', () async {
      final h = harness();

      final ok = await h.cubit.addMethod(name: 'GCash');

      expect(ok, isTrue);
      expect(h.cubit.state.error, isNull);
    });

    test('a refusal returns false and lands the reason in state', () async {
      final h = harness(failAdd: true);

      final ok = await h.cubit.addMethod(name: 'GCash');

      expect(ok, isFalse);
      expect(h.cubit.state.error, contains('GCash'));
    });

    test('offline says so rather than the server\'s words', () async {
      final h = harness();
      h.goOffline();

      final ok = await h.cubit.addMethod(name: 'GCash');

      expect(ok, isFalse);
      expect(h.cubit.state.error, contains('Cannot reach the server'));
    });
  });

  group('removing a method', () {
    test('a refusal is caught, not thrown through the cubit', () async {
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
      await h.cubit.load();
      final method = h.cubit.state.methods.single;
      h.goOffline();

      await h.cubit.removeMethod(method);

      expect(h.cubit.state.error, contains('GCASH'));
      // The list is not touched on a failed remove -- reload only follows a
      // write that actually happened.
      expect(h.cubit.state.methods, hasLength(1));
    });
  });

  group('uploading a QR', () {
    test('a success clears any earlier error', () async {
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
      await h.cubit.load();
      final method = h.cubit.state.methods.single;

      await h.cubit.uploadQr(method: method, bytes: Uint8List.fromList([1]));

      expect(h.cubit.state.error, isNull);
    });
  });
}
