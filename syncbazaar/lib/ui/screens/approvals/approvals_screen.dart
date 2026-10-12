import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/approvals/approvals_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/approval_request.dart';
import '../../../models/user.dart';
import '../../../core/utils/formatters.dart';
import 'widgets/approval_details_dialog.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key, required this.user});

  /// Who is looking. An employee reaches this screen straight after raising a
  /// request -- the nav item is hidden from them, but the pre-bazaar form used
  /// to walk them here -- and the screen had no idea, so the Approve button
  /// worked. An employee could approve their own bazaar.
  final AppUser user;

  static const _kCardShadow = [
    BoxShadow(color: Color(0x11000000), blurRadius: 20, offset: Offset(0, 4)),
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
              labelStyle: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
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
                    _ApprovalList(
                      requests: stock,
                      canDecide: user.isAdminOrOwner,
                    ),
                    _ApprovalList(
                      requests: soa,
                      canDecide: user.isAdminOrOwner,
                    ),
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
  const _ApprovalList({required this.requests, required this.canDecide});

  final List<ApprovalRequest> requests;

  /// Whether the viewer may answer a request, as opposed to watching one they
  /// raised. Only owners and admins decide; an employee sees the same detail
  /// with no buttons on it.
  final bool canDecide;

  static const _kCardShadow = [
    BoxShadow(color: Color(0x11000000), blurRadius: 20, offset: Offset(0, 4)),
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
        final locationName = _getLocationName(req);
        final eventDateRange = _getEventDateRange(req);

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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            locationName,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (eventDateRange != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              eventDateRange,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black45,
                                    fontWeight: FontWeight.w500,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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

  String _getTitle(ApprovalRequest req) {
    if (req.type == ApprovalType.stock) {
      return 'STOCK REQUEST for ${_getEventName(req)}';
    }
    return '${req.type.name.toUpperCase()} Request #${req.id}';
  }

  String _getEventName(ApprovalRequest req) {
    final decoded = _safeDecode(req.detailsJson);
    final rawName = decoded?['eventName'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      return rawName.trim();
    }
    return 'Bazaar #${req.eventId}';
  }

  String? _getEventDateRange(ApprovalRequest req) {
    final decoded = _safeDecode(req.detailsJson);
    final startRaw = decoded?['dateStart'];
    final endRaw = decoded?['dateEnd'];

    final startDate = startRaw is String ? DateTime.tryParse(startRaw) : null;
    final endDate = endRaw is String ? DateTime.tryParse(endRaw) : null;
    if (startDate == null || endDate == null) {
      return null;
    }

    final start = _formatDate(startDate);
    final end = _formatDate(endDate);
    return '$start - $end';
  }

  String _getLocationName(ApprovalRequest req) {
    final decoded = _safeDecode(req.detailsJson);
    final rawLocationName = decoded?['locationName'];
    if (rawLocationName is String && rawLocationName.trim().isNotEmpty) {
      return rawLocationName.trim();
    }
    final companyId = decoded?['companyId'];
    if (companyId is int) {
      return 'Venue ID: $companyId';
    }
    return 'Venue not specified';
  }

  String _formatDate(DateTime date) => formatDate(date);

  Future<void> _showDetailsModal(BuildContext context, ApprovalRequest req) {
    return showApprovalDetailsDialog(
      context: context,
      request: req,
      canDecide: canDecide,
    );
  }

  Map<String, dynamic>? _safeDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
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
