import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';
import '../../../models/user.dart';
import 'widgets/active_bazaars_card.dart';
import 'widgets/analyze_card.dart';
import 'widgets/average_daily_sales_card.dart';
import 'widgets/customer_history_card.dart';
import 'widgets/dashboard_kpi_card.dart';

/// The one gap between any two blocks on this screen — between KPI cards in
/// either axis, between the two cards in the row below them, and between the
/// KPI grid and that row.
///
/// It was three different numbers: a 12px grid gutter, a 16px gap between the
/// chart and Analyze cards, and 8px between the two groups. Nothing about the
/// layout justified the difference, and unequal gutters read as misalignment
/// rather than as hierarchy (Gestalt proximity — equal spacing is what makes a
/// set of tiles read as one group).
const double _dashboardGutter = 16;

/// Height of every KPI tile, at every window size.
///
/// Its content is a constant 84px — a 20px label row and a 20px value inside
/// 16px padding. The extra sits between the two, put there by the card's
/// `spaceBetween`, so the padding stays symmetric.
const double _kpiCardHeight = 96;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    required this.onOpenPos,
  });

  final AppUser user;
  final VoidCallback onOpenPos;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Both sections are hidden by default and revealed by tapping their
  // matching KPI card — the raw list of active bazaars and the full
  // transaction log are detail views, not something every visit to the
  // dashboard needs to show. Hiding them by default is what actually
  // reduces redundancy; the KPI card doubles as both the summary number
  // and the entry point to the detail behind it.
  bool _showBazaarSummary = false;
  bool _showTransactionHistory = false;

  @override
  Widget build(BuildContext context) {
    final dashboardCubit = context.read<DashboardCubit>();

    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        return Container(
          color: AppColors.background,
          child: RefreshIndicator(
            onRefresh: () => dashboardCubit.load(widget.user),
            color: AppColors.primary,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // Equal on all four sides: the KPI grid's inset from the
                  // left and right edges used to be 24 against 16 from the top.
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, dashboardCubit, width, state),
                      const SizedBox(height: _dashboardGutter),
                      _buildKpiSection(width, state),
                      AnimatedSize(
                        duration: AppMotion.entrance,
                        curve: AppMotion.easeOut,
                        alignment: Alignment.topCenter,
                        child: !_showBazaarSummary
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(
                                  top: _dashboardGutter,
                                ),
                                child: ActiveBazaarsCard(
                                  items: state.bazaarSummaries,
                                ),
                              ),
                      ),
                      const SizedBox(height: _dashboardGutter),
                      _buildMiddleSection(context, width, state),
                      AnimatedSize(
                        duration: AppMotion.entrance,
                        curve: AppMotion.easeOut,
                        alignment: Alignment.topCenter,
                        child: !_showTransactionHistory
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(
                                  top: _dashboardGutter,
                                ),
                                child: CustomerHistoryCard(
                                  rows: state.recentOrders,
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    DashboardCubit dashboardCubit,
    double width,
    DashboardState state,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
              children: [
                const TextSpan(text: 'Hello, '),
                TextSpan(
                  text: widget.user.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: '!'),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.user.isAdminOrOwner) ...[
          const SizedBox(width: 8),
          _BazaarFilterDropdown(
            options: state.bazaarFilterOptions,
            selected: state.selectedBazaarFilter,
            triggerWidth: width >= 900 ? 220 : 170,
            onSelected: (selected) => dashboardCubit.updateGlobalFilter(
              selectedFilter: selected,
              user: widget.user,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKpiSection(double width, DashboardState state) {
    final kpis = state.kpis.take(4).toList();
    const icons = <IconData>[
      Icons.attach_money_outlined,
      Icons.show_chart_outlined,
      Icons.check_circle_outline,
      Icons.shopping_cart_outlined,
    ];
    final columns = width >= 760 ? 4 : 2;

    return GridView.builder(
      itemCount: kpis.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: _dashboardGutter,
        mainAxisSpacing: _dashboardGutter,
        // Not childAspectRatio. Deriving the height from the column width made
        // the same card 102px tall at a 1000px window and 151px at 1440 — a
        // 16px top padding against 31-80px of dead space below it, changing
        // with the viewport. A card's padding must not be a function of how
        // wide the window is.
        mainAxisExtent: _kpiCardHeight,
      ),
      itemBuilder: (context, index) {
        final kpi = kpis[index];
        // Index 2 = Active Bazaars, index 3 = Total Orders — these two KPI
        // cards double as toggles for the (hidden-by-default) detail
        // sections below, instead of adding permanent extra containers.
        final isActiveBazaarsCard = index == 2;
        final isTotalOrdersCard = index == 3;
        final onTap = isActiveBazaarsCard
            ? () => setState(() => _showBazaarSummary = !_showBazaarSummary)
            : isTotalOrdersCard
            ? () => setState(
                () => _showTransactionHistory = !_showTransactionHistory,
              )
            : null;
        final isExpanded = isActiveBazaarsCard
            ? _showBazaarSummary
            : isTotalOrdersCard
            ? _showTransactionHistory
            : false;

        return DashboardKpiCard(
          title: kpi.title,
          value: kpi.value,
          onTap: onTap,
          isExpanded: isExpanded,
          iconWidget: index == 0
              ? Text(
                  '₱',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                )
              : null,
          icon: index < icons.length ? icons[index] : null,
        );
      },
    );
  }

  Widget _buildMiddleSection(
    BuildContext context,
    double width,
    DashboardState state,
  ) {
    // Side by side, the two cards have to agree on a height, and the taller of
    // the two is Analyze — 381 at the narrowest width this branch runs at.
    // Pinned by a test rather than left to drift, because falling short here
    // pushes part of the Analyze grid behind a scroll. The chart simply fills
    // whatever is left over, so the sales card never pads itself out with
    // dead space to match.
    const pairedCardHeight = 384.0;

    if (width >= 900) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              height: pairedCardHeight,
              child: AverageDailySalesCard(dailySales: state.dailySales),
            ),
          ),
          const SizedBox(width: _dashboardGutter),
          Expanded(
            child: SizedBox(
              height: pairedCardHeight,
              child: AnalyzeCard(analytics: state.analytics),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        AverageDailySalesCard(dailySales: state.dailySales),
        const SizedBox(height: _dashboardGutter),
        AnalyzeCard(analytics: state.analytics),
      ],
    );
  }
}

/// The dashboard-wide "which bazaar am I looking at" filter.
///
/// Treated as a select, not a button: it reports which option is active both
/// on the trigger and with a check inside the menu (recognition over recall —
/// an open menu that doesn't mark the current choice forces the user to
/// remember it), the menu drops directly under the trigger and is never
/// narrower than it (Jakob's Law — that is how every native select behaves),
/// and the trigger visibly changes state while the menu is open rather than
/// showing a chevron that always points the same way.
///
/// It is deliberately *not* filled with solid primary purple: this is a
/// secondary control, and the dashboard has no primary CTA to out-shout, so a
/// saturated button here becomes the loudest thing on a screen whose job is
/// to show data. See the button sizing tiers in DESIGN_GUIDELINES.md.
class _BazaarFilterDropdown extends StatefulWidget {
  const _BazaarFilterDropdown({
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.triggerWidth,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final double triggerWidth;

  @override
  State<_BazaarFilterDropdown> createState() => _BazaarFilterDropdownState();
}

class _BazaarFilterDropdownState extends State<_BazaarFilterDropdown> {
  static const Color _borderColor = Color(0xFFEAEAEF);

  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Filter dashboard by bazaar: ${widget.selected}',
      // Anchor the menu to the trigger and never let it be narrower — a
      // content-sized menu floating off to one side reads as a detached
      // popup rather than as this field's list of values.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: BoxConstraints(minWidth: widget.triggerWidth, maxWidth: 320),
      initialValue: widget.selected,
      color: AppColors.surface,
      elevation: 3,
      padding: EdgeInsets.zero,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFEDEDF1)),
      ),
      onOpened: () => setState(() => _isOpen = true),
      onCanceled: () => setState(() => _isOpen = false),
      onSelected: (value) {
        setState(() => _isOpen = false);
        widget.onSelected(value);
      },
      itemBuilder: (context) => [
        for (final option in widget.options)
          PopupMenuItem<String>(
            value: option,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: option == widget.selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: option == widget.selected
                          ? AppColors.primary
                          : AppColors.text,
                      fontWeight: option == widget.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.triggerWidth),
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _isOpen ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isOpen ? AppColors.primary : _borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.selected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Points down when closed, up when open, so the chevron is a
              // state indicator rather than static decoration.
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0,
                duration: AppMotion.small,
                curve: AppMotion.easeOut,
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
