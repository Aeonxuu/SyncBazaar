import '../models/notification.dart';

/// In-memory store for the notices the app raises about its own background
/// work — today that is [SyncService] reporting what it pushed.
///
/// Read state lives here rather than in the UI so the sidebar badge and the
/// Notifications screen can never disagree about how many are unread.
class NotificationService {
  final List<AppNotification> _notifications = [];
  int _nextId = 1;

  /// Newest first, which is the order the screen shows and the only order
  /// anyone reads a notification list in.
  Future<List<AppNotification>> listAll() async =>
      _notifications.reversed.toList();

  Future<int> unreadCount() async =>
      _notifications.where((n) => !n.read).length;

  Future<void> add({required String type, required String message}) async {
    _notifications.add(
      AppNotification(
        id: _nextId++,
        type: type,
        message: message,
        createdAt: DateTime.now(),
        read: false,
      ),
    );
  }

  Future<void> markAllRead() async {
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].read) {
        _notifications[i] = _notifications[i].copyWith(read: true);
      }
    }
  }

  Future<void> markRead(int id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _notifications[index] = _notifications[index].copyWith(read: true);
  }
}
