import 'package:flutter/material.dart';

import '../../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../../core/constants/colors.dart';
import 'dashboard_section_card.dart';
import '../../../../core/utils/formatters.dart';

class CustomerHistoryCard extends StatelessWidget {
  const CustomerHistoryCard({super.key, required this.rows});

  final List<CustomerHistoryData> rows;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Transaction History',
      child: Column(
        children: [
          _headerRow(context),
          const SizedBox(height: 8),
          const Divider(height: 1),
          SizedBox(
            height: 270,
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      'Transaction History is currently empty.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: rows
                          .map((row) => _dataRow(context, row))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w700,
    );

    return Row(
      children: [
        Expanded(flex: 2, child: Text('Date', style: style)),
        Expanded(flex: 2, child: Text('Time', style: style)),
        Expanded(flex: 3, child: Text('Customer', style: style)),
        Expanded(flex: 3, child: Text('Bazaar', style: style)),
        Expanded(flex: 2, child: Text('Payment', style: style)),
        Expanded(flex: 2, child: Text('Amount', style: style)),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text('Status', style: style),
          ),
        ),
      ],
    );
  }

  Widget _dataRow(BuildContext context, CustomerHistoryData row) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(_fmtDate(row.timestamp), style: textStyle),
          ),
          Expanded(
            flex: 2,
            child: Text(_fmtTime(row.timestamp), style: textStyle),
          ),
          Expanded(flex: 3, child: Text(row.customerName, style: textStyle)),
          Expanded(flex: 3, child: Text(row.bazaarName, style: textStyle)),
          Expanded(flex: 2, child: Text(row.paymentMethod, style: textStyle)),
          Expanded(
            flex: 2,
            child: Text(
              formatPeso(row.amount),
              style: textStyle?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.left,
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: _statusChip(context, row.status),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _fmtTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Widget _statusChip(BuildContext context, String status) {
    final isCompleted = status.toLowerCase() == 'completed';
    final isPending = status.toLowerCase() == 'pending';
    final bg = isCompleted
        ? const Color(0x1A2E7D32)
        : isPending
        ? const Color(0x1AF59E0B)
        : const Color(0x1ADC3545);
    final fg = isCompleted
        ? const Color(0xFF2E7D32)
        : isPending
        ? const Color(0xFFB45309)
        : AppColors.error;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
