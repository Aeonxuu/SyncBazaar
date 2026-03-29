import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../bloc/inventory/inventory_cubit.dart';
import '../../../bloc/pos/pos_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/user.dart';
import 'widgets/create_bazaar_card.dart';
import 'widgets/stock_allocation_card.dart';

class PreBazaarScreen extends StatefulWidget {
  const PreBazaarScreen({
    super.key,
    required this.user,
    required this.onOpenApprovals,
  });

  final AppUser user;
  final VoidCallback onOpenApprovals;

  @override
  State<PreBazaarScreen> createState() => _PreBazaarScreenState();
}

class _PreBazaarScreenState extends State<PreBazaarScreen> {
  final _eventName = TextEditingController();
  DateTimeRange? _dateRange;
  int? _selectedCompanyId = 1;
  bool? _stockAllocationUnlocked;
  final Map<String, int> _allocations = {};
  final Map<String, int> _masterStockByItem = {};
  final Map<String, int> _availableStockAtDraftStart = {};
  final Map<String, ProductAllocationItem> _allocationMetaByKey = {};
  final Set<String> _acceptedPaymentMethods = {'CASH', 'COOP'};
  final List<BazaarPaymentMethod> _customOtherMethods = [];
  final TextEditingController _otherPaymentMethodController =
      TextEditingController();
  bool _otherRequiresEmployeeId = false;

  final List<DropdownMenuItem<int>> _companyItems = const [
    DropdownMenuItem<int>(value: 1, child: Text('Amkor Technology')),
    DropdownMenuItem<int>(value: 2, child: Text('Shin-Etsu')),
  ];

  @override
  void initState() {
    super.initState();
    _stockAllocationUnlocked = false;
    _eventName.addListener(_onEventNameChanged);
    Future.microtask(_syncStocksFromRepository);
  }

  void _onEventNameChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _eventName.removeListener(_onEventNameChanged);
    _eventName.dispose();
    _otherPaymentMethodController.dispose();
    super.dispose();
  }

  bool get _isBazaarInfoComplete {
    final eventNameOk = _eventName.text.trim().isNotEmpty;
    final companyOk = _selectedCompanyId != null;
    final dateOk = _dateRange != null;
    final paymentOk = _acceptedPaymentMethods.isNotEmpty;
    final otherOk = !_acceptedPaymentMethods.contains('OTHER') ||
        _customOtherMethods.isNotEmpty;
    return eventNameOk && companyOk && dateOk && paymentOk && otherOk;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final range = await showDateRangePicker(
      context: context,
      firstDate: tomorrow,
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
      selectableDayPredicate: (day, _, __) => day.isAfter(today),
    );
    if (range != null) {
      final startDate = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final endDate = DateTime(range.end.year, range.end.month, range.end.day);

      if (!startDate.isAfter(today) || !endDate.isAfter(today)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select dates after today.')),
          );
        }
        return;
      }

      setState(() => _dateRange = range);
    }
  }

  void _resetCreateBazaar() {
    setState(() {
      _eventName.clear();
      _dateRange = null;
      _selectedCompanyId = _companyItems.first.value;
      _stockAllocationUnlocked = false;
      _acceptedPaymentMethods
        ..clear()
        ..addAll({'CASH', 'COOP'});
      _customOtherMethods.clear();
      _otherPaymentMethodController.clear();
      _otherRequiresEmployeeId = false;
    });
  }

  void _resetAllocation() {
    setState(() {
      _allocations.updateAll((_, __) => 0);
      _masterStockByItem
        ..clear()
        ..addAll(_availableStockAtDraftStart);
    });
  }

  Future<void> _resetPreBazaarForm() async {
    setState(() {
      _eventName.clear();
      _dateRange = null;
      _selectedCompanyId = _companyItems.first.value;
      _stockAllocationUnlocked = false;
      _allocations.updateAll((_, __) => 0);
      _masterStockByItem.clear();
      _acceptedPaymentMethods
        ..clear()
        ..addAll({'CASH', 'COOP'});
      _customOtherMethods.clear();
      _otherPaymentMethodController.clear();
      _otherRequiresEmployeeId = false;
    });
    await _syncStocksFromRepository();
  }

  void _togglePaymentMethod(String method, bool enabled) {
    setState(() {
      if (enabled) {
        _acceptedPaymentMethods.add(method);
      } else {
        _acceptedPaymentMethods.remove(method);
        if (method == 'OTHER') {
          _customOtherMethods.clear();
        }
      }
    });
  }

  void _addOtherMethod() {
    final name = _otherPaymentMethodController.text.trim();
    if (name.isEmpty) {
      return;
    }
    final exists = _customOtherMethods.any(
      (method) => method.name.trim().toUpperCase() == name.toUpperCase(),
    );
    if (exists) {
      return;
    }

    setState(() {
      _customOtherMethods.add(
        BazaarPaymentMethod(
          name: name,
          requiresEmployeeId: _otherRequiresEmployeeId,
        ),
      );
      _otherPaymentMethodController.clear();
      _otherRequiresEmployeeId = false;
    });
  }

  void _removeOtherMethod(String name) {
    setState(() {
      _customOtherMethods.removeWhere((method) => method.name == name);
    });
  }

  void _handleAllocationChanged(String itemKey, int requestedValue) {
    final maxForItem = _availableStockAtDraftStart[itemKey] ?? 0;
    final nextAllocation = requestedValue.clamp(0, maxForItem);

    setState(() {
      _allocations[itemKey] = nextAllocation;
      _masterStockByItem[itemKey] = maxForItem - nextAllocation;
    });
  }

  Future<void> _syncStocksFromRepository() async {
    final productRepository = context.read<ProductRepository>();
    final stockByAllocationKey = await productRepository.stockByAllocationKey();
    final items = await productRepository.allocationItems();

    if (!mounted) {
      return;
    }

    setState(() {
      _allocationMetaByKey
        ..clear()
        ..addEntries(items.map((item) => MapEntry(item.allocationKey, item)));

      for (final item in items) {
        _allocations.putIfAbsent(item.allocationKey, () => 0);
      }
      _allocations.removeWhere((key, _) => !_allocationMetaByKey.containsKey(key));

      _availableStockAtDraftStart
        ..clear()
        ..addAll(stockByAllocationKey);
      _masterStockByItem
        ..clear()
        ..addAll(_availableStockAtDraftStart);
    });
  }

  void _onNextFromCreate() {
    if (!_isBazaarInfoComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete all Create Bazaar fields before proceeding.'),
        ),
      );
      return;
    }

    setState(() {
      _stockAllocationUnlocked = true;
    });
  }

  Future<void> _handleSubmit() async {
    if (!widget.user.isAdminOrOwner) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Submission'),
          content: const Text(
            'Submit this stock allocation for admin/owner approval?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      );

      if (approved == true && mounted) {
        widget.onOpenApprovals();
      }
      return;
    }

    if (!_isBazaarInfoComplete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete event name, company, and event dates before finishing.',
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm Bazaar Publish',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Please confirm all event information is correct before publishing this bazaar.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                    child: const Text('Review'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('Publish'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final eventRepository = context.read<EventRepository>();
      final productRepository = context.read<ProductRepository>();
      final settingsRepository = context.read<SettingsRepository>();

      final allocationsByAllocationKey = <String, int>{};
      for (final entry in _allocations.entries) {
        if (entry.value > 0) {
          allocationsByAllocationKey[entry.key] = entry.value;
        }
      }

      final reserved = await productRepository.reserveStocksByAllocationKey(
        allocationsByAllocationKey,
      );

      if (!reserved) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to reserve stock. Please review allocations and try again.',
              ),
            ),
          );
        }
        return;
      }

      await eventRepository.createEvent(
        name: _eventName.text.trim(),
        companyId: _selectedCompanyId ?? _companyItems.first.value ?? 1,
        startDate: _dateRange!.start,
        endDate: _dateRange!.end,
        acceptedPaymentMethods: _acceptedPaymentMethods.toList(),
        customOtherMethods: _customOtherMethods,
        allocationsByAllocationKey: allocationsByAllocationKey,
      );

      for (final custom in _customOtherMethods) {
        await settingsRepository.upsertPaymentMethod(
          PaymentMethodMeta(
            name: custom.name,
            requiresEmployeeId: custom.requiresEmployeeId,
          ),
        );
      }

      if (!mounted) {
        return;
      }

      await context.read<DashboardCubit>().load(widget.user);
      await context.read<PosCubit>().load(widget.user);
      await context.read<InventoryCubit>().load();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bazaar published successfully.')),
      );
      await _resetPreBazaarForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdminOrOwner = widget.user.isAdminOrOwner;
    final canGoNext = _isBazaarInfoComplete;
    final isStockAllocationUnlocked = _stockAllocationUnlocked ?? false;
    final canUseStockAllocation = isStockAllocationUnlocked;
    final canFinish = canUseStockAllocation && _isBazaarInfoComplete;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSideBySide = constraints.maxWidth >= 760;

          final createCard = CreateBazaarCard(
            eventNameController: _eventName,
            selectedCompanyId: _selectedCompanyId,
            companyItems: _companyItems,
            dateRange: _dateRange,
            acceptedPaymentMethods: _acceptedPaymentMethods,
            onPaymentMethodToggled: _togglePaymentMethod,
            otherPaymentMethodController: _otherPaymentMethodController,
            otherRequiresEmployeeId: _otherRequiresEmployeeId,
            onOtherRequiresEmployeeIdChanged: (value) {
              setState(() {
                _otherRequiresEmployeeId = value;
              });
            },
            onAddOtherMethod: _addOtherMethod,
            customOtherMethods: _customOtherMethods,
            onRemoveOtherMethod: _removeOtherMethod,
            onCompanyChanged: (value) =>
                setState(() => _selectedCompanyId = value),
            onPickDates: _pickDateRange,
            onCancel: _resetCreateBazaar,
            onNext: _onNextFromCreate,
            isNextEnabled: canGoNext,
          );

          final grouped = <int, StockAllocationGroup>{};
          for (final entry in _allocationMetaByKey.entries) {
            final itemKey = entry.key;
            final meta = entry.value;
            final existing = grouped[meta.product.id];
            final label = (meta.group == null || meta.option == null)
                ? meta.product.name
                : '${meta.group!.name} ${meta.option!.value}';
            final row = StockAllocationRow(
              key: itemKey,
              label: label,
              allocated: _allocations[itemKey] ?? 0,
              remaining: _masterStockByItem[itemKey] ?? 0,
            );

            if (existing == null) {
              grouped[meta.product.id] = StockAllocationGroup(
                productName: meta.product.name,
                rows: [row],
              );
            } else {
              grouped[meta.product.id] = StockAllocationGroup(
                productName: existing.productName,
                rows: [...existing.rows, row],
              );
            }
          }

          final allocationCard = StockAllocationCard(
            groups: grouped.values.toList(),
            isAdminOrOwner: isAdminOrOwner,
            isAllocationEnabled: canUseStockAllocation,
            onAllocationChanged: _handleAllocationChanged,
            onCancel: _resetAllocation,
            onSubmit: _handleSubmit,
            isSubmitEnabled: canFinish,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pre-Bazaar',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                isAdminOrOwner
                    ? 'Prepare your event and allocate stock before launch.'
                    : 'Allocate stock and submit for approval before launch.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              if (showSideBySide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: createCard),
                      const SizedBox(width: 14),
                      Expanded(child: allocationCard),
                    ],
                  ),
                )
              else ...[
                createCard,
                const SizedBox(height: 14),
                allocationCard,
              ],
            ],
          );
        },
      ),
    );
  }
}
