import 'package:flutter_test/flutter_test.dart';

/// How an order row is built.
///
/// The product arrives as one string — "Nike ZoomX Vaporfly (Color Panda,
/// Size 43)" — which wrapped to two lines at an uneven height and made every
/// row a different size. It is split so the product sits on one line and the
/// variant beneath it, and the row is two short lines by construction.
void main() {
  /// The row's own split.
  (String product, String variant) split(String label) {
    final bracket = label.indexOf('(');
    if (bracket == -1) {
      return (label, '');
    }
    return (
      label.substring(0, bracket).trim(),
      label.substring(bracket + 1).replaceAll(')', '').trim(),
    );
  }

  /// The row's own clock.
  String time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
  }

  group('product label', () {
    test('splits the variant off the product name', () {
      final (product, variant) = split(
        'Nike ZoomX Vaporfly (Color Panda, Size 43)',
      );

      expect(product, 'Nike ZoomX Vaporfly');
      expect(variant, 'Color Panda, Size 43');
    });

    test('a product with no variant keeps the whole line', () {
      final (product, variant) = split('Tote Bag');

      expect(product, 'Tote Bag');
      expect(variant, '');
    });

    test('a name containing a bracket still splits at the variant', () {
      final (product, variant) = split(
        'Onitsuka Tiger Mexico 66 (Color Cream/Peacoat, Size 40)',
      );

      expect(product, 'Onitsuka Tiger Mexico 66');
      expect(variant, 'Color Cream/Peacoat, Size 40');
    });
  });

  group('time', () {
    test('midnight and noon are twelve, not zero', () {
      // 0:00 AM is not a time anybody writes.
      expect(time(DateTime(2026, 8, 7, 0, 5)), '12:05 AM');
      expect(time(DateTime(2026, 8, 7, 12, 0)), '12:00 PM');
    });

    test('the afternoon reads as PM', () {
      expect(time(DateTime(2026, 8, 7, 14, 32)), '2:32 PM');
    });

    test('minutes are padded', () {
      expect(time(DateTime(2026, 8, 7, 8, 0)), '8:00 AM');
      expect(time(DateTime(2026, 8, 7, 8, 7)), '8:07 AM');
    });
  });
}
