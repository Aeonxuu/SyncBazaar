import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/approvals/approvals_cubit.dart';
import 'bloc/auth/auth_cubit.dart';
import 'bloc/auth/auth_state.dart';
import 'bloc/dashboard/dashboard_cubit.dart';
import 'bloc/inventory/inventory_cubit.dart';
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
import 'models/user.dart';
import 'services/notification_service.dart';
import 'services/dashboard_insights_service.dart';
import 'services/sync_service.dart';
import 'ui/screens/approvals/approvals_screen.dart';
import 'ui/screens/dashboard/dashboard_screen.dart';
import 'ui/screens/inventory/inventory_screen.dart';
import 'ui/screens/login/login_screen.dart';
import 'ui/screens/location/location_screen.dart';
import 'ui/screens/orders/orders_screen.dart';
import 'ui/screens/pos/pos_screen.dart';
import 'ui/screens/post_bazaar/post_bazaar_screen.dart';
import 'ui/screens/pre_bazaar/pre_bazaar_screen.dart';
import 'ui/screens/settings/settings_screen.dart';
import 'ui/screens/staff/staff_screen.dart';
import 'ui/widgets/navigation_rail.dart';
import 'ui/widgets/top_bar.dart';

class SyncBazaarApp extends StatefulWidget {
  const SyncBazaarApp({super.key});

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

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository();
    _eventRepository = EventRepository();
    _productRepository = ProductRepository();
    _salesRepository = SalesRepository();
    _ordersRepository = OrdersRepository();
    _approvalsRepository = ApprovalsRepository();
    _settingsRepository = SettingsRepository();
    _notificationService = NotificationService();
    _syncService = SyncService(
      apiService: ApiService(),
      salesRepository: _salesRepository,
      ordersRepository: _ordersRepository,
      approvalsRepository: _approvalsRepository,
      notificationService: _notificationService,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<EventRepository>.value(value: _eventRepository),
        RepositoryProvider<ProductRepository>.value(value: _productRepository),
        RepositoryProvider<SalesRepository>.value(value: _salesRepository),
        RepositoryProvider<OrdersRepository>.value(value: _ordersRepository),
        RepositoryProvider<SettingsRepository>.value(value: _settingsRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AuthCubit(_authRepository),
          ),
          BlocProvider(
            create: (_) => DashboardCubit(
              _eventRepository,
              _salesRepository,
              insightsService: const LocalDashboardInsightsService(),
            ),
          ),
          BlocProvider(
            create: (_) => PosCubit(
              _eventRepository,
              _productRepository,
              _salesRepository,
              _ordersRepository,
              _settingsRepository,
            ),
          ),
          BlocProvider(
            create: (_) => OrdersCubit(
              _ordersRepository,
              _salesRepository,
            )..load(),
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
            create: (_) => InventoryCubit(_productRepository)..load(),
          ),
          BlocProvider(create: (_) => StaffCubit(_authRepository)..load()),
          BlocProvider(
            create: (_) => SettingsCubit(_settingsRepository)..load(),
          ),
          BlocProvider(create: (_) => PreBazaarCubit(_approvalsRepository)),
          BlocProvider(create: (_) => SyncCubit(_syncService)),
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
        if (state.isLoading && !state.isAuthenticated) {
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
  int _selectedIndex = 0;
  bool _isNavCollapsed = false;

  late List<AppNavItem> _navItems;

  @override
  void initState() {
    super.initState();
    _navItems = _buildNavItems(widget.user);
    _loadForUser();
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id) {
      _navItems = _buildNavItems(widget.user);
      _selectedIndex = 0;
      _loadForUser();
    }
  }

  void _loadForUser() {
    context.read<DashboardCubit>().load(widget.user);
    context.read<PosCubit>().load(widget.user);
  }

  void _handleSectionSelect(int index) {
    setState(() => _selectedIndex = index);
    final section = _navItems[index].section;
    if (section == AppSection.dashboard) {
      context.read<DashboardCubit>().load(widget.user);
    }
    if (section == AppSection.pos) {
      context.read<PosCubit>().load(widget.user);
    }
    if (section == AppSection.orders) {
      context.read<OrdersCubit>().load();
    }
    if (section == AppSection.approvals) {
      context.read<ApprovalsCubit>().loadPending();
    }
  }

  List<AppNavItem> _buildNavItems(AppUser user) {
    final canApprove = user.isAdminOrOwner;
    return [
      const AppNavItem(
        section: AppSection.dashboard,
        label: 'Dashboard',
        icon: Icons.home_outlined,
      ),
      const AppNavItem(
        section: AppSection.inventory,
        label: 'Master Inventory',
        icon: Icons.inventory_2_outlined,
      ),
      const AppNavItem(
        section: AppSection.preBazaar,
        label: 'Preparations',
        icon: Icons.event_note_outlined,
      ),
      const AppNavItem(
        section: AppSection.pos,
        label: 'POS',
        icon: Icons.point_of_sale_outlined,
      ),
      const AppNavItem(
        section: AppSection.postBazaar,
        label: 'Documentation',
        icon: Icons.summarize_outlined,
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
      if (canApprove)
        const AppNavItem(
          section: AppSection.staff,
          label: 'Staff List',
          icon: Icons.groups_2_outlined,
        ),
      if (canApprove)
        const AppNavItem(
          section: AppSection.location,
          label: 'Location',
          icon: Icons.place_outlined,
        ),
      const AppNavItem(
        section: AppSection.settings,
        label: 'Settings',
        icon: Icons.settings_outlined,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final section = _navItems[_selectedIndex].section;

    return Scaffold(
      resizeToAvoidBottomInset:
          section != AppSection.pos && section != AppSection.staff,
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          SideNavigationRail(
            items: _navItems,
            selectedIndex: _selectedIndex,
            onSelect: _handleSectionSelect,
            isCollapsed: _isNavCollapsed,
            onToggle: () => setState(() => _isNavCollapsed = !_isNavCollapsed),
          ),
          Expanded(
            child: Column(
              children: [
                TopBar(
                  user: widget.user,
                  notificationCount: widget.user.isAdminOrOwner ? 2 : 1,
                  onOpenNotifications: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          widget.user.isAdminOrOwner
                              ? 'New pending approvals available.'
                              : 'New assignment/sync notifications.',
                        ),
                      ),
                    );
                  },
                  onLogout: () => context.read<AuthCubit>().logout(),
                ),
                Expanded(child: _buildSection(section)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(AppSection section) {
    switch (section) {
      case AppSection.dashboard:
        return DashboardScreen(
          user: widget.user,
          onOpenPos: () {
            final index = _navItems.indexWhere(
              (i) => i.section == AppSection.pos,
            );
            if (index != -1) setState(() => _selectedIndex = index);
          },
        );
      case AppSection.preBazaar:
        return PreBazaarScreen(
          user: widget.user,
          onOpenApprovals: () {
            final index = _navItems.indexWhere(
              (i) => i.section == AppSection.approvals,
            );
            if (index != -1) {
              setState(() => _selectedIndex = index);
              context.read<ApprovalsCubit>().loadPending();
            }
          },
        );
      case AppSection.pos:
        return PosScreen(user: widget.user);
      case AppSection.postBazaar:
        return const PostBazaarScreen();
      case AppSection.orders:
        return OrdersScreen(user: widget.user);
      case AppSection.approvals:
        return const ApprovalsScreen();
      case AppSection.inventory:
        return InventoryScreen(user: widget.user);
      case AppSection.staff:
        return StaffScreen(currentUser: widget.user);
      case AppSection.settings:
        return SettingsScreen(user: widget.user);
      case AppSection.location:
        return LocationScreen(user: widget.user);
    }
  }
}
