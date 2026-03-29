import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/approvals/approvals_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/approval_request.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  static const _kCardShadow = [
    BoxShadow(
      color: Color(0x11000000),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
              labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              tabs: const [
                Tab(text: 'Stock Allocations'),
                Tab(text: 'SOA Drafts'),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<ApprovalsCubit, List<ApprovalRequest>>(
              builder: (context, requests) {
                final stock = requests
                    .where((r) => r.type == ApprovalType.stock)
                    .toList();
                final soa = requests
                    .where((r) => r.type == ApprovalType.soa)
                    .toList();
                return TabBarView(
                  children: [
                    _ApprovalList(requests: stock),
                    _ApprovalList(requests: soa),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalList extends StatelessWidget {
  const _ApprovalList({required this.requests});

  final List<ApprovalRequest> requests;

  static const _kCardShadow = [
    BoxShadow(
      color: Color(0x11000000),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
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
                    Icons.inbox_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No pending requests',
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, i) {
        final req = requests[i];
        final title = _getTitle(req);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _AnimatedEntrance(
            delayMs: 40 * (i % 8),
            child: _InteractiveCard(
              onTap: () => _showDetailsModal(context, req),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _kCardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2ECFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        req.type == ApprovalType.stock
                            ? Icons.inventory_2_outlined
                            : Icons.description_outlined,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Event ID: ${req.eventId}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    _typeBadge(context, req),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _typeBadge(BuildContext context, ApprovalRequest req) {
    final isStock = req.type == ApprovalType.stock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isStock ? const Color(0x1A2E7D32) : const Color(0x1AF59E0B),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isStock ? 'STOCK' : 'SOA',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isStock ? const Color(0xFF2E7D32) : const Color(0xFFB45309),
            ),
      ),
    );
  }

  Widget _animatedTableCell({
    required int delayMs,
    required Widget child,
  }) {
    return _AnimatedEntrance(
      delayMs: delayMs,
      child: child,
    );
  }

  String _getTitle(ApprovalRequest req) {
    return '${req.type.name.toUpperCase()} Request #${req.id}';
  }

  Future<void> _showDetailsModal(BuildContext context, ApprovalRequest req) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.96, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Transform.scale(
                scale: value,
                child: Opacity(opacity: value, child: child),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
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
                                  'Approval Details',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getTitle(req),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                    ),
                      const Divider(height: 18),
                      _buildProductTable(context, req),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFC62828),
                                side: const BorderSide(color: Color(0xFFC62828)),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              label: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.check_rounded, size: 18),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              label: const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductTable(BuildContext context, ApprovalRequest req) {
    final decoded = _safeDecode(req.detailsJson);
    if (decoded == null) {
      return Text(
        'Unable to parse details: ${req.detailsJson}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
      );
    }

    final items = decoded['items'] as List?;
    if (items != null && items.isNotEmpty) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE9EAEE)),
        ),
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(1.5),
                  3: FlexColumnWidth(1),
                  4: FlexColumnWidth(1),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                  bottom: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Category', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Variant', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Price', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('QTY', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...items.asMap().entries.map<TableRow>((entry) {
                    final rowIndex = entry.key;
                    final item = entry.value;
                    if (item is! Map<String, dynamic>) {
                      return const TableRow(children: [SizedBox()]);
                    }
                    final name = item['name'] ?? '—';
                    final category = item['category'] ?? '—';
                    final variant = item['variant'] ?? '—';
                    final price = item['price'] ?? '—';
                    final qty = item['qty'] ?? '—';
                    return TableRow(
                      children: [
                        _animatedTableCell(
                          delayMs: 35 * (rowIndex + 1),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(name.toString()),
                          ),
                        ),
                        _animatedTableCell(
                          delayMs: 35 * (rowIndex + 1) + 6,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(category.toString()),
                          ),
                        ),
                        _animatedTableCell(
                          delayMs: 35 * (rowIndex + 1) + 12,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(variant.toString()),
                          ),
                        ),
                        _animatedTableCell(
                          delayMs: 35 * (rowIndex + 1) + 18,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(price.toString()),
                          ),
                        ),
                        _animatedTableCell(
                          delayMs: 35 * (rowIndex + 1) + 24,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(qty.toString()),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Handle allocations format
    final allocations = decoded['allocations'] as Map?;
    if (allocations != null) {
      final entries = allocations.entries.toList();
      return SizedBox(
        height: 300,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE9EAEE)),
          ),
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                  bottom: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('QTY', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...entries.asMap().entries.map<TableRow>((mapEntry) {
                    final rowIndex = mapEntry.key;
                    final entry = mapEntry.value;
                    return TableRow(
                      children: [
                        _animatedTableCell(
                          delayMs: 35 * (rowIndex + 1),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(entry.key.toString()),
                          ),
                        ),
                        _animatedTableCell(
                          delayMs: 35 * (rowIndex + 1) + 10,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(entry.value.toString()),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
        ),
      );
    }

    return Text(
      'No product details available',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Map<String, dynamic>? _safeDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _AnimatedEntrance extends StatefulWidget {
  const _AnimatedEntrance({
    required this.child,
    required this.delayMs,
  });

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
