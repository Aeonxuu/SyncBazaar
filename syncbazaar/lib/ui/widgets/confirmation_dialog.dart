import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// How serious the confirmation is, which decides the accent and the primary
/// button's colour.
enum ConfirmationTone {
  /// Reversible or additive — publishing, submitting, saving.
  normal,

  /// Irreversible — deleting a product, removing a category.
  destructive,
}

/// Which choice gets the filled button, the focus, and the Enter key.
enum ConfirmationEmphasis {
  /// The confirming action. Right when the user asked for it and the dialog is
  /// a speed bump — they tapped "Delete product", so the dialog is confirming
  /// an intent they already expressed.
  confirm,

  /// The cancelling action. Right when the destructive part is a *consequence*
  /// rather than the request — tapping a navigation item that happens to throw
  /// away a half-rung sale. The user did not ask to lose anything, so backing
  /// out is the likely intent and must be the easy path; the destructive option
  /// stays reachable but quiet, and Enter can no longer trigger it.
  cancel,
}

/// The app's one confirmation modal.
///
/// Rebuilt to match the dialog language used by the product form and the
/// category manager: header / hairline / body / hairline / footer, radius 14,
/// neutral surface. Three things changed beyond styling:
///
/// 1. **Cancel was red and Confirm was green.** Red reads as "the dangerous
///    one", so a destructive action put the alarming colour on the *safe*
///    choice and a reassuring green on the one that deletes your data. Colour
///    now follows the action: Cancel is a quiet text button, and the primary
///    is purple normally or red when [tone] is destructive.
/// 2. **Both buttons were equal-width and full-bleed**, giving a destructive
///    action the same visual weight as backing out. They're now content-sized
///    with the primary on the right, matching every other footer in the app.
/// 3. **Icons on both buttons** added noise to a two-word decision; the
///    primary keeps one only when it's destructive.
Future<bool> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Confirm',
  ConfirmationTone tone = ConfirmationTone.normal,
  ConfirmationEmphasis emphasis = ConfirmationEmphasis.confirm,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _ConfirmationDialog(
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      tone: tone,
      emphasis: emphasis,
      icon: icon,
    ),
  );
  // Dismissing by tapping the barrier reads as backing out, so the absence of
  // an answer is a "no" -- never a silent yes to something irreversible.
  return result ?? false;
}

class _ConfirmationDialog extends StatelessWidget {
  const _ConfirmationDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.tone,
    required this.emphasis,
    this.icon,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final ConfirmationTone tone;

  final ConfirmationEmphasis emphasis;

  /// Overrides the tone's default glyph.
  ///
  /// [ConfirmationTone.destructive] draws a wastebasket, which is right for
  /// deleting a record and wrong for anything else that is merely irreversible
  /// — discarding a half-rung sale loses work without deleting anything the
  /// cashier would call a thing. The tone still decides the colour.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDestructive = tone == ConfirmationTone.destructive;
    final accent = isDestructive ? AppColors.error : AppColors.primary;

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.97, end: 1),
        duration: AppMotion.entrance,
        curve: AppMotion.easeOut,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon ??
                            (isDestructive
                                ? Icons.delete_outline_rounded
                                : Icons.help_outline_rounded),
                        size: 19,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.black54,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                // The filled button is whichever choice the dialog wants to be
                // easy, and it always sits on the right where the eye and the
                // thumb finish. Under `ConfirmationEmphasis.cancel` that is
                // backing out, so the destructive option becomes a quiet text
                // button — still red, still one tap away, but no longer the
                // thing you hit by reflex or by pressing Enter.
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (emphasis == ConfirmationEmphasis.confirm) ...[
                      _QuietButton(
                        label: cancelLabel,
                        color: Colors.black54,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      const SizedBox(width: 12),
                      _FilledButton(
                        label: confirmLabel,
                        color: accent,
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ] else ...[
                      _QuietButton(
                        label: confirmLabel,
                        color: accent,
                        onPressed: () => Navigator.pop(context, true),
                      ),
                      const SizedBox(width: 12),
                      _FilledButton(
                        label: cancelLabel,
                        color: AppColors.primary,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dialog's easy choice: filled, and focused so Enter picks it.
///
/// Secondary-action sizing from the design guidelines' button tiers — auto
/// width, not stretched. A dialog action is not a primary CTA.
class _FilledButton extends StatelessWidget {
  const _FilledButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      // Enter picks this one and Esc dismisses, which is what a keyboard user
      // tries first. It is only ever the safe choice when the dialog says so.
      autofocus: true,
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}

/// The dialog's deliberate choice: present and legible, but not the reflex.
class _QuietButton extends StatelessWidget {
  const _QuietButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(label),
    );
  }
}
