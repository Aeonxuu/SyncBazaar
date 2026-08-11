import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
import '../../widgets/date_range_picker_dialog.dart';
import '../../widgets/custom_card.dart';
import '../../widgets/product_thumbnail.dart';
import '../../widgets/selectable_option_button.dart';
import 'widgets/pos_product_card.dart';
import '../../../core/utils/formatters.dart';
import 'widgets/confirm_sale_dialog.dart';
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
  final TextEditingController _customerNameController =
      TextEditingController();
  final TextEditingController _paymentExtraFieldController =
      TextEditingController();
  final TextEditingController _cashTenderedController =
      TextEditingController();
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: TextField(
                  controller: _bazaarSearchController,
                  onChanged: (_) => setState(() {}),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search bazaars by name, status, or date',
                    hintStyle: const TextStyle(color: Colors.black38),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.black45,
                    ),
                    suffixIcon: _bazaarSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            splashRadius: 18,
                            onPressed: () {
                              _bazaarSearchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
              _StatusFilterCycleButton(
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
                        onDelete: () async {
                          // Everything is resolved off `context` up front:
                          // deleting the bazaar removes this very card from
                          // the list, so by the time the awaits below finish,
                          // looking anything up through this context would be
                          // resolving against a dead element — which is why
                          // the success message could silently go missing.
                          final messenger = ScaffoldMessenger.of(context);
                          final posCubit = context.read<PosCubit>();
                          final dashboardCubit = context.read<DashboardCubit>();
                          final inventoryCubit = context.read<InventoryCubit>();
                          final confirmed = await showConfirmationDialog(
                            context: context,
                            title: 'Delete Bazaar',
                            message:
                                'Are you sure you want to delete "${event.name}"?',
                            confirmLabel: 'Delete',
                            tone: ConfirmationTone.destructive,
                          );
                          if (confirmed != true) {
                            return;
                          }
                          await posCubit.deleteEventFromPos(
                            user: widget.user,
                            event: event,
                          );
                          await dashboardCubit.load(widget.user);
                          await inventoryCubit.load();
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Bazaar deleted successfully.'),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _productPanel(BuildContext context, PosState state) {
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
        Row(
          children: [
            // A breadcrumb rather than a bordered button. Leaving the bazaar
            // happens once a shift, so an outlined purple control gave a
            // rare action the same weight as the search field beside it
            // (Section 4's button tiers). As a crumb it also answers a
            // question the panel never used to: which bazaar am I selling at?
            _BazaarBreadcrumb(
              eventName: eventName,
              onBack: () => context.read<PosCubit>().backToEventSelection(),
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
    final requiresPaymentExtraField = state.requiresPaymentExtraField;
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
                          if (state.requiresPaymentExtraField &&
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
                          final confirmed = await _confirmSale(context, state);
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
    return '${date.month}/${date.day}/${date.year}';
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
    final nameController = TextEditingController(text: event.name);
    DateTimeRange selectedRange = DateTimeRange(
      start: event.startDate,
      end: event.endDate,
    );
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

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Bazaar'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Bazaar Name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final range = await showAppDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialRange: selectedRange,
                            title: 'Bazaar dates',
                          );
                          if (range != null) {
                            setState(() => selectedRange = range);
                          }
                        },
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(
                          '${_formatDate(selectedRange.start)} - ${_formatDate(selectedRange.end)}',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Allocated Stocks',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...allocationItems.map((item) {
                        final allocated = allocations[item.allocationKey] ?? 0;
                        final maxQty = maxByKey[item.allocationKey] ?? 0;
                        final lineLabel = item.displayLabel;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lineLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                onPressed: allocated <= 0
                                    ? null
                                    : () => setState(
                                        () => allocations[item.allocationKey] =
                                            allocated - 1,
                                      ),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('$allocated'),
                              IconButton(
                                onPressed: allocated >= maxQty
                                    ? null
                                    : () => setState(
                                        () => allocations[item.allocationKey] =
                                            allocated + 1,
                                      ),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !context.mounted) {
      return;
    }

    final ok = await cubit.updateEventFromPos(
      user: widget.user,
      event: event,
      name: nameController.text.trim().isEmpty
          ? event.name
          : nameController.text.trim(),
      startDate: selectedRange.start,
      endDate: selectedRange.end,
      newAllocations: allocations,
    );

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
class _StatusFilterCycleButton extends StatefulWidget {
  const _StatusFilterCycleButton({required this.status, required this.onTap});

  /// null means "All" (no filter applied).
  final BazaarStatus? status;
  final VoidCallback onTap;

  @override
  State<_StatusFilterCycleButton> createState() =>
      _StatusFilterCycleButtonState();
}

class _StatusFilterCycleButtonState extends State<_StatusFilterCycleButton> {
  bool _pressed = false;

  static const Map<BazaarStatus, Color> _statusColors = {
    BazaarStatus.ongoing: Color(0xFF2E7D32),
    BazaarStatus.upcoming: Color(0xFFB45309),
    BazaarStatus.ended: AppColors.error,
  };

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final color = status == null
        ? Colors.black54
        : (_statusColors[status] ?? AppColors.error);
    final label = switch (status) {
      null => 'All',
      BazaarStatus.upcoming => 'Upcoming',
      BazaarStatus.ongoing => 'Ongoing',
      BazaarStatus.ended => 'Ended',
    };

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: AppMotion.feedback,
      curve: AppMotion.easeOut,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: status == null
                ? Colors.black.withValues(alpha: 0.06)
                : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_rounded, size: 13, color: color),
              const SizedBox(width: 4),
              AnimatedDefaultTextStyle(
                duration: AppMotion.small,
                curve: AppMotion.easeOut,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BazaarCard extends StatefulWidget {
  const _BazaarCard({
    required this.event,
    required this.canManage,
    required this.formatDate,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final BazaarEvent event;
  final bool canManage;
  final String Function(DateTime) formatDate;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_BazaarCard> createState() => _BazaarCardState();
}

class _BazaarCardState extends State<_BazaarCard> {
  bool _pressed = false;

  static const Map<BazaarStatus, Color> _statusColors = {
    BazaarStatus.ongoing: Color(0xFF2E7D32),
    BazaarStatus.upcoming: Color(0xFFB45309),
    BazaarStatus.ended: AppColors.error,
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
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        splashRadius: 16,
                        icon: const Icon(
                          Icons.more_vert,
                          size: 18,
                          color: Colors.black45,
                        ),
                        onSelected: (value) {
                          if (value == 'edit') {
                            widget.onEdit();
                          } else {
                            widget.onDelete();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
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
