import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/vendor_payment_method_api_mapper.dart';

/// The two calls a vendor's payment methods are built from, and how they
/// join.
///
/// `GET .../payment-method/` names each row's own id and which catalog entry
/// it points at, but not the reference-field label -- only the catalog
/// knows that a GCash-shaped method wants one. Getting the join backwards, or
/// dropping a row with nothing to join against, is the kind of mistake that
/// shows up as "the reference field vanished" months later, not as a crash
/// now.
void main() {
  const catalogPayload = [
    {'id': 1, 'name': 'Cash', 'required_information_name': null},
    {'id': 2, 'name': 'GCash', 'required_information_name': 'Reference Number'},
    {'id': 3, 'name': 'QR PH', 'required_information_name': '  '},
  ];

  group('the catalog', () {
    test('reads id, name and the reference-field label', () {
      final catalog = mapModeOfPaymentCatalog(catalogPayload);

      final gcash = catalog.firstWhere((e) => e.name == 'GCash');
      expect(gcash.id, 2);
      expect(gcash.extraFieldLabel, 'Reference Number');
    });

    test('a blank label is null, not an empty string', () {
      // A blank label and no label mean the same thing to every caller that
      // checks for one; keeping the distinction would just be a second way
      // to represent "none" that somebody eventually forgets to check.
      final catalog = mapModeOfPaymentCatalog(catalogPayload);

      expect(
        catalog.firstWhere((e) => e.name == 'QR PH').extraFieldLabel,
        isNull,
      );
    });

    test('an entry with no name is dropped, not kept blank', () {
      final catalog = mapModeOfPaymentCatalog([
        {'id': 9, 'name': '', 'required_information_name': null},
        ...catalogPayload,
      ]);

      expect(catalog.map((e) => e.id), isNot(contains(9)));
    });
  });

  group('a vendor\'s own list', () {
    Map<int, ModeOfPaymentCatalogEntry> catalogById() => {
      for (final entry in mapModeOfPaymentCatalog(catalogPayload))
        entry.id: entry,
    };

    test('the label comes from the catalog, not from this response', () {
      // The vendor-scoped payload never carries it -- confirmed against a
      // real response before this mapper was written. A method built from
      // this payload alone would have no reference field at all.
      final methods = mapVendorPaymentMethods([
        {
          'id': 11,
          'mode_of_payment_name': 'GCash',
          'qr_code_image_url': null,
          'vendor': 1,
          'mode_of_payment': 2,
        },
      ], catalogById: catalogById());

      expect(methods.single.extraFieldLabel, 'Reference Number');
    });

    test('keeps this row\'s own id separate from the catalog id', () {
      // The row id is what a removal or a QR upload addresses; the catalog
      // id is only for the join. Conflating them sends a delete to the
      // wrong endpoint.
      final methods = mapVendorPaymentMethods([
        {
          'id': 11,
          'mode_of_payment_name': 'GCash',
          'qr_code_image_url': null,
          'vendor': 1,
          'mode_of_payment': 2,
        },
      ], catalogById: catalogById());

      expect(methods.single.id, 11);
      expect(methods.single.modeOfPaymentId, 2);
    });

    test('carries the QR url through unchanged', () {
      final methods = mapVendorPaymentMethods([
        {
          'id': 11,
          'mode_of_payment_name': 'GCash',
          'qr_code_image_url': 'https://cdn.example/gcash.png',
          'vendor': 1,
          'mode_of_payment': 2,
        },
      ], catalogById: catalogById());

      expect(methods.single.qrImageUrl, 'https://cdn.example/gcash.png');
    });

    test(
      'a row pointing at nothing in the catalog is not skipped silently',
      () {
        // Falls back to its own name rather than an empty one -- a row
        // disappearing off the list would read as "the method was removed"
        // when it was really a join miss.
        final methods = mapVendorPaymentMethods([
          {
            'id': 11,
            'mode_of_payment_name': 'ShopeePay',
            'qr_code_image_url': null,
            'vendor': 1,
            'mode_of_payment': 999,
          },
        ], catalogById: catalogById());

        expect(methods.single.name, 'SHOPEEPAY');
        expect(methods.single.extraFieldLabel, isNull);
      },
    );

    test(
      'names are upper-cased, matching every other method name in the app',
      () {
        final methods = mapVendorPaymentMethods([
          {
            'id': 11,
            'mode_of_payment_name': 'GCash',
            'qr_code_image_url': null,
            'vendor': 1,
            'mode_of_payment': 2,
          },
        ], catalogById: catalogById());

        expect(methods.single.name, 'GCASH');
      },
    );
  });

  group('paths', () {
    test('the vendor\'s own list', () {
      expect(vendorPaymentMethodsPath(4), '/api/core/vendor/4/payment-method/');
    });

    test('one row, for removing or reading back', () {
      expect(
        vendorPaymentMethodPath(4, 11),
        '/api/core/vendor/4/payment-method/11/',
      );
    });

    test('the image endpoint', () {
      expect(
        vendorPaymentMethodImagePath(4, 11),
        '/api/core/vendor/4/payment-method/11/image/',
      );
    });
  });
}
