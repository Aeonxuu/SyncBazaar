import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/orders/orders_cubit.dart';
import '../../../bloc/pos/pos_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../widgets/selectable_option_button.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/user.dart';
import '../../screens/dashboard/widgets/dashboard_section_card.dart';
import '../../../core/utils/formatters.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Separate from the transaction search: this one filters the list of
  /// bazaars, the other filters the rows inside one. Sharing a controller
  /// would carry a customer's name into the bazaar picker.
  final TextEditingController _bazaarSearch = TextEditingController();
  String _bazaarStatusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrdersCubit>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bazaarSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersCubit, OrdersState>(
      builder: (context, state) {
        if (state.selectedEventId == null && widget.user.isAdminOrOwner) {
          return _bazaarSelector(context);
        }

        final paymentFilterOptions = <String>{
          'All',
          ...state.records.map((r) => r.paymentMethod.trim()),
        }.where((value) => value.isNotEmpty).toList();

        final query = _searchController.text.trim().toLowerCase();
        var records = state.visibleRecords(widget.user);
        if (query.isNotEmpty) {
          records = records
              .where(
                (r) =>
                    r.customerName.toLowerCase().contains(query) ||
                    r.productLabel.toLowerCase().contains(query),
              )
              .toList();
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaction History',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (widget.user.isAdminOrOwner)
                    TextButton.icon(
                      onPressed: () =>
                          context.read<OrdersCubit>().filterByEvent(null),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Change Bazaar'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DashboardSectionCard(
                  title:
                      '${records.length} transaction${records.length == 1 ? '' : 's'}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search name or product',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 170,
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              paymentFilterOptions.contains(state.paymentMethod)
                              ? state.paymentMethod
                              : 'All',
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: paymentFilterOptions
                              .map(
                                (method) => DropdownMenuItem(
                                  value: method,
                                  child: Text(method.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              context.read<OrdersCubit>().filterByPayment(
                                value,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  child: records.isEmpty
                      ? _emptyState(context)
                      : _transactionTable(context, records),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _transactionTable(
    BuildContext context,
    List<TransactionRecord> records,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tableHeader(context),
        const Divider(height: 1, color: Color(0xFFEDEDED)),
        SizedBox(
          height: 460,
          child: ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return _tableRow(context, record, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w700,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Name', style: style)),
          Expanded(flex: 2, child: Text('Date', style: style)),
          Expanded(flex: 4, child: Text('Product', style: style)),
          Expanded(
            flex: 2,
            child: Text('Unit Price', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('Qty', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('Total', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(BuildContext context, TransactionRecord record, int index) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      color: isEven ? Colors.transparent : const Color(0xFFFAFAFB),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              record.customerName,
              style: textStyle?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(_fmtDate(record.timestamp), style: textStyle),
          ),
          Expanded(
            flex: 4,
            child: Text(
              record.productLabel,
              style: textStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatPeso(record.unitPrice),
              style: textStyle,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${record.quantity}',
              style: textStyle,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatPeso(record.total),
              style: textStyle?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.month}/${dt.day}/${dt.year} $hour:$minute $suffix';
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF2ECFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No transactions found.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bazaarSelector(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        final theme = Theme.of(context);
        final query = _bazaarSearch.text.trim().toLowerCase();
        final visible = state.events
            .where(
              (event) =>
                  _bazaarStatusFilter == 'ALL' ||
                  event.status.name.toUpperCase() == _bazaarStatusFilter,
            )
            .where(
              (event) =>
                  query.isEmpty || event.name.toLowerCase().contains(query),
            )
            .toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Not "active": this list is every bazaar the vendor has run
                // or will run, and its own badges say ENDED on most of them.
                'Select a bazaar',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.events.isEmpty
                    ? 'No bazaars yet.'
                    : _describeScope(state.events.length, visible.length),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _bazaarSearch,
                      onChanged: (_) => setState(() {}),
                      style: theme.textTheme.bodyMedium,
                      decoration: _selectorFieldDecoration(
                        hint: 'Search bazaar',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  for (final status in const [
                    'ALL',
                    'ONGOING',
                    'UPCOMING',
                    'ENDED',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectableOptionButton(
                        label: status,
                        isSelected: _bazaarStatusFilter == status,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        onTap: () =>
                            setState(() => _bazaarStatusFilter = status),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.search_off_outlined,
                              size: 28,
                              color: Colors.black26,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              state.events.isEmpty
                                  ? 'No bazaars yet.'
                                  : 'No bazaar matches that.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      )
                    // A grid rather than a Wrap of fixed-width cards. Wrap
                    // packs from the left and leaves whatever is left over as
                    // dead space on the right, so the whole page read as
                    // shoved into one corner. A grid divides the width
                    // between its columns, which is symmetric by
                    // construction and fills the row.
                    : GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 320,
                              mainAxisExtent: 152,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final event = visible[index];
                          return _AnimatedEntrance(
                            delayMs: 40 * (index % 8),
                            child: _InteractiveCard(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => context
                                  .read<OrdersCubit>()
                                  .filterByEvent(event.id),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFEDEDF1),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    // Dates, because two bazaars at the same
                                    // venue a season apart are told apart by
                                    // nothing else on this card.
                                    Text(
                                      '${_shortDate(event.startDate)} – '
                                      '${_shortDate(event.endDate)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.black45),
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        _StatusBadge(status: event.status),
                                        const Spacer(),
                                        const Icon(
                                          Icons.arrow_forward_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _describeScope(int total, int shown) {
    if (total == shown) {
      return '$total ${total == 1 ? 'bazaar' : 'bazaars'}';
    }
    return '$shown of $total shown';
  }

  static String _shortDate(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';
}

InputDecoration _selectorFieldDecoration({required String hint}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      prefixIcon: const Icon(Icons.search, size: 18, color: Colors.black38),
      filled: true,
      fillColor: AppColors.inputFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );

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

/// The bazaar's status, coloured by what it means for the reader.
///
/// Green for the one you can sell at now, amber for one still to come, grey for
/// one that is done — so the state is legible from the colour before the word
/// is read, and an ended bazaar stops looking like a live one.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BazaarStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (status) {
      BazaarStatus.ongoing => ('ACTIVE BAZAAR', const Color(0xFF2E7D32)),
      BazaarStatus.upcoming => ('UPCOMING', const Color(0xFF8A6100)),
      BazaarStatus.ended => ('ENDED', Colors.black54),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colour,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
