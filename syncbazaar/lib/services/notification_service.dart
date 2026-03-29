import '../models/notification.dart';

class NotificationService {
  final List<AppNotification> _notifications = [];

  Future<List<AppNotification>> listAll() async => _notifications;

  Future<void> add({required String type, required String message}) async {
    _notifications.add(
      AppNotification(
        id: _notifications.length + 1,
        type: type,
        message: message,
        createdAt: DateTime.now(),
        read: false,
      ),
    );
  }
}
