import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

class AiAnalyticsCard extends StatefulWidget {
  const AiAnalyticsCard({
    super.key,
    required this.insights,
    this.onRefresh,
    this.onFeedback,
    this.isLoading = false,
  });

  final List<String> insights;
  final VoidCallback? onRefresh;
  final void Function(bool isPositive)? onFeedback;
  final bool isLoading;

  @override
  State<AiAnalyticsCard> createState() => _AiAnalyticsCardState();
}

class _AiAnalyticsCardState extends State<AiAnalyticsCard> {
  bool? _lastFeedbackPositive;

  @override
  Widget build(BuildContext context) {
    final insights = widget.insights.isEmpty
        ? _fallbackInsights
        : widget.insights;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final insightsContent = Scrollbar(
            thumbVisibility: !widget.isLoading && insights.length > 4,
            child: SingleChildScrollView(
              child: widget.isLoading
                  ? _buildLoadingState(context)
                  : _buildInsights(context, insights),
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 14),
              if (constraints.maxHeight.isFinite)
                Expanded(child: insightsContent)
              else
                SizedBox(height: 180, child: insightsContent),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _buildFooter(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.primary, AppColors.accent],
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.psychology_outlined,
          color: AppColors.primary,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Analyze',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (widget.onRefresh != null)
          IconButton(
            onPressed: widget.onRefresh,
            tooltip: 'Regenerate insights',
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
      ],
    );
  }

  Widget _buildInsights(BuildContext context, List<String> insights) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: insights
          .map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      insight,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analyzing recent bazaar activity...',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 10),
        ...List.generate(
          4,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final upSelected = _lastFeedbackPositive == true;
    final downSelected = _lastFeedbackPositive == false;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.info_outline, size: 15, color: Colors.black54),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Please review AI-generated content as it may contain inaccuracies or biases.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        IconButton(
          onPressed: () => _handleFeedback(context, true),
          icon: Icon(
            Icons.thumb_up_alt_outlined,
            size: 19,
            color: upSelected ? const Color(0xFF2E7D32) : Colors.black45,
          ),
          tooltip: 'Helpful',
        ),
        IconButton(
          onPressed: () => _handleFeedback(context, false),
          icon: Icon(
            Icons.thumb_down_alt_outlined,
            size: 19,
            color: downSelected ? AppColors.error : Colors.black45,
          ),
          tooltip: 'Not helpful',
        ),
      ],
    );
  }

  void _handleFeedback(BuildContext context, bool isPositive) {
    setState(() {
      _lastFeedbackPositive = isPositive;
    });
    widget.onFeedback?.call(isPositive);
    debugPrint(
      'AI insight feedback: ${isPositive ? 'thumbs_up' : 'thumbs_down'}',
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thanks for your feedback')));
  }
}

const List<String> _fallbackInsights = [
  'Amkor Bazaar - March 2025 generated the highest revenue this week, with \u20B1120,450 in total sales.',
  'Sneaker Model X had the highest number of orders, selling 42 units across all bazaars.',
  'COOP payments accounted for 62% of all sales in the last 7 days.',
  'Company B - April 2025 Bazaar shows a lower average order value; consider creating a promo bundle.',
];
