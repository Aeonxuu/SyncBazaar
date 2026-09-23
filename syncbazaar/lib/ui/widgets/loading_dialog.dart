import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// Shows a small non-dismissible "something is happening" dialog: a spinner
/// and a one-line message, for a multi-step action with nothing on screen
/// otherwise saying it's in progress (Nielsen's Visibility of System Status)
/// — publishing a bazaar runs half a dozen sequential requests behind an
/// otherwise-unchanged screen, and a tap with no feedback reads as "it didn't
/// work," inviting a second one mid-submission.
///
/// The caller owns dismissal. `showDialog` defaults to the root navigator,
/// so capture that *before* starting the awaited work — a local
/// `Navigator.of(context)` resolved afterwards may belong to a widget that
/// has since been disposed:
///
/// ```dart
/// final dialogNavigator = Navigator.of(context, rootNavigator: true);
/// showLoadingDialog(context, 'Publishing bazaar…');
/// try {
///   await doTheWork();
/// } finally {
///   dialogNavigator.pop();
/// }
/// ```
void showLoadingDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _LoadingDialog(message: message),
  );
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // No back-button/Esc dismissal either — the barrier already refuses a
      // tap, and a half-finished submission has nowhere safe to un-show.
      canPop: false,
      child: Dialog(
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
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
