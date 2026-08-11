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
    ),
  );
  return result ?? false;
}

class _ConfirmationDialog extends StatelessWidget {
  const _ConfirmationDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.tone,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final ConfirmationTone tone;

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
                        isDestructive
                            ? Icons.delete_outline_rounded
                            : Icons.help_outline_rounded,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      child: Text(cancelLabel),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      // Focused by default so Enter confirms and Esc cancels,
                      // which is what a keyboard user will try first.
                      autofocus: true,
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(confirmLabel),
                    ),
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
