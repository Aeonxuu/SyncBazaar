import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/notification.dart';
import '../../services/notification_service.dart';

class NotificationsState {
  const NotificationsState({this.items = const [], this.unreadCount = 0});

  final List<AppNotification> items;
  final int unreadCount;

  bool get isEmpty => items.isEmpty;
}

/// Backs both the sidebar badge and the Notifications screen.
///
/// One cubit for both so the count on the rail and the list behind it are the
/// same read of the same store — a badge that disagrees with the screen it
/// points at trains people to ignore the badge.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit(this._service) : super(const NotificationsState());

  final NotificationService _service;

  Future<void> load() async {
    emit(
      NotificationsState(
        items: await _service.listAll(),
        unreadCount: await _service.unreadCount(),
      ),
    );
  }

  Future<void> markAllRead() async {
    await _service.markAllRead();
    await load();
  }

  Future<void> markRead(int id) async {
    await _service.markRead(id);
    await load();
  }
}
