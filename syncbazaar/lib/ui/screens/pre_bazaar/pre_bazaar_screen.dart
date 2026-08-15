import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';

import '../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../bloc/inventory/inventory_cubit.dart';
import '../../../bloc/orders/orders_cubit.dart';
import '../../../bloc/pos/pos_cubit.dart';
import '../../../bloc/pre_bazaar/pre_bazaar_cubit.dart';
import '../../../bloc/staff/staff_cubit.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/company.dart';
import '../../../models/user.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart';
import 'widgets/bazaar_details_step.dart';
import 'widgets/stock_allocation_step.dart';

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

  /// 0 = details, 1 = stock allocation. Replaces the old
  /// `_stockAllocationUnlocked` flag: the relationship between the two halves
  /// was always sequential, and naming it as a step makes that visible to the
  /// user instead of expressing it as a greyed-out panel beside a live one.
  int _step = 0;
  final _allocationSearch = TextEditingController();
  final Map<String, int> _allocations = {};
  final Map<String, int> _masterStockByItem = {};
  final Map<String, int> _availableStockAtDraftStart = {};
  final Map<String, ProductAllocationItem> _allocationMetaByKey = {};
  final Set<int> _assignedEmployeeIds = {};
  List<Company> _locations = const [];
  Map<int, List<PaymentMethodMeta>> _locationPaymentMethodsByCompanyId =
      const {};

  @override
  void initState() {
    super.initState();
    _eventName.addListener(_onEventNameChanged);
    Future.microtask(() async {
      await _syncLocationsFromRepository();
      await _syncStocksFromRepository();
    });
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
    _allocationSearch.dispose();
    super.dispose();
  }

  List<PaymentMethodMeta> get _selectedLocationPaymentMethods {
    if (_selectedCompanyId == null) {
      return const [];
    }
    return _locationPaymentMethodsByCompanyId[_selectedCompanyId!] ?? const [];
  }

  bool get _isBazaarInfoComplete {
    final eventNameOk = _eventName.text.trim().isNotEmpty;
    final companyOk = _selectedCompanyId != null;
    final dateOk = _dateRange != null;
    final paymentOk = _selectedLocationPaymentMethods.isNotEmpty;
    return eventNameOk && companyOk && dateOk && paymentOk;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Today counts. A stall that opens this morning is the ordinary case at a
    // pop-up, not an exception -- the calendar used to start tomorrow, which
    // made a same-day bazaar impossible to enter at all. Yesterday still is:
    // a bazaar cannot be planned into the past.
    final range = await showAppDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(2030, 12, 31),
      initialRange: _dateRange,
      title: 'Event dates',
    );
    if (range != null && mounted) {
      setState(() => _dateRange = range);
    }
  }

  Future<void> _resetPreBazaarForm() async {
    setState(() {
      _eventName.clear();
      _dateRange = null;
      _selectedCompanyId = _locations.isEmpty ? null : _locations.first.id;
      _step = 0;
      _allocationSearch.clear();
      _allocations.updateAll((_, __) => 0);
      _masterStockByItem.clear();
      _assignedEmployeeIds.clear();
    });
    await _syncLocationsFromRepository();
    await _syncStocksFromRepository();
  }

  Future<void> _syncLocationsFromRepository() async {
    final settingsRepository = context.read<SettingsRepository>();
    final locations = await settingsRepository.listCompanies();
    final methodsByCompanyId = await settingsRepository
        .paymentMethodsByCompanyId();

    if (!mounted) {
      return;
    }

    setState(() {
      _locations = locations;
      _locationPaymentMethodsByCompanyId = methodsByCompanyId;

      if (_selectedCompanyId == null ||
          !_locations.any((location) => location.id == _selectedCompanyId)) {
        _selectedCompanyId = _locations.isEmpty ? null : _locations.first.id;
      }
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
      _allocations.removeWhere(
        (key, _) => !_allocationMetaByKey.containsKey(key),
      );

      _availableStockAtDraftStart
        ..clear()
        ..addAll(stockByAllocationKey);
      _masterStockByItem
        ..clear()
        ..addAll(_availableStockAtDraftStart);
    });
  }

  /// Advances to allocation. The button is disabled until the details are
  /// complete and the step itself lists what's outstanding, so this never has
  /// to reject a tap with an error.
  void _goToAllocation() {
    if (!_isBazaarInfoComplete) return;
    setState(() => _step = 1);
  }

  Future<void> _handleSubmit() async {
    if (!widget.user.isAdminOrOwner) {
      if (!_isBazaarInfoComplete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Complete event name, venue, and event dates before submitting.',
              ),
            ),
          );
        }
        return;
      }

      final approved = await showConfirmationDialog(
        context: context,
        title: 'Confirm Submission',
        message: 'Submit this stock allocation for admin/owner approval?',
        confirmLabel: 'Submit',
      );

      if (approved == true && mounted) {
        final selectedMethods = _selectedLocationPaymentMethods;
        final locationName =
            _locations
                .where((location) => location.id == _selectedCompanyId)
                .map((location) => location.name)
                .cast<String?>()
                .firstWhere((value) => value != null, orElse: () => null) ??
            'Unknown venue';
        final allocationsByAllocationKey = <String, int>{
          for (final entry in _allocations.entries)
            if (entry.value > 0) entry.key: entry.value,
        };

        final selectedAllocations = _allocations.entries
            .where((entry) => entry.value > 0)
            .toList();

        if (selectedAllocations.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Add at least one allocated quantity before submitting.',
              ),
            ),
          );
          return;
        }

        final allocationItems = selectedAllocations.map((entry) {
          final meta = _allocationMetaByKey[entry.key];
          final product = meta?.product;
          final variantValues = [
            meta?.optionA?.value,
            meta?.optionB?.value,
          ].whereType<String>().toList();
          return {
            'name': product?.name ?? entry.key,
            'variant': variantValues.isEmpty ? '—' : variantValues.join(', '),
            // The raw number, not a formatted string: this goes into the
            // request's detailsJson, and the approvals table formats it when
            // it renders. Baking the display format in at encode time is how
            // the price ended up as the one unseparated amount in the app.
            'price': product?.basePrice,
            'qty': entry.value,
          };
        }).toList();

        final details = jsonEncode({
          'eventName': _eventName.text.trim(),
          'locationName': locationName,
          'companyId': _selectedCompanyId,
          'dateStart': _dateRange?.start.toIso8601String(),
          'dateEnd': _dateRange?.end.toIso8601String(),
          'acceptedPaymentMethods': selectedMethods
              .map((method) => method.name)
              .toList(),
          'customOtherMethods': selectedMethods
              .map(
                (method) => {
                  'name': method.name,
                  'extraFieldLabel': method.extraFieldLabel,
                },
              )
              .toList(),
          'allocationsByAllocationKey': allocationsByAllocationKey,
          'items': allocationItems,
        });

        // Resolved before the submit, because the form is reset in between.
        final preBazaarCubit = context.read<PreBazaarCubit>();
        final messenger = ScaffoldMessenger.of(context);
        final bazaarName = _eventName.text.trim();
        await preBazaarCubit.submitAllocation(
          user: widget.user,
          detailsJson: details,
        );

        await _resetPreBazaarForm();

        // Deliberately not sent to Approvals any more. That screen decides
        // requests, and walking the requester into it handed an employee the
        // Approve button for their own bazaar -- the nav item is hidden from
        // them, so this was the only way in, and it worked.
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '$bazaarName has been submitted for approval. '
              'You will be notified once it has been reviewed.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    if (!_isBazaarInfoComplete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete event name, venue, and event dates before finishing.',
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Confirm Bazaar Publish',
      message: 'Publish this bazaar now?',
      cancelLabel: 'Review',
      confirmLabel: 'Publish',
    );

    if (confirmed == true && mounted) {
      final eventRepository = context.read<EventRepository>();
      final productRepository = context.read<ProductRepository>();

      // Publishing reloads four cubits and then resets the form; resolving
      // any of them through `context` afterwards risks a context that has
      // already moved on, which would drop the success message.
      final messenger = ScaffoldMessenger.of(context);
      final staffCubit = context.read<StaffCubit>();
      final dashboardCubit = context.read<DashboardCubit>();
      final posCubit = context.read<PosCubit>();
      final inventoryCubit = context.read<InventoryCubit>();
      final ordersCubit = context.read<OrdersCubit>();
      await _syncLocationsFromRepository();

      final selectedMethods = _selectedLocationPaymentMethods;
      if (selectedMethods.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This venue has no payment methods yet. Add them under Venues & Terms.',
              ),
            ),
          );
        }
        return;
      }

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

      final createdEvent = await eventRepository.createEvent(
        name: _eventName.text.trim(),
        companyId: _selectedCompanyId ?? _locations.first.id,
        startDate: _dateRange!.start,
        endDate: _dateRange!.end,
        acceptedPaymentMethods: selectedMethods
            .map((method) => method.name)
            .toList(),
        customOtherMethods: selectedMethods
            .map(
              (method) => BazaarPaymentMethod(
                name: method.name,
                extraFieldLabel: method.extraFieldLabel,
              ),
            )
            .toList(),
        allocationsByAllocationKey: allocationsByAllocationKey,
      );

      if (_assignedEmployeeIds.isNotEmpty) {
        await staffCubit.assignEmployeesToBazaar(
          eventId: createdEvent.id,
          employeeIds: _assignedEmployeeIds.toList(),
        );
      }

      await dashboardCubit.load(widget.user);
      await posCubit.load(widget.user);
      await inventoryCubit.load();
      await ordersCubit.load();

      messenger.showSnackBar(
        const SnackBar(content: Text('Bazaar published successfully.')),
      );
      await _resetPreBazaarForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdminOrOwner = widget.user.isAdminOrOwner;
    final employees = context
        .select((StaffCubit cubit) => cubit.state)
        .where((user) => user.role == UserRole.employee)
        .toList();
    final employeeNameById = {
      for (final employee in employees) employee.id: employee.name,
    };
    final assignedEmployees = _assignedEmployeeIds
        .map((id) => MapEntry(id, employeeNameById[id] ?? 'Employee #$id'))
        .toList();

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pre-Bazaar',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAdminOrOwner
                      ? 'Set up the event, then allocate the stock it will sell.'
                      : 'Set up the event and allocate stock, then submit for approval.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                _buildStepper(context),
              ],
            ),
          ),
          // Same full-bleed rule as Master Inventory: the controls sit on the
          // page background, the work surface starts below the line.
          const Divider(height: 1, color: Color(0xFFE2E2E8)),
          Expanded(
            child: ColoredBox(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _step == 0
                    ? SingleChildScrollView(
                        child: BazaarDetailsStep(
                          eventNameController: _eventName,
                          locations: _locations,
                          selectedCompanyId: _selectedCompanyId,
                          onCompanyChanged: (id) =>
                              setState(() => _selectedCompanyId = id),
                          dateRange: _dateRange,
                          onPickDates: _pickDateRange,
                          configuredPaymentMethods:
                              _selectedLocationPaymentMethods,
                          employees: employees,
                          assignedEmployees: assignedEmployees,
                          onAssignEmployee: (id) =>
                              setState(() => _assignedEmployeeIds.add(id)),
                          onRemoveAssignedEmployee: (id) => setState(() {
                            _assignedEmployeeIds.remove(id);
                          }),
                          showEmployeeAssignment: isAdminOrOwner,
                        ),
                      )
                    : StockAllocationStep(
                        groups: _visibleAllocationGroups(),
                        onAllocationChanged: _handleAllocationChanged,
                        searchController: _allocationSearch,
                        onSearchChanged: (_) => setState(() {}),
                      ),
              ),
            ),
          ),
          _buildFooter(context, isAdminOrOwner),
        ],
      ),
    );
  }

  /// Two numbered markers, matching the product form's stepper so the app has
  /// one visual language for "you are partway through something".
  Widget _buildStepper(BuildContext context) {
    const labels = ['Bazaar details', 'Stock allocation'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: i <= _step ? AppColors.primary : AppColors.border,
              ),
            ),
          _StepMarker(
            number: i + 1,
            label: labels[i],
            isDone: i < _step,
            isCurrent: i == _step,
            // Going back is always allowed; going forward is what the
            // completeness check gates.
            onTap: i < _step ? () => setState(() => _step = i) : null,
          ),
        ],
      ],
    );
  }

  Widget _buildFooter(BuildContext context, bool isAdminOrOwner) {
    final onDetails = _step == 0;
    final canContinue = _isBazaarInfoComplete;
    final canSubmit = canContinue && _totalAllocated > 0;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        children: [
          if (!onDetails)
            TextButton.icon(
              onPressed: () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black54,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              label: const Text('Back'),
            ),
          const Spacer(),
          TextButton(
            onPressed: _resetPreBazaarForm,
            style: TextButton.styleFrom(
              foregroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('Reset'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onDetails
                ? (canContinue ? _goToAllocation : null)
                : (canSubmit ? _handleSubmit : null),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(
                alpha: 0.35,
              ),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              onDetails
                  ? 'Continue'
                  : isAdminOrOwner
                  ? 'Publish bazaar'
                  : 'Submit for approval',
            ),
          ),
        ],
      ),
    );
  }

  int get _totalAllocated =>
      _allocations.values.fold<int>(0, (sum, value) => sum + value);

  /// Builds the allocation list, grouped by product and filtered by the
  /// search box. Grouping happens here rather than in the widget so the step
  /// stays a pure renderer.
  List<StockAllocationGroup> _visibleAllocationGroups() {
    final query = _allocationSearch.text.trim().toLowerCase();
    final grouped = <int, StockAllocationGroup>{};

    for (final entry in _allocationMetaByKey.entries) {
      final meta = entry.value;
      final variantParts = <String>[
        if (meta.groupA != null && meta.optionA != null)
          '${meta.groupA!.name} ${meta.optionA!.value}',
        if (meta.groupB != null && meta.optionB != null)
          '${meta.groupB!.name} ${meta.optionB!.value}',
      ];
      final label = variantParts.isEmpty
          ? meta.product.name
          : variantParts.join(' · ');

      if (query.isNotEmpty &&
          !meta.product.name.toLowerCase().contains(query) &&
          !label.toLowerCase().contains(query)) {
        continue;
      }

      final row = StockAllocationRow(
        key: entry.key,
        label: label,
        allocated: _allocations[entry.key] ?? 0,
        remaining: _masterStockByItem[entry.key] ?? 0,
      );
      final existing = grouped[meta.product.id];
      grouped[meta.product.id] = StockAllocationGroup(
        productName: meta.product.name,
        rows: [...?existing?.rows, row],
      );
    }

    return grouped.values.toList();
  }
}

/// One numbered marker in the pre-bazaar stepper.
class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.number,
    required this.label,
    required this.isDone,
    required this.isCurrent,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = isDone || isCurrent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.small,
              curve: AppMotion.easeOut,
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : Colors.black38,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: isActive ? AppColors.primary : Colors.black38,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
