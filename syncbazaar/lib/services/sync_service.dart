import '../data/remote/api_service.dart';
import '../data/repositories/approvals_repository.dart';
import '../data/repositories/orders_repository.dart';
import '../data/repositories/sales_repository.dart';
import 'notification_service.dart';

class SyncService {
  SyncService({
    required ApiService apiService,
    required SalesRepository salesRepository,
    required OrdersRepository ordersRepository,
    required ApprovalsRepository approvalsRepository,
    required NotificationService notificationService,
  }) : _apiService = apiService,
       _salesRepository = salesRepository,
       _ordersRepository = ordersRepository,
       _approvalsRepository = approvalsRepository,
       _notificationService = notificationService;

  final ApiService _apiService;
  final SalesRepository _salesRepository;
  final OrdersRepository _ordersRepository;
  final ApprovalsRepository _approvalsRepository;
  final NotificationService _notificationService;

  Future<void> syncNow() async {
    final unsyncedSales = await _salesRepository.listUnsyncedSales();
    final unsyncedOrders = await _ordersRepository.listUnsyncedOrders();
    final pendingApprovals = await _approvalsRepository.listPending();

    final payload = <Map<String, dynamic>>[
      {'sales': unsyncedSales.length},
      {'orders': unsyncedOrders.length},
      {'approvals': pendingApprovals.length},
    ];

    await _apiService.syncPayload(payload);

    await _notificationService.add(
      type: 'sync',
      message:
          'Sync completed: ${unsyncedSales.length} sale(s), ${unsyncedOrders.length} order(s).',
    );
  }
}
