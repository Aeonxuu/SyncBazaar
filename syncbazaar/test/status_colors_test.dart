import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/constants/colors.dart';

/// A bazaar's status colour, now that there is one of each.
///
/// Twelve files used to declare these themselves, and two had already
/// drifted by the time they were consolidated: upcoming was #8A6100 in the
/// orders badge against #B45309 everywhere else, and ended was grey there
/// against the error red everywhere else. So the same bazaar wore different
/// colours depending on which screen you were looking at.
void main() {
  test('every status has its own colour', () {
    final colours = {
      AppColors.statusOngoing,
      AppColors.statusUpcoming,
      AppColors.statusEnded,
    };

    // Three distinct values: two statuses sharing a colour is the same as
    // having no colour coding at all.
    expect(colours, hasLength(3));
  });

  test('ended reuses the error red rather than inventing one', () {
    expect(AppColors.statusEnded, AppColors.error);
  });

  test('the colours are the ones the guidelines name', () {
    expect(AppColors.statusOngoing, const Color(0xFF2E7D32));
    expect(AppColors.statusUpcoming, const Color(0xFFB45309));
  });

  test('a badge fill is the status at 12 percent', () {
    // Full strength for the text, 12% for the fill -- a solid badge is too
    // loud for a label that size.
    final fill = AppColors.statusOngoing.withValues(alpha: 0.12);

    expect(fill.a, closeTo(0.12, 0.001));
    expect(fill.r, AppColors.statusOngoing.r);
  });
}
