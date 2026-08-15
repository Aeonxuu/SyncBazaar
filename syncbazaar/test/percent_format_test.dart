import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/utils/formatters.dart';

/// How a rate is written.
///
/// The same percentage was being spelled three ways across the app — "10.0%"
/// on the venue list, "10%" in the statement of account, "10.0" in the
/// approvals table — because each place formatted it itself. A formatting rule
/// re-implemented per file drifts, which is why the money formats have one
/// home and why this now does too.
void main() {
  test('a whole rate carries no decimal it does not need', () {
    expect(formatPercent(10), '10%');
    expect(formatPercent(5), '5%');
    expect(formatPercent(10.0), '10%');
  });

  test('a fractional rate keeps its decimal', () {
    // Venues do agree half points, and rounding one away silently understates
    // what comes off the payout.
    expect(formatPercent(12.5), '12.5%');
    expect(formatPercent(7.5), '7.5%');
  });

  test('zero is a rate, not a blank', () {
    expect(formatPercent(0), '0%');
  });

  test('more than one decimal is rounded, not printed in full', () {
    expect(formatPercent(10.25), '10.3%');
    expect(formatPercent(10.04), '10%');
  });
}
