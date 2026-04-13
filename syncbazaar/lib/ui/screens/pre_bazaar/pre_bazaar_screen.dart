import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/approvals/approvals_cubit.dart';
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
  final Set<int> _assignedEmployeeIds = {};
  int? _selectedEmployeeId;
  List<Company> _locations = const [];
  Map<int, List<PaymentMethodMeta>> _locationPaymentMethodsByCompanyId = const {};

  @override
  void initState() {
    super.initState();
    _stockAllocationUnlocked = false;
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
    super.dispose();
  }

  List<DropdownMenuItem<int>> get _locationItems {
    return _locations
        .map(
          (location) => DropdownMenuItem<int>(
            value: location.id,
            child: Text(location.name),
          ),
        )
        .toList();
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

  Future<void> _resetPreBazaarForm() async {
    setState(() {
      _eventName.clear();
      _dateRange = null;
      _selectedCompanyId = _locationItems.isEmpty ? null : _locationItems.first.value;
      _stockAllocationUnlocked = false;
      _allocations.updateAll((_, __) => 0);
      _masterStockByItem.clear();
      _assignedEmployeeIds.clear();
      _selectedEmployeeId = null;
    });
    await _syncLocationsFromRepository();
    await _syncStocksFromRepository();
  }

  Future<void> _syncLocationsFromRepository() async {
    final settingsRepository = context.read<SettingsRepository>();
    final locations = await settingsRepository.listCompanies();
    final methodsByCompanyId =
        await settingsRepository.paymentMethodsByCompanyId();

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
      if (!_isBazaarInfoComplete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Complete event name, location, and event dates before submitting.',
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
        final categories = await context.read<ProductRepository>().listCategories();
        final categoryNameById = {
          for (final category in categories) category.id: category.name,
        };
        final selectedMethods = _selectedLocationPaymentMethods;
        final locationName = _locations
                .where((location) => location.id == _selectedCompanyId)
                .map((location) => location.name)
                .cast<String?>()
                .firstWhere((value) => value != null, orElse: () => null) ??
            'Unknown Location';
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
              content: Text('Add at least one allocated quantity before submitting.'),
            ),
          );
          return;
        }

        final allocationItems = selectedAllocations.map((entry) {
          final meta = _allocationMetaByKey[entry.key];
          final product = meta?.product;
          return {
            'name': product?.name ?? entry.key,
            'category': product == null
                ? '—'
                : (categoryNameById[product.categoryId] ?? 'Uncategorized'),
            'variant': meta?.option?.value ?? '—',
            'price': product == null ? '—' : product.basePrice.toStringAsFixed(2),
            'qty': entry.value,
          };
        }).toList();

        final details = jsonEncode({
          'eventName': _eventName.text.trim(),
          'locationName': locationName,
          'companyId': _selectedCompanyId,
          'dateStart': _dateRange?.start.toIso8601String(),
          'dateEnd': _dateRange?.end.toIso8601String(),
          'acceptedPaymentMethods': selectedMethods.map((method) => method.name).toList(),
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

        await context.read<PreBazaarCubit>().submitAllocation(
          user: widget.user,
          eventId: DateTime.now().millisecondsSinceEpoch,
          detailsJson: details,
        );

        await _resetPreBazaarForm();
        await context.read<ApprovalsCubit>().loadPending();
        widget.onOpenApprovals();
      }
      return;
    }

    if (!_isBazaarInfoComplete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete event name, location, and event dates before finishing.',
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
      await _syncLocationsFromRepository();

      final selectedMethods = _selectedLocationPaymentMethods;
      if (selectedMethods.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selected location has no payment methods. Configure it in Location section.',
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
        companyId: _selectedCompanyId ?? _locationItems.first.value ?? 1,
        startDate: _dateRange!.start,
        endDate: _dateRange!.end,
        acceptedPaymentMethods: selectedMethods.map((method) => method.name).toList(),
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
        await context.read<StaffCubit>().assignEmployeesToBazaar(
          eventId: createdEvent.id,
          employeeIds: _assignedEmployeeIds.toList(),
        );
      }

      if (!mounted) {
        return;
      }

      await context.read<DashboardCubit>().load(widget.user);
      await context.read<PosCubit>().load(widget.user);
      await context.read<InventoryCubit>().load();
      await context.read<OrdersCubit>().load();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bazaar published successfully.')),
      );
      await _resetPreBazaarForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdminOrOwner = widget.user.isAdminOrOwner;
    final users = context.select((StaffCubit cubit) => cubit.state);
    final employees = users.where((user) => user.role == UserRole.employee).toList();
    final employeeNameById = {
      for (final employee in employees) employee.id: employee.name,
    };
    final assignedEmployees = _assignedEmployeeIds
        .map((id) => MapEntry(id, employeeNameById[id] ?? 'Employee #$id'))
        .toList();
    final employeeItems = employees
        .map(
          (employee) => DropdownMenuItem<int>(
            value: employee.id,
            child: Text(employee.name),
          ),
        )
        .toList();

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
            companyItems: _locationItems,
            dateRange: _dateRange,
            configuredPaymentMethods: _selectedLocationPaymentMethods,
            employeeItems: employeeItems,
            selectedEmployeeId: _selectedEmployeeId,
            assignedEmployees: assignedEmployees,
            onEmployeeChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedEmployeeId = value;
                _assignedEmployeeIds.add(value);
              });
            },
            onRemoveAssignedEmployee: (employeeId) {
              setState(() {
                _assignedEmployeeIds.remove(employeeId);
              });
            },
            showEmployeeAssignment: isAdminOrOwner,
            onCompanyChanged: (value) {
              setState(() => _selectedCompanyId = value);
            },
            onPickDates: _pickDateRange,
            onCancel: () {
              _resetPreBazaarForm();
            },
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
            onCancel: () {
              _resetPreBazaarForm();
            },
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
