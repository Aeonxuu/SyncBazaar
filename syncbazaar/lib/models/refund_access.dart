import 'bazaar_event.dart';
import 'user.dart';

/// Whether [user] gets a refund button at [event].
///
/// The one place this is decided, so the rule cannot drift between screens.
/// It says nothing about who may *approve*: whoever taps the button, the
/// server accepts only the owner's password or the password of that bazaar's
/// refund handler, so the app never needs to know who the handler is.
///
/// Admins are deliberately out. They can choose the handler but not refund.
bool canRefund(AppUser user, BazaarEvent event) {
  if (event.isFinalized) {
    return false;
  }
  return switch (user.role) {
    UserRole.owner => true,
    UserRole.employee => user.assignedEventIdsEffective.contains(event.id),
    UserRole.admin => false,
  };
}
