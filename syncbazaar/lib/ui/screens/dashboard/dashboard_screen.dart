import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/user.dart';
import 'widgets/active_bazaars_card.dart';
import 'widgets/ai_analytics_card.dart';
import 'widgets/average_daily_sales_card.dart';
import 'widgets/customer_history_card.dart';
import 'widgets/dashboard_kpi_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    required this.onOpenPos,
  });

  final AppUser user;
  final VoidCallback onOpenPos;

  @override
  Widget build(BuildContext context) {
    final dashboardCubit = context.read<DashboardCubit>();

    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        return Container(
          color: AppColors.background,
          child: RefreshIndicator(
            onRefresh: () => dashboardCubit.load(user),
            color: AppColors.primary,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                children: [
                                  const TextSpan(text: 'Hello, '),
                                  TextSpan(
                                    text: user.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const TextSpan(text: '!'),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user.isAdminOrOwner) ...[
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              onSelected: (selected) {
                                dashboardCubit.updateGlobalFilter(
                                  selectedFilter: selected,
                                  user: user,
                                );
                              },
                              itemBuilder: (context) => state
                                  .bazaarFilterOptions
                                  .map(
                                    (option) => PopupMenuItem<String>(
                                      value: option,
                                      child: Text(option),
                                    ),
                                  )
                                  .toList(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: width >= 900 ? 220 : 170,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.primary,
                                        Color.lerp(
                                          AppColors.primary,
                                          Colors.white,
                                          0.18,
                                        )!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x1A000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.filter_alt_outlined,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Text(
                                          state.selectedBazaarFilter,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildKpiSection(width, state),
                      const SizedBox(height: 14),
                      _buildMiddleSection(context, width, state),
                      const SizedBox(height: 14),
                      CustomerHistoryCard(
                        rows: state.recentOrders,
                        filterOptions: state.bazaarFilterOptions,
                        selectedFilter: state.selectedBazaarFilter,
                        isFilterEnabled: user.isAdminOrOwner,
                        showFilter: false,
                        onFilterChanged: (selected) {
                          if (selected != null) {
                            dashboardCubit.updateBazaarFilter(
                              selectedFilter: selected,
                              user: user,
                            );
                          }
                        },
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

  Widget _buildKpiSection(double width, DashboardState state) {
    final kpis = state.kpis.take(4).toList();
    const icons = <IconData>[
      Icons.attach_money_outlined,
      Icons.show_chart_outlined,
      Icons.check_circle_outline,
      Icons.shopping_cart_outlined,
    ];
    final columns = width >= 760 ? 4 : 2;
    final aspectRatio = columns == 4 ? 2.25 : 2.6;

    return GridView.builder(
      itemCount: kpis.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, index) {
        final kpi = kpis[index];
        return DashboardKpiCard(
          title: kpi.title,
          value: kpi.value,
          trendText: kpi.trendText,
          trendIsPositive: kpi.trendIsPositive,
          iconWidget: index == 0
              ? Text(
                  '\u20B1',
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
    final aiInsights = state.aiInsights.isNotEmpty
        ? state.aiInsights
        : const [
            'Amkor Bazaar - March 2025 generated the highest revenue this week, with \u20B1120,450 in sales.',
            'Sneaker Model X had the most orders, selling 42 units across all bazaars.',
            'COOP payments accounted for 62% of all transactions in the last 7 days.',
            'Company B - April Bazaar shows a lower average order value; consider adding bundle promotions.',
          ];
    final pairedCardHeight = width >= 1200 ? 320.0 : 300.0;

    if (width >= 900) {
      return Column(
        children: [
          ActiveBazaarsCard(items: state.bazaarSummaries),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: pairedCardHeight,
                  child: AverageDailySalesCard(
                    dailySales: state.dailySales,
                    trendText: state.averageDailySalesTrendText,
                    trendIsPositive: state.averageDailySalesTrendIsPositive,
                    showFilter: false,
                    filterOptions: state.salesFilterOptions,
                    selectedFilter: state.selectedSalesFilter,
                    onFilterChanged: null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: pairedCardHeight,
                  child: AiAnalyticsCard(
                    insights: aiInsights,
                    onRefresh: () => context.read<DashboardCubit>().load(user),
                    onFeedback: (isPositive) {
                      debugPrint(
                        'AI analytics feedback from dashboard: ${isPositive ? 'positive' : 'negative'}',
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        ActiveBazaarsCard(items: state.bazaarSummaries),
        const SizedBox(height: 12),
        AverageDailySalesCard(
          dailySales: state.dailySales,
          trendText: state.averageDailySalesTrendText,
          trendIsPositive: state.averageDailySalesTrendIsPositive,
          showFilter: false,
          filterOptions: state.salesFilterOptions,
          selectedFilter: state.selectedSalesFilter,
          onFilterChanged: null,
        ),
        const SizedBox(height: 12),
        AiAnalyticsCard(
          insights: aiInsights,
          onRefresh: () => context.read<DashboardCubit>().load(user),
          onFeedback: (isPositive) {
            debugPrint(
              'AI analytics feedback from dashboard: ${isPositive ? 'positive' : 'negative'}',
            );
          },
        ),
      ],
    );
  }
}
