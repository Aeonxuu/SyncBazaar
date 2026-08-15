import 'package:flutter/foundation.dart';

import 'core/config/api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/approvals/approvals_cubit.dart';
import 'bloc/auth/auth_cubit.dart';
import 'bloc/auth/auth_state.dart';
import 'bloc/dashboard/dashboard_cubit.dart';
import 'bloc/inventory/inventory_cubit.dart';
import 'bloc/notifications/notifications_cubit.dart';
import 'bloc/orders/orders_cubit.dart';
import 'bloc/pos/pos_cubit.dart';
import 'bloc/pre_bazaar/pre_bazaar_cubit.dart';
import 'bloc/settings/settings_cubit.dart';
import 'bloc/staff/staff_cubit.dart';
import 'bloc/sync/sync_cubit.dart';
import 'core/constants/colors.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/remote/api_service.dart';
import 'data/repositories/approvals_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/event_repository.dart';
import 'data/repositories/orders_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/sales_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'dev/dev_mock_data_seeder.dart';
import 'models/approval_request.dart';
import 'models/user.dart';
import 'services/notification_service.dart';
import 'services/sale_upload_service.dart';
import 'services/sync_service.dart';
import 'ui/screens/approvals/approvals_screen.dart';
import 'ui/screens/dashboard/dashboard_screen.dart';
import 'ui/screens/inventory/inventory_screen.dart';
import 'ui/screens/login/login_screen.dart';
import 'ui/screens/notifications/notifications_screen.dart';
import 'ui/screens/venues/venues_screen.dart';
import 'ui/screens/orders/orders_screen.dart';
import 'ui/screens/pos/pos_screen.dart';
import 'ui/screens/pos/widgets/discard_sale_guard.dart';
import 'ui/screens/post_bazaar/post_bazaar_screen.dart';
import 'ui/screens/pre_bazaar/pre_bazaar_screen.dart';
import 'ui/screens/settings/settings_screen.dart';
import 'ui/screens/staff/staff_screen.dart';
import 'ui/widgets/navigation_rail.dart';

class SyncBazaarApp extends StatefulWidget {
  const SyncBazaarApp({
    super.key,
    this.seedMockData = kDebugMode && !ApiConfig.useBackend,
  });

  /// Whether to load `assets/dev/mock_data.json` on boot.
  ///
  /// Defaults to on in debug builds and off in release, which is what the app
  /// itself always wants — except when the build is pointed at the backend, in
  /// which case seeding is off in debug too and the repositories read from the
  /// server instead. Otherwise the tablet would show every product twice, once
  /// from each source.
  ///
  /// It is also a parameter for widget tests: the
  /// seeder reads the asset through `rootBundle`, and that is real I/O which
  /// never completes inside `testWidgets`' fake-async zone — so a test that
  /// boots the app with seeding on hangs in `pumpAndSettle` until it times
  /// out. Passing `false` lets a test exercise the real widget tree without
  /// waiting on a load that, by construction, cannot finish.
  final bool seedMockData;

  @override
  State<SyncBazaarApp> createState() => _SyncBazaarAppState();
}

class _SyncBazaarAppState extends State<SyncBazaarApp> {
  late final AuthRepository _authRepository;
  late final EventRepository _eventRepository;
  late final ProductRepository _productRepository;
  late final SalesRepository _salesRepository;
  late final OrdersRepository _ordersRepository;
  late final ApprovalsRepository _approvalsRepository;
  late final SettingsRepository _settingsRepository;
  late final NotificationService _notificationService;
  late final SyncService _syncService;
  SaleUploadService? _saleUploader;
  late bool _seeding;

  @override
  void initState() {
    super.initState();
    _seeding = widget.seedMockData;
    _authRepository = AuthRepository();
    // Handed the session rather than an API client: the vendor whose data to
    // fetch is only known once someone signs in, and these are built before
    // that. Without it both stay in memory and the seeder fills them as before.
    //
    // Keyed on the build flag rather than on `seedMockData`, which those are
    // not the same question. Widget tests boot with seeding off to avoid the
    // asset load, and tying the two together silently pointed them at a live
    // server — a test suite has no business making HTTP requests.
    final session = ApiConfig.useBackend ? _authRepository : null;
    _productRepository = ProductRepository(auth: session);
    _eventRepository = EventRepository(
      auth: session,
      products: _productRepository,
    );
    // Built after events, which it needs to turn a sale's stock row back into
    // the combination it was sold from.
    _salesRepository = SalesRepository(auth: session, events: _eventRepository);
    _ordersRepository = OrdersRepository();
    // Null without a backend, so the in-memory build behaves exactly as before
    // and the POS has nothing to push to.
    _saleUploader = session == null
        ? null
        : SaleUploadService(
            auth: session,
            events: _eventRepository,
            products: _productRepository,
            sales: _salesRepository,
          );
    _approvalsRepository = ApprovalsRepository(
      auth: _authRepository,
      events: _eventRepository,
    );
    _settingsRepository = SettingsRepository(auth: session);
    _notificationService = NotificationService();
    _syncService = SyncService(
      apiService: ApiService(),
      salesRepository: _salesRepository,
      ordersRepository: _ordersRepository,
      approvalsRepository: _approvalsRepository,
      notificationService: _notificationService,
    );
    if (widget.seedMockData) {
      _seedMockData();
    }
  }

  Future<void> _seedMockData() async {
    await DevMockDataSeeder(
      eventRepository: _eventRepository,
      productRepository: _productRepository,
      salesRepository: _salesRepository,
      ordersRepository: _ordersRepository,
      settingsRepository: _settingsRepository,
      authRepository: _authRepository,
    ).seed();
    if (mounted) {
      setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_seeding) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: _authRepository),
        RepositoryProvider<EventRepository>.value(value: _eventRepository),
        RepositoryProvider<ProductRepository>.value(value: _productRepository),
        RepositoryProvider<SalesRepository>.value(value: _salesRepository),
        RepositoryProvider<OrdersRepository>.value(value: _ordersRepository),
        RepositoryProvider<SettingsRepository>.value(
          value: _settingsRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          // Restored immediately, otherwise the saved session is written on
          // every login and read by nobody: `restoreSession` existed but had no
          // caller, so "remember me" never survived a relaunch.
          BlocProvider(
            create: (_) => AuthCubit(_authRepository)..restoreSession(),
          ),
          BlocProvider(
            create: (_) => DashboardCubit(
              _eventRepository,
              _salesRepository,
              productRepository: _productRepository,
            ),
          ),
          BlocProvider(
            create: (_) => PosCubit(
              _eventRepository,
              _productRepository,
              _salesRepository,
              _ordersRepository,
              _settingsRepository,
              saleUploader: _saleUploader,
            ),
          ),
          BlocProvider(
            create: (_) =>
                OrdersCubit(_salesRepository, _productRepository)..load(),
          ),
          BlocProvider(
            create: (_) => ApprovalsCubit(
              _approvalsRepository,
              _eventRepository,
              _productRepository,
              _authRepository,
            )..loadPending(),
          ),
          BlocProvider(
            create: (_) =>
                InventoryCubit(_productRepository, _salesRepository)..load(),
          ),
          BlocProvider(create: (_) => StaffCubit(_authRepository)..load()),
          BlocProvider(
            create: (_) => SettingsCubit(_settingsRepository)..load(),
          ),
          BlocProvider(
            create: (_) =>
                PreBazaarCubit(_approvalsRepository, _eventRepository),
          ),
          BlocProvider(create: (_) => SyncCubit(_syncService)),
          BlocProvider(
            create: (_) => NotificationsCubit(_notificationService)..load(),
          ),
        ],
        child: MaterialApp(
          title: 'SyncBazaar',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        // Only the startup session read replaces the screen. A sign-in in
        // flight must not: swapping the login form out for a spinner disposes
        // its controllers, so a rejected password came back to an empty form,
        // and the rebuilt screen subscribed too late to ever show the error.
        // The form reports its own progress on the button instead.
        if (state.isRestoring && !state.isAuthenticated) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!state.isAuthenticated) {
          return const LoginScreen();
        }
        return MainShell(user: state.user!);
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.user});

  final AppUser user;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppSection _section = AppSection.dashboard;
  bool _isNavCollapsed = false;

  late List<AppNavGroup> _navGroups;

  @override
  void initState() {
    super.initState();
    _navGroups = _buildNavGroups(widget.user);
    _loadForUser();
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id) {
      _navGroups = _buildNavGroups(widget.user);
      _section = AppSection.dashboard;
      _loadForUser();
    }
  }

  void _loadForUser() {
    context.read<DashboardCubit>().load(widget.user);
    context.read<PosCubit>().load(widget.user);
    context.read<NotificationsCubit>().load();
  }

  Future<void> _handleSectionSelect(AppSection section) async {
    // Leaving the POS mid-sale discards the cart, and the rail is the easiest
    // way to do it by accident — one stray tap while a customer waits. Asked
    // here rather than inside the POS because the rail sits outside it and the
    // section has already changed by the time the POS could react.
    if (section != _section && _section == AppSection.pos) {
      if (!await confirmLeavingSale(context)) {
        return;
      }
      if (!mounted) {
        return;
      }
    }

    setState(() => _section = section);
    switch (section) {
      case AppSection.dashboard:
        context.read<DashboardCubit>().load(widget.user);
      case AppSection.pos:
        context.read<PosCubit>().load(widget.user);
      case AppSection.orders:
        context.read<OrdersCubit>().load();
      case AppSection.approvals:
        context.read<ApprovalsCubit>().loadPending();
      case AppSection.notifications:
        context.read<NotificationsCubit>().load();
      // Reloaded like the rest. Without this the catalogue showed whatever it
      // held at launch, so returning a bazaar's unsold stock moved the figures
      // on the server and left this screen insisting nothing had happened --
      // the one screen where the whole point is the number.
      case AppSection.inventory:
        context.read<InventoryCubit>().load();
      case AppSection.staff:
        context.read<StaffCubit>().load();
      default:
        break;
    }
  }

  /// Destinations grouped by when in the job they are needed, rather than as
  /// one flat list. See [SideNavigationRail] for why.
  ///
  /// Role gating happens per item, so a group can come back with one entry or
  /// none; the rail drops the heading in the first case and the whole block in
  /// the second.
  List<AppNavGroup> _buildNavGroups(AppUser user) {
    final canApprove = user.isAdminOrOwner;
    final isOwner = user.role == UserRole.owner;

    final groups = <AppNavGroup>[
      const AppNavGroup(
        items: [
          AppNavItem(
            section: AppSection.dashboard,
            label: 'Dashboard',
            icon: Icons.home_outlined,
          ),
          AppNavItem(
            section: AppSection.notifications,
            label: 'Notifications',
            icon: Icons.notifications_outlined,
          ),
        ],
      ),
      // Ordered the way a bazaar actually runs — set up, sell, close out. The
      // sequence is itself information: it tells a new employee what comes
      // next without anyone documenting it.
      const AppNavGroup(
        label: 'Bazaar',
        items: [
          AppNavItem(
            section: AppSection.preBazaar,
            label: 'Preparations',
            icon: Icons.event_note_outlined,
          ),
          AppNavItem(
            section: AppSection.pos,
            label: 'Sales',
            icon: Icons.point_of_sale_outlined,
          ),
          AppNavItem(
            section: AppSection.postBazaar,
            label: 'Documentation',
            icon: Icons.summarize_outlined,
          ),
        ],
      ),
      AppNavGroup(
        label: 'Records',
        items: [
          if (isOwner)
            const AppNavItem(
              section: AppSection.inventory,
              label: 'Master Inventory',
              icon: Icons.inventory_2_outlined,
            ),
          const AppNavItem(
            section: AppSection.orders,
            label: 'Orders',
            icon: Icons.receipt_long_outlined,
          ),
          if (canApprove)
            const AppNavItem(
              section: AppSection.approvals,
              label: 'Pending Approvals',
              icon: Icons.pending_actions_outlined,
            ),
        ],
      ),
      AppNavGroup(
        label: 'Manage',
        items: [
          if (canApprove) ...[
            const AppNavItem(
              section: AppSection.staff,
              label: 'Staff List',
              icon: Icons.groups_2_outlined,
            ),
            const AppNavItem(
              section: AppSection.venues,
              label: 'Venues & Terms',
              icon: Icons.storefront_outlined,
            ),
          ],
          const AppNavItem(
            section: AppSection.settings,
            label: 'Settings',
            icon: Icons.settings_outlined,
          ),
        ],
      ),
    ];

    return groups.where((group) => group.items.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final section = _section;

    return Scaffold(
      resizeToAvoidBottomInset:
          section != AppSection.pos && section != AppSection.staff,
      backgroundColor: AppColors.background,
      // A sync writes a notification, so the badge has to re-read the store
      // when one finishes. Without this the count only catches up the next
      // time something else happens to reload it.
      body: BlocListener<SyncCubit, SyncState>(
        listenWhen: (previous, current) =>
            previous.isSyncing && !current.isSyncing,
        listener: (context, _) => context.read<NotificationsCubit>().load(),
        child: Row(
          children: [
            BlocBuilder<SyncCubit, SyncState>(
              builder: (context, syncState) =>
                  BlocBuilder<NotificationsCubit, NotificationsState>(
                    builder: (context, notificationsState) =>
                        BlocBuilder<ApprovalsCubit, List<ApprovalRequest>>(
                          builder: (context, pendingApprovals) =>
                              SideNavigationRail(
                                groups: _navGroups,
                                selected: section,
                                onSelect: _handleSectionSelect,
                                isCollapsed: _isNavCollapsed,
                                onToggle: () => setState(
                                  () => _isNavCollapsed = !_isNavCollapsed,
                                ),
                                onLogout: () =>
                                    context.read<AuthCubit>().logout(),
                                isSyncing: syncState.isSyncing,
                                onSync: () =>
                                    context.read<SyncCubit>().syncNow(),
                                syncMessage: syncState.lastMessage,
                                badges: {
                                  AppSection.notifications:
                                      notificationsState.unreadCount,
                                  if (widget.user.isAdminOrOwner)
                                    AppSection.approvals:
                                        pendingApprovals.length,
                                },
                              ),
                        ),
                  ),
            ),
            Expanded(child: _buildSection(section)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(AppSection section) {
    switch (section) {
      case AppSection.dashboard:
        return DashboardScreen(
          user: widget.user,
          onOpenPos: () => _handleSectionSelect(AppSection.pos),
        );
      case AppSection.preBazaar:
        return PreBazaarScreen(
          user: widget.user,
          onOpenApprovals: () => _handleSectionSelect(AppSection.approvals),
        );
      case AppSection.pos:
        return PosScreen(user: widget.user);
      case AppSection.postBazaar:
        return PostBazaarScreen(user: widget.user);
      case AppSection.orders:
        return OrdersScreen(user: widget.user);
      case AppSection.approvals:
        return ApprovalsScreen(user: widget.user);
      case AppSection.inventory:
        return InventoryScreen(user: widget.user);
      case AppSection.staff:
        return StaffScreen(currentUser: widget.user);
      case AppSection.settings:
        return SettingsScreen(user: widget.user);
      case AppSection.venues:
        return VenuesScreen(user: widget.user);
      case AppSection.notifications:
        return const NotificationsScreen();
    }
  }
}
