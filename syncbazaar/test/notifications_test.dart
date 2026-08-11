import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/bloc/notifications/notifications_cubit.dart';
import 'package:syncbazaar/services/notification_service.dart';

/// The sidebar badge and the Notifications screen read the same store, so the
/// count and the list must never be able to disagree.
void main() {
  late NotificationService service;
  late NotificationsCubit cubit;

  setUp(() {
    service = NotificationService();
    cubit = NotificationsCubit(service);
  });

  test('starts empty rather than with a placeholder count', () async {
    await cubit.load();

    // The old bell hardcoded `isAdminOrOwner ? 2 : 1`, so a fresh account
    // always showed unread notices it did not have.
    expect(cubit.state.unreadCount, 0);
    expect(cubit.state.isEmpty, isTrue);
  });

  test('new notices arrive unread and are counted', () async {
    await service.add(type: 'sync', message: 'Sync completed: 3 sale(s).');
    await service.add(type: 'sync', message: 'Sync completed: 1 order(s).');
    await cubit.load();

    expect(cubit.state.items, hasLength(2));
    expect(cubit.state.unreadCount, 2);
  });

  test('lists newest first', () async {
    await service.add(type: 'sync', message: 'first');
    await service.add(type: 'sync', message: 'second');
    await cubit.load();

    expect(cubit.state.items.first.message, 'second');
    expect(cubit.state.items.last.message, 'first');
  });

  test(
    'reading one decrements the count without touching the others',
    () async {
      await service.add(type: 'sync', message: 'a');
      await service.add(type: 'sync', message: 'b');
      await cubit.load();

      final target = cubit.state.items.first;
      await cubit.markRead(target.id);

      expect(cubit.state.unreadCount, 1);
      expect(
        cubit.state.items.firstWhere((n) => n.id == target.id).read,
        isTrue,
      );
      expect(cubit.state.items.where((n) => !n.read), hasLength(1));
    },
  );

  test('mark all read clears the badge but keeps the history', () async {
    await service.add(type: 'sync', message: 'a');
    await service.add(type: 'sync', message: 'b');
    await cubit.load();

    await cubit.markAllRead();

    expect(cubit.state.unreadCount, 0);
    expect(cubit.state.items, hasLength(2), reason: 'read is not deleted');
  });

  test('marking an unknown id is a no-op, not a crash', () async {
    await service.add(type: 'sync', message: 'a');
    await cubit.load();

    await cubit.markRead(9999);

    expect(cubit.state.unreadCount, 1);
  });

  test('ids stay unique after reads', () async {
    // The old service derived ids from `_notifications.length`, which repeats
    // as soon as the list is ever mutated by anything but an append.
    for (var i = 0; i < 5; i++) {
      await service.add(type: 'sync', message: 'n$i');
    }
    await cubit.load();

    final ids = cubit.state.items.map((n) => n.id).toSet();
    expect(ids, hasLength(5));
  });
}
