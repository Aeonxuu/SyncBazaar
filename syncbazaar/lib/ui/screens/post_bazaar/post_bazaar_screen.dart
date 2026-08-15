import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../bloc/notifications/notifications_cubit.dart';
import '../../../bloc/settings/settings_cubit.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/remote/api_client.dart';
import '../../../services/orders_workbook.dart';
import '../../../services/report_service.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/product.dart';
import '../../../models/user.dart';
import '../../../models/sale.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../../core/utils/formatters.dart';

class PostBazaarScreen extends StatefulWidget {
  const PostBazaarScreen({super.key, required this.user});

  /// Whose paperwork this is. Exports are gated on the role: a statement of
  /// account is what the venue gets paid against, so it is the owner's to
  /// produce rather than a cashier's.
  final AppUser user;

  @override
  State<PostBazaarScreen> createState() => _PostBazaarScreenState();
}

class _PostBazaarScreenState extends State<PostBazaarScreen> {
  late Future<_PostBazaarData> _futureData;
  int? _selectedReconciliationEventId;

  static const _kCardRadius = 12.0;
  static const _kCardShadow = [
    BoxShadow(color: Color(0x11000000), blurRadius: 20, offset: Offset(0, 4)),
  ];

  @override
  void initState() {
    super.initState();
    _futureData = _loadData();
  }

  Future<_PostBazaarData> _loadData() async {
    final salesRepository = context.read<SalesRepository>();
    final productRepository = context.read<ProductRepository>();
    final eventRepository = context.read<EventRepository>();
    final settingsRepository = context.read<SettingsRepository>();
    // Read before the first await, with the other repositories: reaching for
    // the context after one is what the analyzer objects to, and rightly.
    final reportService = ReportService(auth: context.read<AuthRepository>());

    final sales = await salesRepository.listSales();
    final products = await productRepository.listProducts();
    final events = await eventRepository.listAll();
    final allocationsByEventId = <int, Map<String, int>>{};
    for (final event in events) {
      allocationsByEventId[event.id] = await eventRepository
          .allocationsForEventByAllocationKey(event.id);
    }
    // Fetched per bazaar rather than counted here: the client keeps only what
    // is *left* of an allocation, so the opening figure a reconciliation is
    // measured against is already gone by the time this screen opens.
    final reports = <int, ReconciliationReport>{};
    if (reportService.isAvailable) {
      for (final event in events) {
        try {
          final report = await reportService.reconciliation(event.id);
          if (report != null) {
            reports[event.id] = report;
          }
        } on ApiException {
          // One bazaar failing should not take the whole page down; the row
          // falls back to the local figures.
        }
      }
    }

    // Built once for every product rather than per row: the order list joins
    // each sale's option ids back to "Color Black, Size 42", and doing that
    // lookup per sale would re-read the same product forty-nine times.
    final optionLabelById = <int, String>{};
    for (final product in products) {
      final groups = await productRepository.variantGroupsForProduct(
        product.id,
      );
      final groupNameById = {for (final group in groups) group.id: group.name};
      final options = await productRepository.allVariantOptionsForProduct(
        product.id,
      );
      for (final option in options) {
        final groupName = groupNameById[option.variantGroupId];
        optionLabelById[option.id] = groupName == null
            ? option.value
            : '$groupName ${option.value}';
      }
    }

    // Which methods a bazaar took, and what each one asked the cashier for --
    // a GCash reference, a bank slip number. Resolved per bazaar because a
    // venue can override a method's field for its own event.
    final basePaymentMethods = await settingsRepository.paymentMethods();
    final extraFieldLabelsByEventId = {
      for (final event in events)
        event.id: _extraFieldLabels(event, basePaymentMethods),
    };

    final eventNameById = {for (final event in events) event.id: event.name};
    final companies = await settingsRepository.listCompanies();
    final companyById = {for (final company in companies) company.id: company};
    final companyNameById = {
      for (final company in companies) company.id: company.name,
    };
    return _PostBazaarData(
      sales: sales,
      products: products,
      events: events,
      allocationsByEventId: allocationsByEventId,
      reconciliationByEventId: reports,
      optionLabelById: optionLabelById,
      extraFieldLabelsByEventId: extraFieldLabelsByEventId,
      eventNameById: eventNameById,
      locationNameByEventId: {
        for (final event in events)
          event.id: companyNameById[event.companyId] ?? 'Unknown venue',
      },
      incentivePercentByEventId: {
        for (final event in events)
          event.id: companyById[event.companyId]?.incentivePercent ?? 10,
      },
      bufferPercentByEventId: {
        for (final event in events)
          event.id: companyById[event.companyId]?.bufferPercent ?? 10,
      },
    );
  }

  /// What each of a bazaar's payment methods asks the cashier for, keyed by
  /// method name in upper case so a sale's stored method matches whatever case
  /// it was configured in.
  ///
  /// Mirrors how the POS resolves the same thing when it decides which field to
  /// show at checkout: the venue's own override for an event wins over the
  /// method's global setting, so the workbook's column is headed with the
  /// wording the cashier was actually typing into.
  static Map<String, String?> _extraFieldLabels(
    BazaarEvent event,
    List<PaymentMethodMeta> baseMethods,
  ) {
    final labels = <String, String?>{};
    for (final method in baseMethods) {
      labels[method.name.trim().toUpperCase()] = method.extraFieldLabel;
    }
    for (final custom in event.customOtherMethods) {
      labels[custom.name.trim().toUpperCase()] = custom.extraFieldLabel;
    }
    return labels;
  }

  /// Turns a bazaar's sales into spreadsheet rows.
  ///
  /// A [Sale] is already one cart line, so this is a rename rather than a
  /// regrouping. The one join is the product label, which the sale holds only
  /// as ids.
  List<OrderLine> _orderLines(_PostBazaarData data, BazaarEvent event) {
    final productNameById = {
      for (final product in data.products) product.id: product.name,
    };

    return [
      for (final sale in data.sales.where((sale) => sale.eventId == event.id))
        OrderLine(
          date: sale.timestamp,
          customerName: normalizeCustomerName(sale.customerName),
          product: _productLabel(data, sale, productNameById),
          paymentMethod: sale.paymentMethod,
          // Named `employeeId` on the model, which it has never held: the
          // POS writes the payment method's extra field into it.
          reference: sale.employeeId,
          quantity: sale.qty,
          total: sale.total,
          returned: sale.orderStatus == OrderStatus.returned,
        ),
    ];
  }

  /// `Nike Air Max SC (Color Black, Size 42)` — the same wording the cart and
  /// the receipt use, so a row can be matched against a customer's copy.
  String _productLabel(
    _PostBazaarData data,
    Sale sale,
    Map<int, String> productNameById,
  ) {
    final name = productNameById[sale.productId] ?? 'Unknown product';
    final parts = [
      for (final optionId in [sale.variantOptionIdA, sale.variantOptionIdB])
        if (optionId != null && data.optionLabelById[optionId] != null)
          data.optionLabelById[optionId]!,
    ];
    return parts.isEmpty ? name : '$name (${parts.join(', ')})';
  }

  Future<void> _refresh() async {
    setState(() {
      _futureData = _loadData();
    });
    await _futureData;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: _kCardShadow,
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: const Color(0xFFF2ECFC),
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.black54,
              labelStyle: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'SOA Draft'),
                Tab(text: 'List of Orders'),
                Tab(text: 'Inventory Reconciliation'),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<_PostBazaarData>(
              future: _futureData,
              builder: (context, snapshot) {
                // A failed load used to fall through to the spinner below,
                // because `hasData` is false for an error too -- so anything
                // going wrong here showed as loading, for ever, with nothing
                // said about it.
                if (snapshot.hasError) {
                  return _loadFailed(context, snapshot.error!);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                if (_selectedReconciliationEventId == null &&
                    data.events.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedReconciliationEventId == null) {
                      setState(() {
                        _selectedReconciliationEventId = data.events.first.id;
                      });
                    }
                  });
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: TabBarView(
                    children: [
                      _soaDraft(context, data),
                      _ordersExport(context, data),
                      _reconciliation(context, data),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _soaDraft(BuildContext context, _PostBazaarData data) {
    if (data.events.isEmpty) {
      return _emptyState('No bazaar events found.');
    }

    return _eventGrid(
      events: data.events,
      locationNameByEventId: data.locationNameByEventId,
      compactCardLayout: true,
      onOpenDetails: (event) => _openSoaDetails(context, data, event),
    );
  }

  Widget _ordersExport(BuildContext context, _PostBazaarData data) {
    if (data.events.isEmpty) {
      return _emptyState('No bazaar events found.');
    }

    return _eventGrid(
      events: data.events,
      locationNameByEventId: data.locationNameByEventId,
      compactCardLayout: true,
      onOpenDetails: (event) => _openOrdersDetails(context, data, event),
    );
  }

  /// Says what went wrong and offers the one useful action.
  Widget _loadFailed(BuildContext context, Object error) {
    final message = error is ApiException
        ? error.message
        : 'Something went wrong preparing this page.';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 28, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reconciliation(BuildContext context, _PostBazaarData data) {
    // Only bazaars that have finished. Reconciling is the act of counting what
    // came back from a stall, so a bazaar still selling has nothing to count --
    // its stock is on a table somewhere, not returned. Listing every bazaar
    // here invited someone to return stock out from under a live till.
    final ended = data.events
        .where((event) => event.status == BazaarStatus.ended)
        .toList();

    if (ended.isEmpty) {
      return _emptyState(
        data.events.isEmpty
            ? 'No bazaar events found.'
            : 'No bazaars have ended yet. A bazaar appears here once its last '
                  'day has passed, ready for its stock to be counted back in.',
      );
    }

    return _eventGrid(
      events: ended,
      locationNameByEventId: data.locationNameByEventId,
      compactCardLayout: true,
      onOpenDetails: (event) => _openReturnStock(context, data, event),
    );
  }

  /// What a bazaar still has on its table, by product.
  ///
  /// The allocations this screen holds are already what is *left*: they are
  /// decremented as each sale is rung up. So this is a naming exercise rather
  /// than a calculation -- the numbers are the ones the stall should be
  /// physically holding.
  List<_LeftoverLine> _leftovers(_PostBazaarData data, BazaarEvent event) {
    final productNameById = {
      for (final product in data.products) product.id: product.name,
    };
    final allocations = data.allocationsByEventId[event.id] ?? const {};

    final lines = <_LeftoverLine>[];
    allocations.forEach((key, quantity) {
      if (quantity <= 0) {
        return;
      }
      final parts = key.split(':');
      final productId = int.tryParse(parts.first) ?? 0;
      final optionIds = parts
          .skip(1)
          .map(int.tryParse)
          .where((id) => id != null && id != 0)
          .cast<int>();
      final variant = [
        for (final id in optionIds)
          if (data.optionLabelById[id] != null) data.optionLabelById[id]!,
      ].join(', ');

      lines.add(
        _LeftoverLine(
          product: productNameById[productId] ?? 'Unknown product',
          variant: variant,
          quantity: quantity,
        ),
      );
    });

    lines.sort((a, b) {
      final byProduct = a.product.compareTo(b.product);
      return byProduct != 0 ? byProduct : a.variant.compareTo(b.variant);
    });
    return lines;
  }

  Future<void> _openReturnStock(
    BuildContext context,
    _PostBazaarData data,
    BazaarEvent event,
  ) async {
    final lines = _leftovers(data, event);
    final totalUnits = lines.fold<int>(0, (sum, line) => sum + line.quantity);
    final canReturn = widget.user.isAdminOrOwner;

    await _showDetailsDialog(
      context: context,
      title: event.name,
      subtitle: data.locationNameByEventId[event.id] ?? 'Unknown venue',
      content: [
        if (lines.isEmpty)
          Text(
            'Everything allocated to this bazaar was sold. There is nothing '
            'to bring back.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.4),
          )
        else ...[
          _sectionLabel(context, 'Still at the stall'),
          const SizedBox(height: 8),
          ConstrainedBox(
            // Tall enough to read a normal bazaar's leftovers at a glance,
            // capped so a big one scrolls rather than pushing the button off
            // the bottom of the dialog.
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final line in lines)
                    _receiptRow(
                      context,
                      label: line.variant.isEmpty
                          ? line.product
                          : '${line.product} (${line.variant})',
                      value: '${line.quantity}',
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 18),
          _receiptRow(
            context,
            label: 'Units to return',
            value: '$totalUnits',
            emphasize: true,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: Color(0xFF8D6E00),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Count these back into the store first. Confirming adds '
                    'them to master inventory, and the app has no way to '
                    'check whether the shoes actually made it back.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6D5500),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      footer: (lines.isEmpty || !canReturn)
          ? null
          : Align(
              alignment: Alignment.centerRight,
              child: _ReturnStockButton(
                onReturn: () async {
                  final eventRepository = context.read<EventRepository>();
                  final notifications = context.read<NotificationsCubit>();
                  await eventRepository.finalizeEvent(event.id);
                  await notifications.record(
                    type: 'reconciliation',
                    message:
                        '$totalUnits unit${totalUnits == 1 ? '' : 's'} '
                        'returned to master inventory from ${event.name}.',
                  );
                  return '$totalUnits unit${totalUnits == 1 ? '' : 's'} '
                      'returned to master inventory.';
                },
                onDone: _refresh,
              ),
            ),
    );
  }

  Widget _eventGrid({
    required List<BazaarEvent> events,
    required Map<int, String> locationNameByEventId,
    bool compactCardLayout = false,
    required ValueChanged<BazaarEvent> onOpenDetails,
  }) {
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: compactCardLayout ? 36 : 16,
        vertical: 16,
      ),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final event = events[index];
        final locationName = locationNameByEventId[event.id] ?? 'Unknown venue';

        return _AnimatedEntrance(
          delayMs: 40 * (index % 8),
          child: _InteractiveCard(
            onTap: () => onOpenDetails(event),
            borderRadius: BorderRadius.circular(_kCardRadius),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_kCardRadius),
                boxShadow: _kCardShadow,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          locationName,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDateRange(event.startDate, event.endDate),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusBackground(event.status),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          event.status.name.toUpperCase(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _statusForeground(event.status),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2ECFC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View details',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    String fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
    return '${fmt(start)} - ${fmt(end)}';
  }

  Color _statusBackground(BazaarStatus status) {
    switch (status) {
      case BazaarStatus.upcoming:
        return const Color(0x1AF59E0B);
      case BazaarStatus.ongoing:
        return const Color(0x1A2E7D32);
      case BazaarStatus.ended:
        return const Color(0x1A6B7280);
    }
  }

  Color _statusForeground(BazaarStatus status) {
    switch (status) {
      case BazaarStatus.upcoming:
        return const Color(0xFFB45309);
      case BazaarStatus.ongoing:
        return const Color(0xFF2E7D32);
      case BazaarStatus.ended:
        return const Color(0xFF4B5563);
    }
  }

  Widget _emptyState(String message) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_kCardRadius),
            boxShadow: _kCardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2ECFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openSoaDetails(
    BuildContext context,
    _PostBazaarData data,
    BazaarEvent event,
  ) async {
    final eventSales = data.sales
        .where((sale) => sale.eventId == event.id)
        .toList();
    final grossSales = eventSales.fold<double>(
      0,
      (sum, sale) => sum + sale.total,
    );
    final location = data.locationNameByEventId[event.id] ?? 'Unknown venue';
    final incentivePct = data.incentivePercentByEventId[event.id] ?? 10;
    final bufferPct = data.bufferPercentByEventId[event.id] ?? 10;
    final incentive = grossSales * (incentivePct / 100);
    final buffer = grossSales * (bufferPct / 100);
    final net = grossSales - incentive - buffer;

    final dueToVenue = incentive + buffer;

    // The vendor's own name, so the last row says whose money it is. Falls
    // back to "us" rather than a hardcoded "SV KICKz" — the settings value is
    // blank until someone fills it in, and this app is not single-tenant.
    final configuredName = context.read<SettingsCubit>().state.storeName.trim();
    final storeName = configuredName.isEmpty ? 'us' : configuredName;

    // Owner-only: this is the money document, the one the venue is paid
    // against. A cashier can read the figures but is shown no action.
    final canExport = widget.user.isAdminOrOwner;

    await _showDetailsDialog(
      context: context,
      title: event.name,
      // The count belongs with the bazaar, not among the peso figures: it is
      // the only number on the card that is not money, and reading it in that
      // column invites it to be read as one.
      subtitle:
          '$location  ·  ${eventSales.length} '
          'transaction${eventSales.length == 1 ? '' : 's'}',
      content: [
        // Laid out the way the exported statement is, so the preview and the
        // document tell the same story: what was taken, what the venue is owed
        // out of it, and what is left.
        _receiptRow(
          context,
          label: 'Gross sales',
          value: formatPeso(grossSales),
        ),
        const SizedBox(height: 14),
        _sectionLabel(context, 'Due to venue'),
        const SizedBox(height: 8),
        _receiptRow(
          context,
          label: 'Incentive (${formatPercent(incentivePct)})',
          value: formatPeso(incentive),
        ),
        _receiptRow(
          context,
          label: 'Buffer (${formatPercent(bufferPct)})',
          value: formatPeso(buffer),
        ),
        const Divider(height: 18),
        // The one emphasised figure. It is the money that actually changes
        // hands, and the reason the document exists -- the app can show the
        // total even though the template cannot yet.
        _receiptRow(
          context,
          label: 'Total due to venue',
          value: formatPeso(dueToVenue),
          emphasize: true,
        ),
        const SizedBox(height: 14),
        _receiptRow(
          context,
          // Named rather than "Net amount": the figure is what the vendor
          // keeps, and the unlabelled version was read on the printed
          // statement as what the venue was owed.
          label: 'Retained by $storeName',
          value: formatPeso(net),
        ),
      ],
      // Right-aligned and auto-width: one primary action, sized to itself
      // rather than stretched across the dialog, per the button tiers in
      // DESIGN_GUIDELINES.md.
      footer: !canExport
          ? null
          : Align(
              alignment: Alignment.centerRight,
              child: _ExportButton(
                icon: Icons.description_outlined,
                label: 'Export SOA (.docx)',
                onExport: () =>
                    ReportService(
                      auth: context.read<AuthRepository>(),
                    ).exportStatementOfAccount(
                      eventId: event.id,
                      eventName: event.name,
                    ),
              ),
            ),
    );
  }

  Future<void> _openOrdersDetails(
    BuildContext context,
    _PostBazaarData data,
    BazaarEvent event,
  ) async {
    // Counted from sales rather than from the local Order rows this screen
    // used to read. Orders are only ever written here, at the till, and never
    // fetched -- so a bazaar whose sales came back from the server had none of
    // them, and this dialog reported zero beside an export full of rows. Sales
    // are what the workbook is built from, so the two now cannot disagree.
    final eventOrders = data.sales
        .where((sale) => sale.eventId == event.id)
        .toList();

    // Counted from the sales themselves rather than against a hardcoded
    // CASH/COOP/other, which reported every method a venue had configured for
    // itself as an anonymous "Custom methods" tally.
    final countByMethod = <String, int>{};
    for (final sale in eventOrders) {
      final method = sale.paymentMethod.trim().isEmpty
          ? 'CASH'
          : sale.paymentMethod.trim().toUpperCase();
      countByMethod[method] = (countByMethod[method] ?? 0) + 1;
    }
    final methods = countByMethod.keys.toList()
      ..sort((a, b) {
        if (a == 'CASH') return -1;
        if (b == 'CASH') return 1;
        return a.compareTo(b);
      });

    final completedCount = eventOrders
        .where((sale) => sale.orderStatus == OrderStatus.completed)
        .length;
    final returnedCount = eventOrders
        .where((sale) => sale.orderStatus == OrderStatus.returned)
        .length;

    final canExport = widget.user.isAdminOrOwner;
    final lines = _orderLines(data, event);
    final extraFieldLabels =
        data.extraFieldLabelsByEventId[event.id] ?? const {};

    await _showDetailsDialog(
      context: context,
      title: event.name,
      subtitle: data.locationNameByEventId[event.id] ?? 'Unknown venue',
      content: [
        _receiptRow(
          context,
          label: 'Total orders',
          value: '${eventOrders.length}',
          emphasize: true,
        ),
        const SizedBox(height: 14),
        // The same two groupings the workbook is built on, so what is read
        // here is what opens in Excel.
        _sectionLabel(context, 'By payment method'),
        const SizedBox(height: 8),
        if (methods.isEmpty)
          _receiptRow(context, label: 'No orders yet', value: '—')
        else
          for (final method in methods)
            _receiptRow(
              context,
              label: method,
              value: '${countByMethod[method]}',
            ),
        const SizedBox(height: 14),
        _sectionLabel(context, 'By status'),
        const SizedBox(height: 8),
        _receiptRow(context, label: 'Completed', value: '$completedCount'),
        _receiptRow(context, label: 'Returned', value: '$returnedCount'),
      ],
      footer: !canExport
          ? null
          : Align(
              alignment: Alignment.centerRight,
              child: _ExportButton(
                icon: Icons.table_chart_outlined,
                label: 'Export order list (.xlsx)',
                // Built on the device, unlike the statement of account: the
                // server renders one flat CSV, and this is a workbook with a
                // sheet per payment method.
                onExport: () =>
                    ReportService(
                      auth: context.read<AuthRepository>(),
                    ).exportOrdersWorkbook(
                      eventName: event.name,
                      lines: lines,
                      extraFieldLabelByMethod: extraFieldLabels,
                    ),
              ),
            ),
    );
  }

  Future<void> _showDetailsDialog({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<Widget> content,
    Widget? footer,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.96, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.scale(
              scale: value,
              child: Opacity(opacity: value, child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          tooltip: 'Close',
                          // Trimmed off the default 8pt so the icon sits on
                          // the dialog's 24pt margin rather than 8pt inside
                          // it, which reads as a lopsided right edge.
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ...content,
                    if (footer != null) ...[const SizedBox(height: 24), footer],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A heading over a group of rows, so the rows beneath it read as one thing.
  ///
  /// The statement's whole difficulty is that incentive and buffer are not two
  /// unrelated deductions — they are the venue's share, and listing them flat
  /// among the other figures is what made the printed version read wrongly.
  Widget _sectionLabel(BuildContext context, String text) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.black45,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );

  Widget _receiptRow(
    BuildContext context, {
    required String label,
    required String value,
    bool emphasize = false,
  }) {
    // The emphasised row carries a weight, a size and a colour rather than
    // just a bolder font: at bodySmall, w600 against w700 is close to
    // invisible, so the one figure that matters did not stand out from the
    // working-out above it.
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: emphasize ? AppColors.text : Colors.black54,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
    );
    final valueStyle =
        (emphasize
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.bodyMedium)
            ?.copyWith(
              color: emphasize ? AppColors.primary : AppColors.text,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: 10),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _AnimatedEntrance extends StatefulWidget {
  const _AnimatedEntrance({required this.child, required this.delayMs});

  final Widget child;
  final int delayMs;

  @override
  State<_AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<_AnimatedEntrance> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (!mounted) return;
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, 0.06),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _visible ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}

class _InteractiveCard extends StatefulWidget {
  const _InteractiveCard({
    required this.onTap,
    required this.child,
    required this.borderRadius,
  });

  final VoidCallback onTap;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<_InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<_InteractiveCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.99 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: widget.borderRadius,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: widget.child,
        ),
      ),
    );
  }
}

class _PostBazaarData {
  const _PostBazaarData({
    required this.sales,
    required this.products,
    required this.events,
    required this.allocationsByEventId,
    required this.optionLabelById,
    required this.extraFieldLabelsByEventId,
    required this.eventNameById,
    required this.locationNameByEventId,
    required this.incentivePercentByEventId,
    required this.bufferPercentByEventId,
    required this.reconciliationByEventId,
  });

  final List<Sale> sales;
  final List<Product> products;
  final List<BazaarEvent> events;
  final Map<int, Map<String, int>> allocationsByEventId;

  /// The server's own count of what each bazaar started with, sold and has
  /// left. Empty without a session, and empty for a bazaar whose figures could
  /// not be fetched -- the screen falls back to what it can see locally.
  final Map<int, ReconciliationReport> reconciliationByEventId;

  /// Variant option id to its printable label, e.g. 3 -> "Color Black". Built
  /// across every product so the order list can name what was sold.
  final Map<int, String> optionLabelById;

  /// Per bazaar: payment method name to the extra field that method asks for,
  /// or null where it asks for nothing. Names the extra column in the order
  /// workbook, and only for the sheets that need one.
  final Map<int, Map<String, String?>> extraFieldLabelsByEventId;

  final Map<int, String> eventNameById;
  final Map<int, String> locationNameByEventId;
  final Map<int, double> incentivePercentByEventId;
  final Map<int, double> bufferPercentByEventId;
}

/// Runs an export and reports where the file landed.
///
/// Its own widget because the work is slow enough to need saying so: the server
/// renders the document before it answers, and a sleeping free-tier host can
/// take most of a minute. A button that looks idle for that long reads as
/// broken, and gets pressed again.
class _ExportButton extends StatefulWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.onExport,
  });

  final IconData icon;
  final String label;

  /// Returns the phrase describing where the file went.
  final Future<String> Function() onExport;

  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final where = await widget.onExport();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(where)));
    } on ReportException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      // Disabled while running, so a slow render cannot be started twice.
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icon),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      label: Text(_busy ? 'Preparing…' : widget.label),
    );
  }
}

/// One product still sitting on a bazaar's table.
class _LeftoverLine {
  const _LeftoverLine({
    required this.product,
    required this.variant,
    required this.quantity,
  });

  final String product;

  /// "Color Black, Size 42", or empty for a product with no categories.
  final String variant;

  final int quantity;
}

/// Confirms, then returns a bazaar's leftover stock to master inventory.
///
/// Its own widget for the same reason exports have one, and one more: the
/// server cannot yet refuse a second return. Its guard tests an `is_finalized`
/// field that does not exist on the model, so `hasattr` is always false and
/// finalizing twice adds the leftovers to the warehouse twice. Until that
/// lands, this being un-pressable while it runs -- and gone once it has -- is
/// the only thing standing between a slow connection and inflated stock.
class _ReturnStockButton extends StatefulWidget {
  const _ReturnStockButton({required this.onReturn, required this.onDone});

  /// Returns the phrase to show once the stock is back.
  final Future<String> Function() onReturn;

  final Future<void> Function() onDone;

  @override
  State<_ReturnStockButton> createState() => _ReturnStockButtonState();
}

class _ReturnStockButtonState extends State<_ReturnStockButton> {
  bool _busy = false;
  bool _done = false;

  Future<void> _run() async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Return stock to inventory',
      message:
          'Have these items been physically counted back into the store? '
          'This cannot be undone from the app.',
      confirmLabel: 'Yes, return them',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final where = await widget.onReturn();
      // Latched rather than reset: a second press would return the same
      // stock again, and nothing server-side would stop it.
      if (mounted) setState(() => _done = true);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(where)));
      await widget.onDone();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.isOffline
                ? 'Cannot reach the server, so nothing was returned. '
                      'Try again when you have a connection.'
                : 'The stock could not be returned. ${error.message}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: (_busy || _done) ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.inventory_2_outlined),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      label: Text(_busy ? 'Returning…' : 'Return stock'),
    );
  }
}
