import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/utils/formatters.dart';

/// Validation and the rate preview in the venue editor.
///
/// The rates are the point of this screen: both come off every sale made at
/// the venue, and a pair of numbers that add past 100 promises more of a sale
/// than the sale contains. Errors used to arrive as SnackBars, which name a
/// problem at the bottom of the screen and leave the reader to work out which
/// of five fields it belongs to.
void main() {
  /// The editor's own check.
  String? ratesError(double? incentive, double? buffer) {
    if (incentive == null || buffer == null) {
      return 'Both rates must be numbers.';
    }
    if (incentive < 0 || buffer < 0) {
      return 'A rate cannot be negative.';
    }
    if (incentive + buffer > 100) {
      return 'Together these take more than the whole sale.';
    }
    return null;
  }

  group('rates', () {
    test('an ordinary pair is accepted', () {
      expect(ratesError(10, 5), isNull);
    });

    test('rates that exceed the whole sale are refused', () {
      // 60 + 50 leaves the vendor owing money on every sale.
      expect(ratesError(60, 50), isNotNull);
    });

    test('exactly the whole sale is allowed', () {
      // Unusual, but it is arithmetic that works: the vendor keeps nothing.
      expect(ratesError(90, 10), isNull);
    });

    test('a negative rate is refused', () {
      expect(ratesError(-1, 10), isNotNull);
    });

    test('unparseable text is refused rather than read as zero', () {
      // Zero would save silently and quietly halve nobody's payout until
      // somebody noticed.
      expect(ratesError(null, 10), isNotNull);
    });
  });

  group('preview', () {
    /// What the editor shows beneath the rates.
    (String venue, String retained) preview(double incentive, double buffer) {
      const sales = 10000.0;
      final share = sales * (incentive + buffer) / 100;
      return (formatPeso(share), formatPeso(sales - share));
    }

    test('turns a pair of percentages into money', () {
      // A percentage is abstract until it is an amount.
      final (venue, retained) = preview(10, 5);

      expect(venue, 'PHP 1,500.00');
      expect(retained, 'PHP 8,500.00');
    });

    test('the two halves always account for the whole sale', () {
      final (venue, retained) = preview(8, 10);

      expect(venue, 'PHP 1,800.00');
      expect(retained, 'PHP 8,200.00');
    });

    test('no rates means nothing is taken', () {
      final (venue, retained) = preview(0, 0);

      expect(venue, 'PHP 0.00');
      expect(retained, 'PHP 10,000.00');
    });
  });
}
