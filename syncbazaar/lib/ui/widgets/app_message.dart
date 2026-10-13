import 'package:flutter/material.dart';

import 'confirmation_dialog.dart';

/// The app's navigator, so a message can be shown from code that no longer
/// holds a usable [BuildContext].
///
/// Handlers capture what they need before an `await` because the widget that
/// started them may be gone by the time they finish; a SnackBar got around
/// that with a captured `ScaffoldMessenger`. A dialog needs a live navigator
/// instead, and this is the one that outlives every screen.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// What a message is telling the user, which decides its heading and glyph.
enum AppMessageKind { success, error, info }

/// Tells the user something in a dialog that holds until dismissed.
///
/// Replaces the app's SnackBars. On a tablet they sat at the bottom edge, were
/// easy to miss and gone in a few seconds, which is how a refused delete or a
/// failed save read as though nothing had happened. Returns once dismissed, or
/// straight away when the app has no navigator to show it on.
Future<void> showAppMessage(
  String message, {
  AppMessageKind kind = AppMessageKind.info,
  String? title,
}) async {
  final overlayContext = appNavigatorKey.currentState?.overlay?.context;
  if (overlayContext == null) {
    return;
  }
  await showNoticeDialog(
    context: overlayContext,
    title: title ?? _defaultTitle(kind),
    message: message,
    buttonLabel: 'Okay',
    tone: kind == AppMessageKind.error
        ? ConfirmationTone.destructive
        : ConfirmationTone.normal,
    icon: switch (kind) {
      AppMessageKind.success => Icons.check_circle_outline_rounded,
      AppMessageKind.error => Icons.error_outline_rounded,
      AppMessageKind.info => Icons.info_outline_rounded,
    },
  );
}

String _defaultTitle(AppMessageKind kind) => switch (kind) {
  AppMessageKind.success => 'Done',
  AppMessageKind.error => 'Something went wrong',
  AppMessageKind.info => 'Notice',
};
