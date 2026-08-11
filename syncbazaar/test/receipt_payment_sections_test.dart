import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/services/receipt_payment_sections.dart';

/// The registry is the extension point for future payment methods, so what is
/// pinned here is mostly its *fallback* behaviour: payment methods in this app
/// are free text merged from global settings and per-event custom entries, so
/// an unrecognised name is a normal input and must still produce a receipt.
void main() {
  group('ReceiptSectionRegistry.resolve', () {
    test('matches CASH regardless of case or surrounding whitespace', () {
      for (final name in ['CASH', 'cash', ' Cash ', 'cAsH']) {
        expect(
          ReceiptSectionRegistry.resolve(name),
          isA<CashReceiptSection>(),
          reason: '"$name" should resolve to the cash section',
        );
      }
    });

    test('falls back to the reference section for unregistered methods', () {
      for (final name in ['GCASH', 'COOP', 'Maya', 'Utang kay Nanay', '']) {
        expect(
          ReceiptSectionRegistry.resolve(name),
          isA<ReferenceReceiptSection>(),
          reason: '"$name" should fall back rather than throw',
        );
      }
    });
  });

  group('CashReceiptSection', () {
    const section = CashReceiptSection();

    test('asks the POS for a tendered amount', () {
      expect(section.requiresTendered, isTrue);
    });

    test('prints cash and change, emphasising the change', () {
      final details = section.details(
        const ReceiptPaymentContext(
          total: 1450,
          paymentMethod: 'CASH',
          cashTendered: 2000,
        ),
      );

      expect(details, hasLength(2));
      expect(details.first.label, 'Cash');
      expect(details.first.value, 'PHP 2,000.00');
      expect(details.last.label, 'Change');
      expect(details.last.value, 'PHP 550.00');
      expect(details.last.emphasize, isTrue);
    });

    test('never prints negative change when tendered is short', () {
      final details = section.details(
        const ReceiptPaymentContext(
          total: 1450,
          paymentMethod: 'CASH',
          cashTendered: 1000,
        ),
      );

      expect(details.last.value, 'PHP 0.00');
    });

    test('prints nothing when no amount was tendered', () {
      final details = section.details(
        const ReceiptPaymentContext(total: 1450, paymentMethod: 'CASH'),
      );

      expect(details, isEmpty);
    });
  });

  group('ReferenceReceiptSection', () {
    const section = ReferenceReceiptSection();

    test('needs no tendered amount', () {
      expect(section.requiresTendered, isFalse);
    });

    test(
      'prints a configured reference with no per-method code',
      () {
        // The whole point of the fallback: a wallet added in settings with an
        // extraFieldLabel prints its reference row without being registered.
        final details = section.details(
          const ReceiptPaymentContext(
            total: 1450,
            paymentMethod: 'GCASH',
            extraFieldLabel: 'GCash Ref No.',
            extraFieldValue: '0057123456',
          ),
        );

        expect(details, hasLength(1));
        expect(details.single.label, 'GCash Ref No.');
        expect(details.single.value, '0057123456');
        expect(details.single.emphasize, isFalse);
      },
    );

    test('prints nothing when the method has no reference configured', () {
      final details = section.details(
        const ReceiptPaymentContext(total: 1450, paymentMethod: 'COOP'),
      );

      expect(details, isEmpty);
    });

    test('prints nothing when the reference was left blank', () {
      final details = section.details(
        const ReceiptPaymentContext(
          total: 1450,
          paymentMethod: 'GCASH',
          extraFieldLabel: 'GCash Ref No.',
          extraFieldValue: '   ',
        ),
      );

      expect(details, isEmpty);
    });
  });

  group('ReceiptPaymentContext.changeDue', () {
    test('is null when nothing was tendered', () {
      expect(
        const ReceiptPaymentContext(
          total: 100,
          paymentMethod: 'CASH',
        ).changeDue,
        isNull,
      );
    });

    test('clamps at zero rather than going negative', () {
      expect(
        const ReceiptPaymentContext(
          total: 100,
          paymentMethod: 'CASH',
          cashTendered: 40,
        ).changeDue,
        0,
      );
    });
  });
}
