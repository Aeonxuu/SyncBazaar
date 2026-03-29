import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/approvals/approvals_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/approval_request.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Stock Allocations'),
              Tab(text: 'SOA Drafts'),
            ],
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

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(child: Text('No pending requests'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, i) {
        final req = requests[i];
        final title = _getTitle(req);

        return Card(
          child: ListTile(
            title: Text(title),
            subtitle: Text('Event ID: ${req.eventId}'),
            onTap: () => _showDetailsModal(context, req),
            trailing: const Icon(Icons.arrow_forward),
          ),
        );
      },
    );
  }

  String _getTitle(ApprovalRequest req) {
    return '${req.type.name.toUpperCase()} Request #${req.id}';
  }

  Future<void> _showDetailsModal(BuildContext context, ApprovalRequest req) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return BackdropFilter(
          filter: ColorFilter.mode(
            Colors.black.withOpacity(0.3),
            BlendMode.darken,
          ),
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approval Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _buildProductTable(context, req),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            backgroundColor: const Color(0xFFFF5252),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text('Approve'),
                        ),
                      ],
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

  Widget _buildProductTable(BuildContext context, ApprovalRequest req) {
    final decoded = _safeDecode(req.detailsJson);
    if (decoded == null) {
      return Text('Unable to parse details: ${req.detailsJson}');
    }

    final items = decoded['items'] as List?;
    if (items != null && items.isNotEmpty) {
      return SizedBox(
        height: 300,
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
                      color: AppColors.primary.withOpacity(0.1),
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
                  ...items.map<TableRow>((item) {
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
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(name.toString()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(category.toString()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(variant.toString()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(price.toString()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(qty.toString()),
                        ),
                      ],
                    );
                  }).toList(),
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
                      color: AppColors.primary.withOpacity(0.1),
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
                  ...entries.map<TableRow>((entry) {
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(entry.key.toString()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(entry.value.toString()),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return const Text('No product details available');
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
