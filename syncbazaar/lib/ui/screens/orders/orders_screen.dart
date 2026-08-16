import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/orders/orders_cubit.dart';
import '../../../bloc/pos/pos_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/bazaar_search_field.dart';
import '../../widgets/bazaar_status_filter_button.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/user.dart';
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

  /// Null means all. Cycled rather than picked from a list, the same way
  /// Sales does it — both screens choose a bazaar from the same set, and two
  /// filters that look different imply they behave differently.
  BazaarStatus? _bazaarStatusFilter;

  void _cycleBazaarStatusFilter() {
    setState(() {
      _bazaarStatusFilter = switch (_bazaarStatusFilter) {
        null => BazaarStatus.upcoming,
        BazaarStatus.upcoming => BazaarStatus.ongoing,
        BazaarStatus.ongoing => BazaarStatus.ended,
        BazaarStatus.ended => null,
      };
    });
  }

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

        final eventName = state.selectedEventId == null
            ? null
            : context
                  .read<PosCubit>()
                  .state
                  .events
                  .where((e) => e.id == state.selectedEventId)
                  .map((e) => e.name)
                  .firstOrNull;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Orders',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          // Names the bazaar being read. The title alone
                          // could be any of twelve.
                          eventName == null
                              ? 'What this bazaar sold.'
                              : 'What $eventName sold.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                  if (widget.user.isAdminOrOwner)
                    TextButton.icon(
                      onPressed: () =>
                          context.read<OrdersCubit>().filterByEvent(null),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Change bazaar'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BazaarSearchField(
                    controller: _searchController,
                    onChanged: () => setState(() {}),
                    hint: 'Search customer or product',
                    maxWidth: 320,
                  ),
                  SizedBox(
                    width: 190,
                    child: AppDropdown<String>(
                      options: paymentFilterOptions,
                      selected:
                          paymentFilterOptions.contains(state.paymentMethod)
                          ? state.paymentMethod
                          : 'All',
                      labelOf: (method) =>
                          method == 'All' ? 'All payments' : method,
                      hint: 'All payments',
                      leadingIcon: Icons.payments_outlined,
                      onSelected: (method) =>
                          context.read<OrdersCubit>().filterByPayment(method),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${records.length} order${records.length == 1 ? '' : 's'} found',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black38),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEDEDF1)),
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
        const Divider(height: 1, color: Color(0xFFEDEDF1)),
        // Expanded, not a hardcoded height. It was pinned to 460px inside a
        // card that already fills the window, so on any screen taller than
        // that the list stopped mid-row and the rest of the card was blank --
        // which read as the text being cut off and sliding under the white.
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: records.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Color(0xFFF3F3F6)),
            itemBuilder: (context, index) => _tableRow(context, records[index]),
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.black38,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('CUSTOMER', style: style)),
          Expanded(flex: 5, child: Text('PRODUCT', style: style)),
          Expanded(
            flex: 2,
            child: Text('UNIT PRICE', style: style, textAlign: TextAlign.right),
          ),
          // Fixed width and centred. A count is one or two characters, so a
          // flex column leaves it stranded against one edge of a gap it does
          // not need -- and the slack it was holding is what makes room for
          // the full word.
          SizedBox(
            width: 92,
            child: Text('QUANTITY', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('TOTAL', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(BuildContext context, TransactionRecord record) {
    final theme = Theme.of(context);
    final label = record.productLabel;
    // "Nike ZoomX Vaporfly (Color Panda, Size 43)" split at the bracket. The
    // product goes on the first line and the variant beneath it, so a row is
    // two short lines rather than one wrapping to an uneven height.
    final bracket = label.indexOf('(');
    final product = bracket == -1 ? label : label.substring(0, bracket).trim();
    final variant = bracket == -1
        ? ''
        : label.substring(bracket + 1).replaceAll(')', '').trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // Time and payment method, not the date: every row in one
                  // bazaar shares the date, so repeating it down the column
                  // says nothing while the payment method -- which this
                  // screen can filter by -- was not shown at all.
                  '${_fmtTime(record.timestamp)} · ${record.paymentMethod}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (variant.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    variant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatAmount(record.unitPrice),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              '${record.quantity}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatPeso(record.total),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _emptyState(BuildContext context) {
    // Two emptinesses, said differently: a bazaar that sold nothing is a fact
    // about the bazaar, while a search that matched nothing is a fact about
    // the search, and only one of them is fixed by clearing the filters.
    final filtered =
        _searchController.text.trim().isNotEmpty ||
        context.read<OrdersCubit>().state.paymentMethod != 'All';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filtered ? Icons.search_off_outlined : Icons.receipt_long_outlined,
            size: 28,
            color: Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'No orders match that search.'
                : 'This bazaar has not sold anything yet.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _bazaarSelector(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        final theme = Theme.of(context);
        final query = _bazaarSearch.text.trim().toLowerCase();
        final visible = state.events.where((event) {
          if (_bazaarStatusFilter != null &&
              event.status != _bazaarStatusFilter) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          // Status and date as well as name, because "ended" and "8/17" are
          // both things somebody types when looking for a bazaar.
          return event.name.toLowerCase().contains(query) ||
              event.status.name.toLowerCase().contains(query) ||
              _shortDate(event.startDate).contains(query) ||
              _shortDate(event.endDate).contains(query);
        }).toList();

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
                // Purpose here, count in the caption under the search. Saying
                // the number twice is the same information in two places.
                'Choose a bazaar to see what it sold.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 24),
              // Wrapped so the two sit side by side on a wide window and
              // drop below each other on a narrow one, rather than
              // overflowing.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BazaarSearchField(
                    controller: _bazaarSearch,
                    onChanged: () => setState(() {}),
                  ),
                  BazaarStatusFilterButton(
                    status: _bazaarStatusFilter,
                    onTap: _cycleBazaarStatusFilter,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${visible.length} bazaar${visible.length == 1 ? '' : 's'} found',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black38,
                ),
              ),
              const SizedBox(height: 16),
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

  static String _shortDate(DateTime value) => formatDate(value);
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
      // "Ongoing", not "Active bazaar": the filter beside it, the status
      // colours, and the model all say ongoing, and a badge that renames the
      // thing it labels makes the filter look like it does something else.
      BazaarStatus.ongoing => ('ONGOING', AppColors.statusOngoing),
      BazaarStatus.upcoming => ('UPCOMING', AppColors.statusUpcoming),
      BazaarStatus.ended => ('ENDED', AppColors.statusEnded),
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
