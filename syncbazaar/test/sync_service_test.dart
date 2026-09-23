import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/services/notification_service.dart';
import 'package:syncbazaar/services/sale_upload_service.dart';
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
      settingsRepository: SettingsRepository(),
    );
  });

  test('pulling down refreshes venues and payment methods too', () async {
    // This list used to be fetched once at sign-in and never again, so a
    // payment method added on the server did not reach the till until the app
    // was restarted. Nobody thinks to restart an app mid-bazaar.
    final settings = _SpySettings();
    final sales = SalesRepository();
    final events = EventRepository();
    final products = ProductRepository();
    final withUploader = SyncService(
      salesRepository: sales,
      eventRepository: events,
      productRepository: products,
      notificationService: notifications,
      settingsRepository: settings,
      // Nothing queued, so this returns without touching the network and the
      // pull-down half still runs.
      saleUploader: SaleUploadService(
        auth: AuthRepository(),
        events: events,
        products: products,
        sales: sales,
      ),
    );

    await withUploader.syncNow();

    expect(settings.refreshCount, 1);
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

  test('a server-rejected sale is reported as rejected, not offline', () async {
    // What actually happened on Sept 18: the batch-sale endpoint answered
    // with a 400, and the old message ("Could not reach the server") read as
    // a connectivity problem when the server had been reached the whole time.
    final withRejection = SyncService(
      salesRepository: SalesRepository(),
      eventRepository: EventRepository(),
      productRepository: ProductRepository(),
      notificationService: notifications,
      settingsRepository: SettingsRepository(),
      saleUploader: _RejectingUploader(),
    );

    final outcome = await withRejection.syncNow();

    expect(outcome.message, isNot(contains('Could not reach the server')));
    expect(outcome.message, contains('rejected'));
    expect(outcome.message, contains('event_stock'));
  });
}

/// Reports a sale the server refused, without a real batch-sale POST behind
/// it -- `uploadPending` is overridden directly rather than routed through
/// `ApiClient`, since this test is only about what `SyncService` says in
/// response to a [SaleUploadResult] carrying [SaleUploadResult.rejected].
class _RejectingUploader extends SaleUploadService {
  _RejectingUploader()
    : super(
        auth: AuthRepository(),
        events: EventRepository(),
        products: ProductRepository(),
        sales: SalesRepository(),
      );

  @override
  Future<SaleUploadResult> uploadPending() async => const SaleUploadResult(
    uploaded: 0,
    skipped: 0,
    rejected: 1,
    rejectionReason: 'event_stock: Invalid pk "999" - object does not exist.',
  );
}

/// Records that a refresh was asked for, without a server to ask.
class _SpySettings extends SettingsRepository {
  int refreshCount = 0;

  @override
  Future<void> refresh() async => refreshCount++;
}
