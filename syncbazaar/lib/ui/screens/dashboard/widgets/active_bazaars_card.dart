import 'package:flutter/material.dart';

import '../../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/bazaar_event.dart';
import 'dashboard_section_card.dart';

class ActiveBazaarsCard extends StatelessWidget {
  const ActiveBazaarsCard({super.key, required this.items});

  final List<BazaarSummaryData> items;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Active Bazaars Summary',
      child: Column(
        children: items.isEmpty
            ? [
                Text(
                  'No active/upcoming bazaars.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ]
            : items.map((item) => _BazaarRow(item: item)).toList(),
      ),
    );
  }
}

class _BazaarRow extends StatelessWidget {
  const _BazaarRow({required this.item});

  final BazaarSummaryData item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.bazaarName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(item.companyName),
                  Text(item.location),
                  Text(_formatDateRange(item.startDate, item.endDate)),
                ],
              ),
            ),
            _StatusBadge(status: item.status),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    String fmt(DateTime d) => formatDate(d);
    return '${fmt(start)} - ${fmt(end)}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BazaarStatus status;

  @override
  Widget build(BuildContext context) {
    final bg = switch (status) {
      BazaarStatus.upcoming => const Color(0x1AF59E0B),
      BazaarStatus.ongoing => const Color(0x1A2E7D32),
      BazaarStatus.ended => const Color(0x1A6B7280),
    };
    final fg = switch (status) {
      BazaarStatus.upcoming => const Color(0xFFB45309),
      BazaarStatus.ongoing => const Color(0xFF2E7D32),
      BazaarStatus.ended => const Color(0xFF4B5563),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
