import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/utils/formatters.dart';

/// Section 6 of DESIGN_GUIDELINES.md is a rule about every number the user
/// reads. It used to live as eleven copies of a `NumberFormat` plus several
/// screens that ignored it; now it lives here, so it gets pinned here.
void main() {
  group('formatPeso', () {
    test('separates thousands', () {
      expect(formatPeso(12495), 'PHP 12,495.00');
      expect(formatPeso(210231.5), 'PHP 210,231.50');
      expect(formatPeso(1234567.89), 'PHP 1,234,567.89');
    });

    test('always shows two decimal places', () {
      expect(formatPeso(0), 'PHP 0.00');
      expect(formatPeso(5), 'PHP 5.00');
      expect(formatPeso(5.1), 'PHP 5.10');
    });

    test('rounds rather than truncating', () {
      expect(formatPeso(5.006), 'PHP 5.01');
      expect(formatPeso(5.004), 'PHP 5.00');
    });

    test('cannot round a half-cent reliably, because money is a double', () {
      // 5.005 is really 5.00499999... in binary floating point, so it rounds
      // *down*. Not a formatter bug — a consequence of prices being `double`
      // throughout. Documented rather than fixed here: the fix is integer
      // centavos in the model, which is a data-layer change.
      expect(formatPeso(5.005), 'PHP 5.00');
    });

    test('handles negatives', () {
      expect(formatPeso(-1250), 'PHP -1,250.00');
    });

    test('is what the POS used to get wrong', () {
      // The till printed `toStringAsFixed(2)` — the same amount, in the
      // hardest possible format to check against a receipt.
      expect(formatPeso(12495), isNot('PHP ${(12495).toStringAsFixed(2)}'));
    });
  });

  group('formatAmount', () {
    test('is formatPeso without the currency marker', () {
      expect(formatAmount(12495), '12,495.00');
      expect(formatPeso(12495), 'PHP ${formatAmount(12495)}');
    });
  });

  group('formatCount', () {
    test('separates thousands with no decimals', () {
      expect(formatCount(1500), '1,500');
      expect(formatCount(42), '42');
      expect(formatCount(1234567), '1,234,567');
    });

    test('rounds a fractional count to whole units', () {
      expect(formatCount(4.6), '5');
    });
  });

  group('formatDateRange', () {
    test('says the month once when both ends share it', () {
      expect(
        formatDateRange(DateTime(2026, 10, 12), DateTime(2026, 10, 16)),
        'Oct 12 – 16, 2026',
      );
    });

    test('names both months when the run crosses one', () {
      expect(
        formatDateRange(DateTime(2026, 10, 30), DateTime(2026, 11, 2)),
        'Oct 30 – Nov 2, 2026',
      );
    });

    test('names both years when the run crosses the new year', () {
      expect(
        formatDateRange(DateTime(2026, 12, 30), DateTime(2027, 1, 2)),
        'Dec 30, 2026 – Jan 2, 2027',
      );
    });

    test('reads a single day as a date, not a range', () {
      expect(
        formatDateRange(DateTime(2026, 10, 12), DateTime(2026, 10, 12)),
        'Oct 12, 2026',
      );
    });

    test('ignores the time of day on either end', () {
      expect(
        formatDateRange(
          DateTime(2026, 10, 12, 18, 30),
          DateTime(2026, 10, 16, 2, 5),
        ),
        'Oct 12 – 16, 2026',
      );
    });
  });
}
