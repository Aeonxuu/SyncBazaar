import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/remote/api_client.dart';
import '../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../bloc/inventory/inventory_cubit.dart';
import '../../../bloc/orders/orders_cubit.dart';
import '../../../bloc/pos/pos_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/product.dart';
import '../../../models/product_variant.dart';
import '../../../models/user.dart';
import '../../../data/repositories/product_repository.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/offline_data_notice.dart';
import 'widgets/discard_sale_guard.dart';
import '../../widgets/date_range_picker_dialog.dart';
import '../../widgets/custom_card.dart';
import '../../../bloc/staff/staff_cubit.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../services/staff_scheduling.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/bazaar_search_field.dart';
import '../../widgets/bazaar_status_filter_button.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/product_thumbnail.dart';
import '../../widgets/selectable_option_button.dart';
import 'widgets/pos_product_card.dart';
import '../../../core/utils/formatters.dart';
import 'widgets/confirm_sale_dialog.dart';
import 'widgets/qr_payment_dialog.dart';
import 'widgets/receipt_print_dialog.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _bazaarSearchController = TextEditingController();
  final TextEditingController _productSearchController =
      TextEditingController();

  // The three order fields are controlled rather than fire-and-forget, so that
  // clearing them in the cubit actually empties them on screen. Without a
  // controller a TextField owns its own text: finishing a sale reset the state
  // but left the previous customer's name and cash amount sitting in the boxes,
  // ready to be committed against the next sale.
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _paymentExtraFieldController =
      TextEditingController();
  final TextEditingController _cashTenderedController = TextEditingController();
  // null = no filter ("All"). A single control cycling through every state
  // beats 3 separate toggle buttons for a filter this small and secondary.
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
  void dispose() {
    _bazaarSearchController.dispose();
    _productSearchController.dispose();
    _customerNameController.dispose();
    _paymentExtraFieldController.dispose();
    _cashTenderedController.dispose();
    super.dispose();
  }

  /// Pulls the order fields back in line whenever the cubit empties them.
  ///
  /// Driven off state rather than cleared at each call site because three
  /// different actions reset these — finishing a sale, cancelling the draft,
  /// and switching payment method — and a cashier only has to be handed one
  /// stale field once to ring up the wrong total. Syncing only on empty, so
  /// typing is never fought mid-keystroke.
  void _syncOrderFields(PosState state) {
    if (state.customerName.isEmpty && _customerNameController.text.isNotEmpty) {
      _customerNameController.clear();
    }
    if (state.paymentExtraFieldValue.isEmpty &&
        _paymentExtraFieldController.text.isNotEmpty) {
      _paymentExtraFieldController.clear();
    }
    if (state.cashTendered.isEmpty && _cashTenderedController.text.isNotEmpty) {
      _cashTenderedController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PosCubit, PosState>(
      listener: (context, state) => _syncOrderFields(state),
      builder: (context, state) {
        if (state.selectedEvent == null) {
          return _eventSelector(context, state);
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(flex: 7, child: _productPanel(context, state)),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _cartPanel(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _eventSelector(BuildContext context, PosState state) {
    final query = _bazaarSearchController.text.trim().toLowerCase();
    final filteredEvents = state.events.where((event) {
      if (_bazaarStatusFilter != null && event.status != _bazaarStatusFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final nameMatch = event.name.toLowerCase().contains(query);
      final statusMatch = event.status.name.toLowerCase().contains(query);
      final startDateMatch = _formatDate(
        event.startDate,
      ).toLowerCase().contains(query);
      final endDateMatch = _formatDate(
        event.endDate,
      ).toLowerCase().contains(query);
      return nameMatch || statusMatch || startDateMatch || endDateMatch;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Active Bazaar',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a bazaar to start selling.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black45),
          ),
          const SizedBox(height: 20),
          // A single, unlabeled search field: the placeholder already says
          // what it's for, so a caption above it would just repeat the
          // same information (minimalism — say it once). Status filters
          // sit in the same Wrap so they sit beside it on wide screens and
          // drop below it on narrow ones, instead of ever overflowing.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              BazaarSearchField(
                controller: _bazaarSearchController,
                onChanged: () => setState(() {}),
              ),
              BazaarStatusFilterButton(
                status: _bazaarStatusFilter,
                onTap: _cycleBazaarStatusFilter,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Visibility of system status: a quiet result count confirms the
          // search actually did something, without shouting about it.
          Text(
            '${filteredEvents.length} bazaar${filteredEvents.length == 1 ? '' : 's'} found',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black38),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filteredEvents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.storefront_outlined,
                          size: 40,
                          color: Colors.black26,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No bazaars match your current search and filters.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.black45),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    itemCount: filteredEvents.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          mainAxisExtent: 200,
                        ),
                    itemBuilder: (context, index) {
                      final event = filteredEvents[index];
                      return _BazaarCard(
                        event: event,
                        canManage: widget.user.isAdminOrOwner,
                        formatDate: _formatDate,
                        onOpen: () =>
                            context.read<PosCubit>().selectEvent(event),
                        onEdit: () =>
                            _showEditEventDialog(context, state, event),
                        onShowInfo: () =>
                            _showEventInfoDialog(context, state, event),
                        onDelete: () => _deleteEvent(context, event),
                        deleteBlockedReason: state.deleteBlockedReason(event),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _productPanel(BuildContext context, PosState state) {
    // Non-null when the catalogue on screen came from storage rather than the
    // server. It matters more here than on the dashboard: a stale stock count
    // can be sold past, and the customer is standing at the counter.
    final servedFrom = context.read<AuthRepository>().api.servingCacheFrom;
    final query = _productSearchController.text.trim().toLowerCase();
    final visibleProducts = query.isEmpty
        ? state.products
        : state.products
              .where((p) => p.name.toLowerCase().contains(query))
              .toList();

    final eventName = state.selectedEvent?.name ?? 'Bazaar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (servedFrom != null) ...[
          OfflineDataNotice(storedAt: servedFrom),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            // A breadcrumb rather than a bordered button. Leaving the bazaar
            // happens once a shift, so an outlined purple control gave a
            // rare action the same weight as the search field beside it
            // (Section 4's button tiers). As a crumb it also answers a
            // question the panel never used to: which bazaar am I selling at?
            _BazaarBreadcrumb(
              eventName: eventName,
              onBack: () async {
                if (!await confirmLeavingSale(context)) {
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                context.read<PosCubit>().backToEventSelection();
              },
            ),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TextField(
                controller: _productSearchController,
                onChanged: (_) => setState(() {}),
                style: Theme.of(context).textTheme.bodyMedium,
                // Matched to the bazaar-picker search field one screen back:
                // same neutral fill, hairline border, clear button. The two
                // used to disagree — this one carried the retired purple
                // #F5F1FB fill and had no way to clear itself.
                decoration: InputDecoration(
                  hintText: 'Search products',
                  hintStyle: const TextStyle(color: Colors.black38),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: Colors.black45,
                  ),
                  suffixIcon: _productSearchController.text.isEmpty
                      ? null
                      : IconButton(
                          splashRadius: 18,
                          tooltip: 'Clear search',
                          onPressed: () {
                            _productSearchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFEAEAEF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFEAEAEF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${visibleProducts.length} of ${state.products.length} products',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
        ],
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFE8E8EC)),
        const SizedBox(height: 14),
        Expanded(
          child: visibleProducts.isEmpty
              ? Center(
                  child: Text(
                    'No products match "${_productSearchController.text}".',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.black45),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Four across, dropping to three or two only when four
                    // would leave each card too narrow to read a product name
                    // in. A hard `crossAxisCount: 4` looks right on the
                    // machine it was tuned on and unusable on a laptop.
                    const gap = 12.0;
                    const minCardWidth = 150.0;
                    final columns = _columnsFor(
                      constraints.maxWidth,
                      gap,
                      minCardWidth,
                    );
                    final cardWidth =
                        (constraints.maxWidth - (columns - 1) * gap) / columns;

                    // mainAxisExtent, not childAspectRatio: the card splits
                    // its height evenly between image and details, and the
                    // details half needs ~100px for name, price and the Add
                    // button. A pure ratio lets that half shrink with the
                    // column width until the button is clipped.
                    final extent = math.max(cardWidth / 0.72, 208.0);

                    return GridView.builder(
                      itemCount: visibleProducts.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: gap,
                        crossAxisSpacing: gap,
                        mainAxisExtent: extent,
                      ),
                      itemBuilder: (context, i) {
                        final product = visibleProducts[i];
                        final inStock = product.stockQuantity > 0;
                        return PosProductCard(
                          product: product,
                          isEnabled: inStock,
                          onTap: () => _showVariantPicker(context, product),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _cartPanel(BuildContext context, PosState state) {
    // Not shown when the method presents a QR: the reference moves into the
    // QR dialog at checkout, and asking for it in both places would have the
    // cashier type it twice.
    final requiresPaymentExtraField =
        state.requiresPaymentExtraField && !state.requiresQrPresentment;
    final extraFieldLabel = state.selectedExtraFieldLabel;
    const subtleInputBg = Color(0xFFF5F1FB);

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current order',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Customer name',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
          const SizedBox(height: 6),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: subtleInputBg,
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
                borderSide: BorderSide.none,
              ),
            ),
            controller: _customerNameController,
            onChanged: context.read<PosCubit>().updateCustomerName,
          ),
          const SizedBox(height: 8),
          Text(
            'Payment method',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.paymentMethods.map((m) {
              final isSelected =
                  m.name.trim().toUpperCase() ==
                  state.selectedPaymentMethod.trim().toUpperCase();
              return _PaymentMethodOption(
                label: m.name,
                icon: _iconForPaymentMethod(m.name),
                isSelected: isSelected,
                onTap: () =>
                    context.read<PosCubit>().updatePaymentMethod(m.name),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (requiresPaymentExtraField)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  extraFieldLabel ?? 'Additional info',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.black45),
                ),
                const SizedBox(height: 6),
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: subtleInputBg,
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
                      borderSide: BorderSide.none,
                    ),
                  ),
                  controller: _paymentExtraFieldController,
                  onChanged: context
                      .read<PosCubit>()
                      .updatePaymentExtraFieldValue,
                ),
              ],
            ),
          // Shown because the payment method's receipt section asks for it,
          // not because the method is named "CASH" — a future method that
          // also gives change needs no change here.
          if (state.requiresCashTendered)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash received',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.black45),
                ),
                const SizedBox(height: 6),
                TextField(
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: subtleInputBg,
                    hintText: formatAmount(state.total),
                    hintStyle: const TextStyle(color: Colors.black38),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 12, right: 6),
                      child: Text(
                        'PHP',
                        style: TextStyle(color: Colors.black45, fontSize: 13.5),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
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
                      borderSide: BorderSide.none,
                    ),
                  ),
                  controller: _cashTenderedController,
                  onChanged: context.read<PosCubit>().updateCashTendered,
                ),
                const SizedBox(height: 6),
                // Live, because the cashier is counting notes into their hand
                // while they read it — waiting for the confirm dialog would be
                // one step too late to be useful.
                _ChangeDueLine(
                  changeDue: state.changeDue,
                  isShort:
                      state.cashTendered.trim().isNotEmpty &&
                      state.changeDue == null,
                ),
              ],
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: state.cart.length,
              itemBuilder: (context, i) {
                final item = state.cart[i];
                return _CartItemEntrance(
                  // Identity-keyed: the cubit mutates CartItem in place on
                  // qty change, so the same object/key survives increments
                  // and the entrance animation only plays once, on add.
                  key: ValueKey(identityHashCode(item)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: ProductThumbnail(
                              imagePath: item.product.imagePath,
                              imageBytes: item.product.imageBytes,
                              borderRadius: BorderRadius.circular(8),
                              iconSize: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.cartLabel,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 3),
                                _NumericCrossfade(
                                  text: formatPeso(item.lineTotal),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _QtyStepperButton(
                                icon: Icons.remove,
                                filled: false,
                                onTap: () => context
                                    .read<PosCubit>()
                                    .decrementCartItem(i),
                              ),
                              SizedBox(
                                width: 24,
                                child: _NumericCrossfade(
                                  text: '${item.quantity}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              _QtyStepperButton(
                                icon: Icons.add,
                                filled: true,
                                onTap: () async {
                                  final ok = await context
                                      .read<PosCubit>()
                                      .incrementCartItem(i);
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Cannot exceed available stock for this item.',
                                        ),
                                      ),
                                    );
                                  }
                                },
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detail Payment',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                // With the order-level discount gone, Subtotal and Total
                // would print the same figure twice. The line that earns its
                // place is what the subtotal is made of.
                Row(
                  children: [
                    Text(
                      state.cart.length == 1
                          ? '1 item'
                          : '${state.cart.length} items',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${state.cart.fold<int>(0, (sum, item) => sum + item.quantity)} unit(s)',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _DashedDivider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'Total Payment',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _NumericCrossfade(
                      text: formatPeso(state.total),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: state.cart.isEmpty
                      ? null
                      : () => context.read<PosCubit>().cancelDraft(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: state.cart.isEmpty
                      ? null
                      : () async {
                          // Resolved before any await: completing a sale
                          // reloads three cubits, and the confirmation must
                          // still reach the user afterwards.
                          final messenger = ScaffoldMessenger.of(context);
                          final posCubit = context.read<PosCubit>();
                          final dashboardCubit = context.read<DashboardCubit>();
                          final ordersCubit = context.read<OrdersCubit>();
                          // Skipped for QR methods: their reference is typed
                          // into the QR dialog below, after the customer has
                          // actually paid, so demanding it here would block a
                          // sale on a number that cannot exist yet.
                          if (!state.requiresQrPresentment &&
                              state.requiresPaymentExtraField &&
                              state.paymentExtraFieldValue.trim().isEmpty) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${state.selectedExtraFieldLabel ?? 'Additional field'} is required for selected payment method.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (!state.cashTenderedIsSufficient) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  state.cashTendered.trim().isEmpty
                                      ? 'Enter the cash received before finishing the sale.'
                                      : 'Cash received must cover ${formatPeso(state.total)}.',
                                ),
                              ),
                            );
                            return;
                          }
                          // Show the code, take the reference, and only then
                          // confirm. Cancelling here commits nothing: an
                          // e-wallet payment that never arrived is the ordinary
                          // reason for backing out at this point.
                          if (state.requiresQrPresentment) {
                            final reference = await showQrPaymentDialog(
                              context: context,
                              paymentMethod: state.selectedPaymentMethod,
                              qrBytes: state.selectedPaymentQr!,
                              amount: state.total,
                              extraFieldLabel: state.selectedExtraFieldLabel,
                            );
                            if (reference == null) return;
                            posCubit.updatePaymentExtraFieldValue(reference);
                          }
                          if (!context.mounted) return;
                          final confirmed = await _confirmSale(
                            context,
                            // Re-read: the QR dialog just wrote the reference
                            // into the cubit, and the captured `state` above
                            // still has the empty value it had on tap.
                            posCubit.state,
                          );
                          if (!confirmed) return;
                          final receipt = await posCubit.completeSale(
                            user: widget.user,
                          );
                          if (receipt == null) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Some items are out of stock. Please review cart quantities.',
                                ),
                              ),
                            );
                            return;
                          }
                          await dashboardCubit.load(widget.user);
                          await ordersCubit.load();
                          // The sale is already committed, so a failure to
                          // print is reported inside the dialog rather than
                          // being allowed to suppress the confirmation below.
                          if (context.mounted) {
                            await showReceiptPrintDialog(
                              context: context,
                              data: receipt,
                            );
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(milliseconds: 1800),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              content: const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Sale completed.',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                  child: const Text('Finish'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return formatDate(date);
  }

  /// Best-effort icon for a payment method name. Methods are free-text
  /// (configured per company in Settings), so this is a heuristic, not a
  /// lookup table — recognizable icons speed up scanning (Jakob's Law:
  /// a wallet/card/cash glyph maps to what people already expect from
  /// checkout flows) without requiring every method to declare one.
  IconData _iconForPaymentMethod(String name) {
    final n = name.trim().toLowerCase();
    if (n.contains('cash')) return Icons.payments_outlined;
    if (n.contains('card') || n.contains('credit') || n.contains('debit')) {
      return Icons.credit_card_outlined;
    }
    if (n.contains('bank') || n.contains('transfer')) {
      return Icons.account_balance_outlined;
    }
    if (n.contains('qr')) return Icons.qr_code_scanner_outlined;
    if (n.contains('gcash') || n.contains('pay') || n.contains('wallet')) {
      return Icons.account_balance_wallet_outlined;
    }
    return Icons.payment_outlined;
  }

  /// Confirms, deletes, and refreshes what the deletion changed.
  ///
  /// Everything is resolved off `context` up front: deleting the bazaar
  /// removes the very card this was called from, so by the time the awaits
  /// finish, looking anything up through that context would be resolving
  /// against a dead element -- which is why the success message could
  /// silently go missing.
  Future<void> _deleteEvent(BuildContext context, BazaarEvent event) async {
    final messenger = ScaffoldMessenger.of(context);
    final posCubit = context.read<PosCubit>();
    final dashboardCubit = context.read<DashboardCubit>();
    final inventoryCubit = context.read<InventoryCubit>();

    // Refused before asking. Putting up a confirmation for something that
    // cannot happen only to fail afterwards is worse than saying so up front.
    final blocked = posCubit.state.deleteBlockedReason(event);
    if (blocked != null) {
      messenger.showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete Bazaar',
      message:
          'Delete "${event.name}"? Any stock allocated to it goes back to '
          'the master inventory. This cannot be undone.',
      confirmLabel: 'Delete',
      tone: ConfirmationTone.destructive,
    );
    if (confirmed != true) {
      return;
    }

    // The success message used to be printed unconditionally. When the server
    // refused, the bazaar stayed in the list with nothing said about why, so a
    // delete that plainly had not happened looked like the screen was stale.
    try {
      await posCubit.deleteEventFromPos(user: widget.user, event: event);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } on StateError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    await dashboardCubit.load(widget.user);
    await inventoryCubit.load();
    messenger.showSnackBar(
      const SnackBar(content: Text('Bazaar deleted successfully.')),
    );
  }

  /// Everything known about a bazaar, and the two things you can do to it.
  ///
  /// Replaces a kebab menu, which promised a menu and said nothing about what
  /// was in it. Edit and Delete now sit beside the facts they act on -- the
  /// dates being changed, the staff being kept, the stock at risk -- rather
  /// than in a floating list of two words.
  Future<void> _showEventInfoDialog(
    BuildContext context,
    PosState state,
    BazaarEvent event,
  ) async {
    final authRepository = context.read<AuthRepository>();
    final staffCubit = context.read<StaffCubit>();
    final settingsRepository = context.read<SettingsRepository>();
    final cubit = context.read<PosCubit>();

    final companies = await settingsRepository.listCompanies();
    final venue = companies
        .where((company) => company.id == event.companyId)
        .map((company) => company.name)
        .firstOrNull;
    final rostered = await authRepository.assignmentsForEvent(event.id);
    final nameById = {for (final user in staffCubit.state) user.id: user.name};
    final allocations = await cubit.eventAllocations(event.id);
    final remaining = allocations.values.fold<int>(0, (sum, q) => sum + q);

    if (!context.mounted) {
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => BazaarInfoDialog(
        event: event,
        venue: venue ?? 'Unknown venue',
        staff: [
          for (final id in rostered.keys) nameById[id] ?? 'Employee #$id',
        ],
        remainingUnits: remaining,
        formatDate: _formatDate,
        deleteBlockedReason: state.deleteBlockedReason(event),
      ),
    );

    if (!context.mounted || choice == null) {
      return;
    }
    // The modal is already closed by the time either runs, so neither opens
    // on top of the other.
    if (choice == 'edit') {
      await _showEditEventDialog(context, state, event);
    } else if (choice == 'delete') {
      await _deleteEvent(context, event);
    }
  }

  Future<void> _showEditEventDialog(
    BuildContext context,
    PosState state,
    BazaarEvent event,
  ) async {
    // Every lookup this method needs is taken before the first await, so
    // nothing is resolved through a context that may have moved on.
    final cubit = context.read<PosCubit>();
    final productRepository = context.read<ProductRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final dashboardCubit = context.read<DashboardCubit>();
    final inventoryCubit = context.read<InventoryCubit>();
    // Everything about a finished bazaar is a record rather than a plan.
    final isEnded = event.status == BazaarStatus.ended;
    DateTimeRange selectedRange = DateTimeRange(
      start: event.startDate,
      end: event.endDate,
    );
    // Staffing, and everything needed to tell who is free. Loaded here with
    // the rest so the dialog opens complete rather than filling in under the
    // user's hands.
    final authRepository = context.read<AuthRepository>();
    final staffCubit = context.read<StaffCubit>();
    final eventRepository = context.read<EventRepository>();
    final allEmployees = staffCubit.state
        .where((user) => user.role == UserRole.employee)
        .toList();
    final assignmentIdByUserId = await authRepository.assignmentsForEvent(
      event.id,
    );
    final rostered = assignmentIdByUserId.keys.toSet();
    final originalRoster = Set<int>.from(rostered);
    final eventsById = {
      for (final other in await eventRepository.listAll()) other.id: other,
    };

    final existingAllocations = await cubit.eventAllocations(event.id);
    final allocationItems = await productRepository.allocationItems();
    final allocations = <String, int>{};
    final maxByKey = <String, int>{};

    for (final item in allocationItems) {
      final allocated = existingAllocations[item.allocationKey] ?? 0;
      allocations[item.allocationKey] = allocated;
      maxByKey[item.allocationKey] = item.availableQuantity + allocated;
    }

    if (!context.mounted) return;

    final result = await showDialog<_EditBazaarResult>(
      context: context,
      builder: (dialogContext) => _EditBazaarDialog(
        event: event,
        isEnded: isEnded,
        initialName: event.name,
        initialRange: selectedRange,
        allocationItems: allocationItems,
        initialAllocations: allocations,
        maxByKey: maxByKey,
        allEmployees: allEmployees,
        initialRoster: rostered,
        eventsById: eventsById,
        formatDate: _formatDate,
      ),
    );

    if (result == null || !context.mounted) {
      return;
    }

    final ok = await cubit.updateEventFromPos(
      user: widget.user,
      event: event,
      name: result.name.isEmpty ? event.name : result.name,
      startDate: result.range.start,
      endDate: result.range.end,
      newAllocations: result.allocations,
    );

    // Only the difference is written. Re-posting the whole roster would rely
    // on the server rejecting duplicates, and removals would never happen at
    // all -- a roster that can only grow cannot be corrected.
    for (final id in originalRoster.difference(result.roster)) {
      final assignmentId = assignmentIdByUserId[id];
      if (assignmentId != null) {
        await authRepository.unassignEmployeeFromBazaar(
          eventId: event.id,
          assignmentId: assignmentId,
          employeeId: id,
        );
      }
    }
    final added = result.roster.difference(originalRoster).toList();
    if (added.isNotEmpty) {
      await authRepository.assignEmployeesToBazaar(
        eventId: event.id,
        employeeIds: added,
      );
    }
    await staffCubit.load();

    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to update bazaar. Check stock allocations and try again.',
          ),
        ),
      );
      return;
    }

    await dashboardCubit.load(widget.user);
    await inventoryCubit.load();
    messenger.showSnackBar(
      const SnackBar(content: Text('Bazaar updated successfully.')),
    );
  }

  Future<bool> _confirmSale(BuildContext context, PosState state) async {
    return showConfirmSaleDialog(
      context: context,
      total: state.total,
      itemCount: state.cart.length,
      unitCount: state.cart.fold<int>(0, (sum, item) => sum + item.quantity),
      paymentMethod: state.selectedPaymentMethod,
      paymentIcon: _iconForPaymentMethod(state.selectedPaymentMethod),
      extraFieldLabel: state.requiresPaymentExtraField
          ? (state.selectedExtraFieldLabel ?? 'Reference')
          : null,
      extraFieldValue: state.paymentExtraFieldValue,
      customerName: state.customerName,
      cashTendered: state.requiresCashTendered ? state.cashTenderedValue : null,
      changeDue: state.requiresCashTendered ? state.changeDue : null,
    );
  }

  Future<void> _showVariantPicker(BuildContext context, Product product) async {
    final cubit = context.read<PosCubit>();
    final groups = await cubit.variantGroupsForProduct(product.id);
    final optionsByGroup = <List<ProductVariantOption>>[];
    for (final group in groups) {
      optionsByGroup.add(await cubit.variantOptionsForGroup(group.id));
    }
    final combinationStocks = await cubit.combinationStocksForProduct(
      product.id,
    );

    final hasGroupA = groups.isNotEmpty;
    final hasGroupB = groups.length > 1;
    final groupA = hasGroupA ? groups[0] : null;
    final groupB = hasGroupB ? groups[1] : null;
    final optionsA = hasGroupA
        ? optionsByGroup[0]
        : const <ProductVariantOption>[];
    final optionsB = hasGroupB
        ? optionsByGroup[1]
        : const <ProductVariantOption>[];

    ProductVariantOption? selectedA;
    ProductVariantOption? selectedB;
    int quantity = 1;
    bool showMaxWarning = false;

    if (!context.mounted) {
      return;
    }

    int stockFor(ProductVariantOption? a, ProductVariantOption? b) {
      return combinationStocks[(a?.id, b?.id)] ?? 0;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final selectionComplete =
                (!hasGroupA || selectedA != null) &&
                (!hasGroupB || selectedB != null);
            final currentStock = selectionComplete
                ? stockFor(selectedA, selectedB)
                : 0;

            final cart = context.read<PosCubit>().state.cart;
            final inCartQty = cart
                .where(
                  (item) =>
                      item.product.id == product.id &&
                      item.variantOptionIdA == selectedA?.id &&
                      item.variantOptionIdB == selectedB?.id,
                )
                .fold<int>(0, (sum, item) => sum + item.quantity);

            final availableForSelection = currentStock - inCartQty;
            final maxSelectable = availableForSelection < 0
                ? 0
                : availableForSelection;
            if (quantity > maxSelectable && maxSelectable > 0) {
              quantity = maxSelectable;
            }
            final canAdd =
                quantity > 0 && selectionComplete && maxSelectable > 0;
            final extraPrice =
                (selectedA?.extraPrice ?? 0) + (selectedB?.extraPrice ?? 0);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (hasGroupA) ...[
                    Text(
                      groupA!.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: optionsA.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 2.6,
                          ),
                      itemBuilder: (context, index) {
                        final option = optionsA[index];
                        final optionStock = hasGroupB
                            ? optionsB.fold<int>(
                                0,
                                (sum, b) => sum + stockFor(option, b),
                              )
                            : stockFor(option, null);
                        final isSelected = selectedA?.id == option.id;
                        return SelectableOptionButton(
                          label: option.value,
                          isSelected: isSelected,
                          isDisabled: optionStock <= 0,
                          borderRadius: 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          onTap: optionStock <= 0
                              ? null
                              : () {
                                  setState(() {
                                    selectedA = option;
                                    selectedB = null;
                                    quantity = 1;
                                    showMaxWarning = false;
                                  });
                                },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (hasGroupB) ...[
                    Text(
                      groupB!.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: optionsB.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 2.2,
                          ),
                      itemBuilder: (context, index) {
                        final option = optionsB[index];
                        final stock = selectedA == null
                            ? 0
                            : stockFor(selectedA, option);
                        final disabled = selectedA == null || stock <= 0;
                        final isSelected = selectedB?.id == option.id;
                        return SelectableOptionButton(
                          label: option.value,
                          isSelected: isSelected,
                          isDisabled: disabled,
                          onTap: disabled
                              ? null
                              : () {
                                  setState(() {
                                    selectedB = option;
                                    quantity = 1;
                                    showMaxWarning = false;
                                  });
                                },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  AnimatedSize(
                    // Stock/hint copy used to pop in and shove the quantity
                    // row down instantly as soon as a chip was tapped.
                    // Growing the space smooths that layout jump.
                    duration: AppMotion.small,
                    curve: AppMotion.easeOut,
                    alignment: Alignment.topLeft,
                    child: AnimatedSwitcher(
                      duration: AppMotion.small,
                      switchInCurve: AppMotion.easeOut,
                      switchOutCurve: AppMotion.easeOut,
                      child: selectionComplete
                          ? Text(
                              'Stock: $maxSelectable',
                              key: const ValueKey('stock'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                            )
                          : hasGroupA
                          ? Text(
                              hasGroupB && selectedA != null
                                  ? 'Select a ${groupB!.name.toLowerCase()} to see stock.'
                                  : 'Select a ${groupA!.name.toLowerCase()} to see stock.',
                              key: const ValueKey('hint'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.black54),
                            )
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ),
                  AnimatedSize(
                    duration: AppMotion.small,
                    curve: AppMotion.easeOut,
                    alignment: Alignment.topLeft,
                    child: AnimatedOpacity(
                      duration: AppMotion.small,
                      curve: AppMotion.easeOut,
                      opacity: showMaxWarning ? 1 : 0,
                      child: showMaxWarning
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'You have reached the maximum quantity available for this item.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      IconButton(
                        onPressed: quantity <= 1
                            ? null
                            : () => setState(() {
                                quantity -= 1;
                                showMaxWarning = false;
                              }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 40,
                        child: _NumericCrossfade(
                          text: '$quantity',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: maxSelectable <= 0
                            ? null
                            : () => setState(() {
                                if (quantity >= maxSelectable) {
                                  showMaxWarning = true;
                                } else {
                                  quantity += 1;
                                  showMaxWarning = false;
                                }
                              }),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Spacer(),
                      _NumericCrossfade(
                        text: formatPeso(
                          (product.basePrice + extraPrice) * quantity,
                        ),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canAdd
                          ? () async {
                              final added = await cubit.addToCart(
                                product,
                                groupA: groupA,
                                optionA: selectedA,
                                groupB: groupB,
                                optionB: selectedB,
                                quantity: quantity,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              if (!added) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Cannot add more than available stock.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(context);
                            }
                          : null,
                      child: const Text('Add to Cart'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// A horizontal, underline-style category tab. Reduces the category picker
/// from a wrapping grid of chips to a single scannable row (Hick's Law:
/// fewer, linearly-ordered choices are faster to scan than a wrapped grid).
/// A payment method option rendered as an always-visible icon+label tile
/// instead of a hidden dropdown menu. With typically 2-4 methods, showing
/// every choice up front (recognition over recall) removes a full
/// open-menu-then-pick interaction, and the icon lets it be recognized
/// before the label is even read. Reuses the same selected/unselected
/// color language as the variant picker (light-purple vs. yellow) so the
/// whole POS screen reads as one system rather than a mix of native form
/// controls and custom ones.
/// Columns for the product grid: four when each card can still be at least
/// [minCardWidth] wide, otherwise as many as fit, never fewer than two.
int _columnsFor(double available, double gap, double minCardWidth) {
  for (var columns = 4; columns > 2; columns--) {
    if ((available - (columns - 1) * gap) / columns >= minCardWidth) {
      return columns;
    }
  }
  return 2;
}

/// Back-link plus the bazaar you are selling at.
///
/// Replaces an `OutlinedButton` reading "Back to Bazaar Selection" that sat at
/// the same visual weight as the search field. Leaving a bazaar happens once a
/// shift; the crumb sizes the action to that, and spends the space it frees on
/// naming the bazaar, which the panel never showed at all.
class _BazaarBreadcrumb extends StatelessWidget {
  const _BazaarBreadcrumb({required this.eventName, required this.onBack});

  final String eventName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    size: 17,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Bazaars',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '/',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black26),
          ),
        ),
        // The current crumb is not a link — there is nowhere for it to go.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            eventName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodOption extends StatefulWidget {
  const _PaymentMethodOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_PaymentMethodOption> createState() => _PaymentMethodOptionState();
}

class _PaymentMethodOptionState extends State<_PaymentMethodOption> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Inverted 2026-08-03: selected is now a solid purple fill with amber
    // content, where it used to be an amber fill with purple content. Same
    // two colours, opposite assignment — a filled tile carries more weight
    // than a tinted one, so the chosen method reads from further away.
    final backgroundColor = widget.isSelected
        ? AppColors.primary
        : AppColors.primaryLight;
    final contentColor = widget.isSelected ? AppColors.accent : AppColors.text;

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: AppMotion.feedback,
      curve: AppMotion.easeOut,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          // 44px-tall tap target: comfortable for a mouse pointer and
          // meets the ~44dp minimum recommended for touch (Fitts's Law —
          // this is a checkout-critical control, not a dense list item).
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: contentColor),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: AppMotion.small,
                curve: AppMotion.easeOut,
                style:
                    Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: contentColor,
                      fontWeight: widget.isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ) ??
                    TextStyle(color: contentColor),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bazaar card for the "Select Active Bazaar" grid. Deliberately flat
/// (border instead of a heavy drop shadow) for a minimalist look, and the
/// button label changes with status ("Starts <date>" / "Bazaar ended")
/// instead of always reading "Open POS" while disabled — a plain grayed
/// button that still says "Open POS" tells the user *that* it's blocked
/// but not *why*, which is exactly the ambiguity Nielsen's "visibility of
/// system status" heuristic warns against.
/// A single small filter control that cycles All → Upcoming → Ongoing →
/// Ended → All on each tap, instead of 3 separate toggle buttons sitting
/// next to the search bar. Deliberately sized like a tag/badge, not a
/// button: this is a secondary, occasional-use control, not a primary
/// action, so Fitts's Law doesn't call for a large target here — it calls
/// for one sized to how often and how precisely it's actually used.
/// Reuses the exact status colors already shown on `_BazaarCard`'s badge
/// (green/amber/red) so the filter reads as "the same status," not a new
/// color language layered on top.
class _BazaarCard extends StatefulWidget {
  const _BazaarCard({
    required this.event,
    required this.canManage,
    required this.formatDate,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onShowInfo,
    this.deleteBlockedReason,
  });

  final BazaarEvent event;
  final bool canManage;
  final String Function(DateTime) formatDate;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  /// Opens the details modal, from which edit and delete are reached.
  final VoidCallback onShowInfo;
  final VoidCallback onDelete;

  /// Why this bazaar cannot be deleted, or null when it can be. Shown rather
  /// than merely disabling the control, since a dead button explains nothing.
  final String? deleteBlockedReason;

  @override
  State<_BazaarCard> createState() => _BazaarCardState();
}

class _BazaarCardState extends State<_BazaarCard> {
  bool _pressed = false;

  static const Map<BazaarStatus, Color> _statusColors = {
    BazaarStatus.ongoing: AppColors.statusOngoing,
    BazaarStatus.upcoming: AppColors.statusUpcoming,
    BazaarStatus.ended: AppColors.statusEnded,
  };

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final enabled = event.status == BazaarStatus.ongoing;
    final statusColor = _statusColors[event.status] ?? AppColors.error;
    final buttonLabel = switch (event.status) {
      BazaarStatus.ongoing => 'Open POS',
      BazaarStatus.upcoming => 'Starts ${widget.formatDate(event.startDate)}',
      BazaarStatus.ended => 'Bazaar ended',
    };

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: AppMotion.feedback,
      curve: AppMotion.easeOut,
      child: InkWell(
        onTap: enabled ? widget.onOpen : null,
        onHighlightChanged: enabled
            ? (value) => setState(() => _pressed = value)
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: enabled ? AppColors.surface : const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEDEDF1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      event.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (widget.canManage)
                    // An "i" rather than a kebab. A kebab promises a menu and
                    // says nothing about what is in it; this says there is
                    // something to read, and the two actions live inside
                    // where they can be shown against the bazaar they act on.
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        splashRadius: 16,
                        tooltip: 'Bazaar details',
                        onPressed: widget.onShowInfo,
                        icon: const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.status.name.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${widget.formatDate(event.startDate)} – ${widget.formatDate(event.endDate)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: ElevatedButton(
                  onPressed: enabled ? widget.onOpen : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: const Color(0xFFE7E7EC),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.black45,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyStepperButton extends StatelessWidget {
  const _QtyStepperButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.primary : const Color(0xFFEDEDF1),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 15,
            color: filled ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

/// Change owed, or a note that the amount tendered is still short.
///
/// Occupies the same slot in both states so the Finish button does not shift
/// under the cashier's finger as they type.
class _ChangeDueLine extends StatelessWidget {
  const _ChangeDueLine({required this.changeDue, required this.isShort});

  final double? changeDue;
  final bool isShort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isShort) {
      return Text(
        'Not enough to cover the total.',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
      );
    }
    if (changeDue == null) {
      return Text(
        'Enter the amount handed over.',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black38),
      );
    }
    return Row(
      children: [
        Text(
          'Change',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const Spacer(),
        Text(
          formatPeso(changeDue!),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }
}

/// A light dashed rule, used above the grand total to separate it from the
/// line items it sums — a common receipt/invoice convention (Jakob's Law).
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dashWidth = 5.0;
          const gapWidth = 4.0;
          final count = (constraints.maxWidth / (dashWidth + gapWidth)).floor();
          return Row(
            children: List.generate(
              count,
              (_) => Padding(
                padding: const EdgeInsets.only(right: gapWidth),
                child: Container(
                  width: dashWidth,
                  height: 1,
                  color: Colors.black26,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Grows and fades a cart line in when it first mounts (new item added).
/// Keyed by the cart item's identity, so re-renders from a quantity change
/// (same object, same key) don't replay the animation — only a genuinely
/// new line does.
class _CartItemEntrance extends StatefulWidget {
  const _CartItemEntrance({required super.key, required this.child});

  final Widget child;

  @override
  State<_CartItemEntrance> createState() => _CartItemEntranceState();
}

class _CartItemEntranceState extends State<_CartItemEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.entrance,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.easeOut,
    );
    return FadeTransition(
      opacity: curved,
      child: SizeTransition(
        sizeFactor: curved,
        alignment: const Alignment(-1.0, -1.0),
        child: widget.child,
      ),
    );
  }
}

/// The selectable option button used for both variant groups (Color chips
/// and the Size grid) in the product modal. One shared widget so both
/// groups read as the same control (internal consistency), with a hard
/// color-coded distinction between states instead of a shade difference:
/// unselected = flat light-purple fill + black label; selected = flat
/// yellow fill + purple label. The color swap itself (not a border or
/// checkmark) is what tells the user which option is active — a Von
/// Restorff-style pop that's readable at a glance across a busy grid.
/// Crossfades a short numeric/price readout when its text changes, so a
/// quantity or total update registers as a small confirmation rather than
/// an instant, jarring teleport. Fade-only (no scale) to keep digits
/// legible for something the cashier is actively reading.
class _NumericCrossfade extends StatelessWidget {
  const _NumericCrossfade({required this.text, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.small,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      child: Text(
        text,
        key: ValueKey(text),
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}

/// A bazaar's facts, and the two things that can be done to it.
///
/// Public so the dialog can be exercised on its own; nothing else builds it.
///
/// Deliberately quiet. It is read far more often than it is acted on, so the
/// facts carry the weight and the actions sit at the bottom in the secondary
/// tier -- full-width buttons here would make a reference card look like a
/// decision. Delete rests as an outline and only turns red on hover, the same
/// way a destructive row action does elsewhere: a panel of facts should not
/// look hazardous while you are reading it.
class BazaarInfoDialog extends StatelessWidget {
  const BazaarInfoDialog({
    super.key,
    required this.event,
    required this.venue,
    required this.staff,
    required this.remainingUnits,
    required this.formatDate,
    this.deleteBlockedReason,
  });

  final BazaarEvent event;
  final String venue;
  final List<String> staff;
  final int remainingUnits;
  final String Function(DateTime) formatDate;

  /// Why this bazaar is protected from deletion, or null when it can go.
  final String? deleteBlockedReason;

  static const Map<BazaarStatus, Color> _statusColors = {
    BazaarStatus.ongoing: AppColors.statusOngoing,
    BazaarStatus.upcoming: AppColors.statusUpcoming,
    BazaarStatus.ended: AppColors.statusEnded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[event.status] ?? AppColors.error;
    final isEnded = event.status == BazaarStatus.ended;

    return Dialog(
      backgroundColor: Colors.white,
      // 14 — a modal floats above the page and earns a step more shape than
      // the cards behind it.
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                          event.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          venue,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // The one isolated element. Status is what changes what you can
              // do here, so it is the only thing wearing colour.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.status.name.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _InfoRow(
                label: 'Dates',
                value:
                    '${formatDate(event.startDate)} – '
                    '${formatDate(event.endDate)}',
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Staff',
                value: staff.isEmpty ? 'Nobody assigned' : staff.join(', '),
                // An unstaffed bazaar is a problem, not a blank. Said in the
                // error colour so it is noticed here rather than on the
                // morning it opens.
                valueColor: staff.isEmpty ? AppColors.error : null,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Payment',
                value: event.acceptedPaymentMethods.isEmpty
                    ? 'CASH'
                    : event.acceptedPaymentMethods.join(' · '),
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: isEnded ? 'Unreturned stock' : 'Stock left',
                value: '${formatCount(remainingUnits)} units',
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: Color(0xFFEDEDF1)),
              const SizedBox(height: 16),
              // Auto-width and right-aligned: two occasional actions, not a
              // pair of calls to action.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _QuietDeleteButton(
                    onPressed: deleteBlockedReason == null
                        ? () => Navigator.pop(context, 'delete')
                        : null,
                    blockedReason: deleteBlockedReason,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, 'edit'),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    label: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label above, value below, both left-aligned at the same x.
///
/// Stacked rather than set in a sentence: every value lands at one x and one
/// weight, so the eye scans a column instead of reading four lines to find
/// the one it wants.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.black38,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Rests neutral, turns red on hover.
///
/// A delete that is red at rest makes a panel you are only reading look
/// hazardous; one that never turns red gives no warning at the moment of
/// intent. This does both, matching the row actions elsewhere in the app.
class _QuietDeleteButton extends StatefulWidget {
  const _QuietDeleteButton({required this.onPressed, this.blockedReason});

  /// Null disables the button, in which case [blockedReason] says why.
  final VoidCallback? onPressed;

  final String? blockedReason;

  @override
  State<_QuietDeleteButton> createState() => _QuietDeleteButtonState();
}

class _QuietDeleteButtonState extends State<_QuietDeleteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final blocked = widget.onPressed == null;
    final color = blocked
        ? Colors.black26
        : (_hovered ? AppColors.error : Colors.black45);
    // A disabled control has to account for itself, so the reason rides on the
    // button rather than only appearing after someone presses it.
    return Tooltip(
      message: widget.blockedReason ?? '',
      // An empty message would otherwise draw an empty tooltip.
      triggerMode: blocked
          ? TooltipTriggerMode.longPress
          : TooltipTriggerMode.manual,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: AppMotion.feedback,
          curve: AppMotion.easeOut,
          child: OutlinedButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(Icons.delete_outline, size: 16, color: color),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(
                color: _hovered && !blocked
                    ? AppColors.error
                    : const Color(0xFFDCDCE3),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            label: Text('Delete', style: TextStyle(color: color)),
          ),
        ),
      ),
    );
  }
}

/// What the Edit Bazaar dialog agreed to, or null if it was cancelled.
class _EditBazaarResult {
  const _EditBazaarResult({
    required this.name,
    required this.range,
    required this.allocations,
    required this.roster,
  });

  final String name;
  final DateTimeRange range;
  final Map<String, int> allocations;
  final Set<int> roster;
}

/// Editing a bazaar: what it is called, when it runs, who works it, what it
/// sells.
///
/// Four questions, so four labelled blocks rather than one column of controls
/// -- the old version ran a text field, a date button, a roster and eighty
/// stock rows together with nothing to say where one ended.
///
/// The stock list is grouped by product. Every row used to restate the product
/// name in full ("Nike Air Max SC - Color: Triple White, Size: 36", forty
/// times over), which is most of a line spent on the one word that does not
/// change between rows. The name is printed once and the variants sit under
/// it, so what the eye scans is what actually differs.
class _EditBazaarDialog extends StatefulWidget {
  const _EditBazaarDialog({
    required this.event,
    required this.isEnded,
    required this.initialName,
    required this.initialRange,
    required this.allocationItems,
    required this.initialAllocations,
    required this.maxByKey,
    required this.allEmployees,
    required this.initialRoster,
    required this.eventsById,
    required this.formatDate,
  });

  final BazaarEvent event;
  final bool isEnded;
  final String initialName;
  final DateTimeRange initialRange;
  final List<ProductAllocationItem> allocationItems;
  final Map<String, int> initialAllocations;
  final Map<String, int> maxByKey;
  final List<AppUser> allEmployees;
  final Set<int> initialRoster;
  final Map<int, BazaarEvent> eventsById;
  final String Function(DateTime) formatDate;

  @override
  State<_EditBazaarDialog> createState() => _EditBazaarDialogState();
}

class _EditBazaarDialogState extends State<_EditBazaarDialog> {
  late final TextEditingController _name;
  late final TextEditingController _search;
  late DateTimeRange _range;
  late Map<String, int> _allocations;
  late Set<int> _roster;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _search = TextEditingController();
    _range = widget.initialRange;
    _allocations = Map<String, int>.from(widget.initialAllocations);
    _roster = Set<int>.from(widget.initialRoster);
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  int get _totalUnits =>
      _allocations.values.fold<int>(0, (sum, quantity) => sum + quantity);

  int get _linesWithStock =>
      _allocations.values.where((quantity) => quantity > 0).length;

  /// Allocation rows grouped under their product, filtered by the search box.
  Map<String, List<ProductAllocationItem>> get _grouped {
    final query = _search.text.trim().toLowerCase();
    final grouped = <String, List<ProductAllocationItem>>{};
    for (final item in widget.allocationItems) {
      if (query.isNotEmpty &&
          !item.product.name.toLowerCase().contains(query) &&
          !item.displayLabel.toLowerCase().contains(query)) {
        continue;
      }
      grouped.putIfAbsent(item.product.name, () => []).add(item);
    }
    return grouped;
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Past days are closed, so a bazaar cannot be dragged backwards over days
    // it never ran. One that already started keeps its own start as the
    // floor, or the picker could not show the range it is editing.
    final floor = _range.start.isBefore(today) ? _range.start : today;
    final picked = await showAppDateRangePicker(
      context: context,
      firstDate: floor,
      lastDate: DateTime(2035),
      initialRange: _range,
      title: 'Bazaar dates',
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conflicts = StaffScheduling.conflicts(
      range: _range,
      employees: widget.allEmployees,
      eventsById: widget.eventsById,
      excludingEventId: widget.event.id,
    );
    final free = widget.allEmployees
        .where((e) => !_roster.contains(e.id))
        .where((e) => !conflicts.containsKey(e.id))
        .toList();
    final busy = widget.allEmployees
        .where((e) => !_roster.contains(e.id))
        .where((e) => conflicts.containsKey(e.id))
        .toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        // Wider than a form dialog usually is, because the stock list has a
        // label and a stepper side by side and neither should wrap.
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header and footer are outside the scroll view. The old version
            // scrolled everything, so the first field's label slid under the
            // title and read as clipped.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Bazaar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _EditSectionLabel('Bazaar'),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _name,
                            style: theme.textTheme.bodyMedium,
                            decoration: _editFieldDecoration(
                              hint: 'Bazaar name',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _DateFieldButton(
                            label:
                                '${widget.formatDate(_range.start)} – '
                                '${widget.formatDate(_range.end)}',
                            enabled: !widget.isEnded,
                            onPressed: _pickDates,
                          ),
                        ),
                      ],
                    ),
                    if (widget.isEnded) ...[
                      const SizedBox(height: 6),
                      Text(
                        'This bazaar has ended. Its dates, staffing and stock '
                        'are fixed — send stock back through Inventory '
                        'Reconciliation.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const _EditSectionLabel('Staffing'),
                    const SizedBox(height: 8),
                    if (_roster.isEmpty)
                      Text(
                        'Nobody is assigned to this bazaar.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final id in _roster)
                            _StaffChip(
                              name:
                                  widget.allEmployees
                                      .where((e) => e.id == id)
                                      .map((e) => e.name)
                                      .firstOrNull ??
                                  'Employee #$id',
                              onRemove: widget.isEnded
                                  ? null
                                  : () => setState(() => _roster.remove(id)),
                            ),
                        ],
                      ),
                    if (!widget.isEnded) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 280,
                        child: AppDropdown<AppUser>(
                          options: free,
                          selected: null,
                          labelOf: (employee) => employee.name,
                          hint: free.isEmpty
                              ? (busy.isEmpty
                                    ? 'Everyone is assigned'
                                    : 'Nobody is free on these dates')
                              : 'Add an employee',
                          leadingIcon: Icons.person_add_alt,
                          onSelected: (employee) =>
                              setState(() => _roster.add(employee.id)),
                        ),
                      ),
                      for (final employee in busy)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.event_busy_outlined,
                                size: 14,
                                color: Colors.black38,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${employee.name} — already at '
                                  '${conflicts[employee.id]}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.black45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const _EditSectionLabel('Allocated stock'),
                        const Spacer(),
                        // Says what is being committed without making the
                        // reader add up eighty rows.
                        Text(
                          '${formatCount(_totalUnits)} units · '
                          '$_linesWithStock lines',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.allocationItems.length > 8)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: theme.textTheme.bodyMedium,
                          decoration: _editFieldDecoration(
                            hint: 'Search products',
                            icon: Icons.search,
                          ),
                        ),
                      ),
                    for (final entry in _grouped.entries) ...[
                      _AllocationGroup(
                        product: entry.key,
                        items: entry.value,
                        allocations: _allocations,
                        maxByKey: widget.maxByKey,
                        enabled: !widget.isEnded,
                        onChanged: (key, value) =>
                            setState(() => _allocations[key] = value),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_grouped.isEmpty)
                      Text(
                        'No products match that search.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _EditBazaarResult(
                        name: _name.text.trim(),
                        range: _range,
                        allocations: _allocations,
                        roster: _roster,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _editFieldDecoration({required String hint, IconData? icon}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: Colors.black38),
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

/// A quiet all-caps heading over a block of the form.
class _EditSectionLabel extends StatelessWidget {
  const _EditSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.black38,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

/// Shaped like the text field beside it rather than like a button, because it
/// holds a value rather than performing an action.
class _DateFieldButton extends StatelessWidget {
  const _DateFieldButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.calendar_today_outlined : Icons.lock_outline,
              size: 15,
              color: Colors.black38,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: enabled ? AppColors.text : Colors.black45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffChip extends StatelessWidget {
  const _StaffChip({required this.name, this.onRemove});

  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: 12, right: onRemove == null ? 12 : 6),
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One product's variants, under its name.
///
/// A bordered region rather than loose rows: the product name applies to
/// everything inside it, and a boundary is what says how far "inside" reaches.
class _AllocationGroup extends StatelessWidget {
  const _AllocationGroup({
    required this.product,
    required this.items,
    required this.allocations,
    required this.maxByKey,
    required this.enabled,
    required this.onChanged,
  });

  final String product;
  final List<ProductAllocationItem> items;
  final Map<String, int> allocations;
  final Map<String, int> maxByKey;
  final bool enabled;
  final void Function(String key, int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allocated = items.fold<int>(
      0,
      (sum, item) => sum + (allocations[item.allocationKey] ?? 0),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    product,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (allocated > 0)
                  Text(
                    formatCount(allocated),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF2F2F5)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // The product name is on the header; this is only what
                      // separates one row from the next.
                      items[i].variantLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  QuantityStepper(
                    value: allocations[items[i].allocationKey] ?? 0,
                    max: maxByKey[items[i].allocationKey] ?? 0,
                    enabled: enabled,
                    onChanged: (value) =>
                        onChanged(items[i].allocationKey, value),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
