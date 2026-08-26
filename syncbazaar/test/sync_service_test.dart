import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/services/notification_service.dart';
import 'package:syncbazaar/services/sync_service.dart';

/// What the sidebar's sync control reports.
///
/// It used to announce "Sync completed: 3 sale(s)" after handing a count to a
/// stub that waited 600ms and returned. Nothing had been sent. These pin the
/// rule that replaced it: never claim more than actually happened.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SyncService service;
  late NotificationService notifications;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = NotificationService();
    // No uploader, which is the in-memory build: there is no server to reach.
    service = SyncService(
      salesRepository: SalesRepository(),
      eventRepository: EventRepository(),
      productRepository: ProductRepository(),
      notificationService: notifications,
    );
  });

  test('without a session it says so rather than claiming success', () async {
    final outcome = await service.syncNow();

    expect(outcome.uploaded, 0);
    expect(outcome.message, isNot(contains('completed')));
    expect(outcome.message, contains('Nothing to sync'));
  });

  test('it does not invent a count of uploaded sales', () async {
    final outcome = await service.syncNow();

    // The old wording put the number of *unsent* sales into a sentence that
    // read as though they had been sent.
    expect(outcome.message, isNot(matches(RegExp(r'Sync completed'))));
    expect(outcome.isComplete, isFalse);
  });

  test('a no-op sync writes no notification', () async {
    await service.syncNow();

    // Nothing was attempted, so there is nothing to record. The old service
    // logged "Sync completed" on every press regardless, which turned the
    // notification list into a record of work that never happened.
    expect(await notifications.listAll(), isEmpty);
  });
}
