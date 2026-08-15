import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF6C4AB6);
  static const Color primaryLight = Color(0xFFEDE7F6);
  static const Color accent = Color(0xFFFFC107);
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFEFEFE);

  /// Fill for text inputs, dropdown triggers and photo wells.
  ///
  /// Neutral on purpose. [primaryLight] is the *unselected* fill in the
  /// selection colour rule, so using it on ordinary inputs made plain fields
  /// carry a faint "option you can pick" signal and diluted what purple means.
  static const Color inputFill = Color(0xFFF0F1F4);

  /// Hairline rules and flat-card borders.
  static const Color border = Color(0xFFEDEDF1);
  static const Color text = Color(0xFF212529);
  static const Color error = Color(0xFFDC3545);

  /// A bazaar's status, as a colour.
  ///
  /// Promoted here from twelve files that each declared their own copy, which
  /// is what the design guidelines asked for the next time anyone touched
  /// them. They had already drifted by then: upcoming was #B45309 in five
  /// places and #8A6100 in the orders badge, and ended was the error red
  /// everywhere except that same badge, where it was grey.
  ///
  /// Badges use these at 12% opacity as the fill with the full strength as
  /// the text -- a solid badge is too loud for a label that size.
  static const Color statusOngoing = Color(0xFF2E7D32);
  static const Color statusUpcoming = Color(0xFFB45309);
  static const Color statusEnded = error;

  /// Confirmation and "ongoing" status.
  ///
  /// Was a bare `Color(0xFF2E7D32)` repeated at every success SnackBar and
  /// status badge; promoted here per section 3 of DESIGN_GUIDELINES.md the
  /// first time a change touched one.
  static const Color success = Color(0xFF2E7D32);
}
