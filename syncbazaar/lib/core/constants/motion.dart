import 'package:flutter/animation.dart';

/// Shared animation timing and easing tokens.
///
/// Curves are strong, custom cubic-beziers (not the built-in Flutter
/// curves) so entrances/feedback feel intentional rather than mushy.
class AppMotion {
  static const Duration feedback = Duration(milliseconds: 140);
  static const Duration small = Duration(milliseconds: 180);
  static const Duration entrance = Duration(milliseconds: 220);

  static const Curve easeOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Curve easeInOut = Cubic(0.77, 0.0, 0.175, 1.0);
}
