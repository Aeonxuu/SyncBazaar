import 'dart:convert';

import 'bazaar_event.dart';

/// The bazaar an employee is asking for, as carried in an approval request.
///
/// The request itself stores this as an opaque blob, which keeps the server
/// out of the business of understanding a proposal. That leaves the client
/// reading it, and two places need to: the screen that raises the request, to
/// create the bazaar it proposes, and the screen that approves one, to fill
/// that bazaar in. Parsing it in both is how the two drift.
///
/// Every field tolerates being missing. The blob is written by an older build
/// than the one reading it as soon as anybody updates mid-bazaar, and an
/// approval that throws is one nobody can clear.
class StockProposal {
  const StockProposal({
    required this.eventName,
    required this.companyId,
    required this.startDate,
    required this.endDate,
    required this.acceptedPaymentMethods,
    required this.customOtherMethods,
    required this.allocationsByAllocationKey,
  });

  final String eventName;
  final int companyId;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> acceptedPaymentMethods;
  final List<BazaarPaymentMethod> customOtherMethods;
  final Map<String, int> allocationsByAllocationKey;

  static StockProposal parse(String detailsJson) {
    final decoded = _safeDecode(detailsJson);

    final rawName = decoded?['eventName'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : 'Approved Bazaar';

    final start = _date(decoded?['dateStart']) ?? DateTime.now();
    final methods = _strings(decoded?['acceptedPaymentMethods']);

    return StockProposal(
      eventName: name,
      companyId: decoded?['companyId'] is int
          ? decoded!['companyId'] as int
          : 1,
      startDate: start,
      // A single-day bazaar writes the same date twice; a missing end is that
      // rather than an open-ended one.
      endDate: _date(decoded?['dateEnd']) ?? start,
      acceptedPaymentMethods: methods.isEmpty ? const ['CASH'] : methods,
      customOtherMethods: _methods(decoded?['customOtherMethods']),
      allocationsByAllocationKey: _allocations(
        decoded?['allocationsByAllocationKey'],
      ),
    );
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  static List<String> _strings(Object? raw) =>
      raw is! List ? const [] : raw.map((value) => value.toString()).toList();

  static List<BazaarPaymentMethod> _methods(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (item) => BazaarPaymentMethod(
            name: item['name']?.toString() ?? 'OTHER',
            extraFieldLabel: _extraFieldLabel(item),
          ),
        )
        .toList();
  }

  static String? _extraFieldLabel(Map<dynamic, dynamic> item) {
    final raw = item['extraFieldLabel'];
    if (raw is String && raw.trim().isNotEmpty) {
      final trimmed = raw.trim();
      // Long enough to read on a till, short enough to fit the field's label.
      return trimmed.length <= 28 ? trimmed : trimmed.substring(0, 28);
    }
    // What older proposals wrote before the label was free text.
    if (item['requiresEmployeeId'] == true) {
      return 'Employee ID';
    }
    return null;
  }

  static Map<String, int> _allocations(Object? raw) {
    if (raw is! Map) {
      return const {};
    }
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is int ? value : int.tryParse(value.toString()) ?? 0,
      ),
    );
  }

  static Map<String, dynamic>? _safeDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
