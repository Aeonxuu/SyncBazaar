import '../data/repositories/event_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'notification_service.dart';
import 'sale_upload_service.dart';

/// What the sidebar's sync control does: push up, then pull down.
///
/// It used to hand a count of unsynced rows to a stub that waited 600ms and
/// returned, then announce "Sync completed: 3 sale(s)". Nothing left the
/// device. A control that reports success for work it never did is worse than
/// no control, because it is the one thing a cashier would trust after a day
/// of selling with no signal.
///
/// Both halves matter and in this order. Sales rung up offline are the only
/// records that exist nowhere else, so they go first; refreshing before
/// uploading would overwrite the local picture while a sale was still waiting.
class SyncService {
  SyncService({
    required SalesRepository salesRepository,
    required EventRepository eventRepository,
    required ProductRepository productRepository,
    required NotificationService notificationService,
    required SettingsRepository settingsRepository,
    SaleUploadService? saleUploader,
  }) : _salesRepository = salesRepository,
       _eventRepository = eventRepository,
       _productRepository = productRepository,
       _notificationService = notificationService,
       _settingsRepository = settingsRepository,
       _saleUploader = saleUploader;

  final SalesRepository _salesRepository;
  final EventRepository _eventRepository;
  final ProductRepository _productRepository;
  final NotificationService _notificationService;
  final SettingsRepository _settingsRepository;

  /// Absent in the in-memory build, where there is nowhere to upload to.
  final SaleUploadService? _saleUploader;

  Future<SyncOutcome> syncNow() async {
    final uploader = _saleUploader;
    if (uploader == null) {
      return const SyncOutcome(
        uploaded: 0,
        stillWaiting: 0,
        refreshed: false,
        message: 'Nothing to sync on this device.',
      );
    }

    // Up first: an offline sale exists only here until it lands.
    final pendingBefore = (await _salesRepository.listUnsyncedSales()).length;
    final upload = await uploader.uploadPending();

    // Then down. Ordered by dependency, the same as a pull to refresh: venues
    // and payment methods, then the catalogue, then bazaars, then the sales
    // recorded against their stock.
    //
    // Venues first because bazaars point at them by id, and because this list
    // was previously loaded once at sign-in and never again. A payment method
    // added on the server did not reach the till until the app was restarted,
    // which is exactly the kind of thing nobody thinks to try during a bazaar.
    var refreshed = false;
    try {
      await _settingsRepository.refresh();
      await _productRepository.refresh();
      await _eventRepository.refresh();
      await _salesRepository.refresh();
      refreshed = true;
    } catch (_) {
      // The upload may still have succeeded, and saying so is more useful than
      // reporting a blanket failure that hides it.
      refreshed = false;
    }

    final outcome = SyncOutcome(
      uploaded: upload.uploaded,
      stillWaiting: upload.skipped,
      refreshed: refreshed,
      message: _describe(
        uploaded: upload.uploaded,
        stillWaiting: upload.skipped,
        elsewhere: upload.elsewhere,
        refreshed: refreshed,
        pendingBefore: pendingBefore,
      ),
    );

    await _notificationService.add(type: 'sync', message: outcome.message);
    return outcome;
  }

  /// Phrased for a cashier, and never claiming more than happened.
  static String _describe({
    required int uploaded,
    required int stillWaiting,
    required int elsewhere,
    required bool refreshed,
    required int pendingBefore,
  }) {
    // Mentioned once, plainly, and never as "waiting": nothing here can send
    // them and repeating a number that never goes down teaches a cashier to
    // ignore this message. Said last so it never displaces what did happen.
    final held = elsewhere > 0
        ? ' $elsewhere sale(s) belong to a different server and were not sent.'
        : '';

    if (stillWaiting > 0) {
      return uploaded > 0
          ? 'Sent $uploaded sale(s). $stillWaiting still waiting for a '
                'connection.$held'
          : 'Could not reach the server. '
                '$stillWaiting sale(s) still waiting.$held';
    }
    if (uploaded > 0) {
      return refreshed
          ? 'Sent $uploaded sale(s) and updated from the server.$held'
          : 'Sent $uploaded sale(s), but could not refresh.$held';
    }
    if (!refreshed) {
      return 'Could not reach the server.$held';
    }
    return pendingBefore == 0
        ? 'Up to date.$held'
        : 'Up to date. Everything was already sent.$held';
  }
}

/// What one sync achieved, so the caller can report it rather than guess.
class SyncOutcome {
  const SyncOutcome({
    required this.uploaded,
    required this.stillWaiting,
    required this.refreshed,
    required this.message,
  });

  final int uploaded;

  /// Sales the server still does not hold, usually for want of a connection.
  final int stillWaiting;

  final bool refreshed;

  /// Ready to show a person.
  final String message;

  bool get isComplete => stillWaiting == 0 && refreshed;
}
