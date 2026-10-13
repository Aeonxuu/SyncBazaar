import 'package:flutter/material.dart';

/// A tall filled button -- the primary/confirming action in a dialog footer
/// or a persistent action row.
///
/// Extracted from `confirmation_dialog.dart`'s old private `_FilledButton` so
/// every "quiet + primary" pair in the app (POS Cancel/Finish, the QR payment
/// dialog's Payment Received, Confirm Sale, the receipt dialog's Close/Try
/// again) shares one tall, consistent look instead of five near-identical
/// hand-rolled copies at five different heights.
class FilledActionButton extends StatelessWidget {
  const FilledActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  /// True only for a dialog's primary action, where the keyboard should land
  /// the moment it opens. Defaults false so this doesn't steal focus when
  /// used inline on a screen that rebuilds while the user is doing something
  /// else, e.g. the POS footer's "Finish".
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      autofocus: autofocus,
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(label),
    );
  }
}

/// A tall quiet button -- text by default, or bordered via [outlined] when it
/// needs to read as a real choice rather than bare text.
///
/// Extracted from `confirmation_dialog.dart`'s old private `_QuietButton` --
/// see [FilledActionButton].
class QuietActionButton extends StatelessWidget {
  const QuietActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: outlined ? BorderSide(color: color) : BorderSide.none,
        ),
      ),
      child: Text(label),
    );
  }
}
