import '../../models/bazaar_event.dart';

/// Turns `GET /api/bazaar/event/` into the app's events.
///
/// [statusFor] is passed in rather than computed here so the rule for deciding
/// upcoming/ongoing/ended lives in one place — `EventRepository` already
/// truncates both sides to whole days, because a bazaar runs for days and a
/// start time of "today 2:30pm" would otherwise read as still upcoming until
/// tomorrow.
///
/// The server does not send which payment methods an event accepts: they hang
/// off `Establishment`, whose endpoint currently returns a 500. Until that is
/// fixed every event is given [fallbackMethods], the vendor-wide list, which
/// over-offers rather than under-offers — a cashier seeing a method the venue
/// disallows is a smaller failure than one unable to take the payment a
/// customer is holding out.
List<BazaarEvent> mapEventsResponse(
  List<dynamic> payload, {
  required BazaarStatus Function(DateTime start, DateTime end) statusFor,
  List<String> fallbackMethods = const ['CASH'],
  List<BazaarPaymentMethod> fallbackCustomMethods = const [],
}) {
  final events = <BazaarEvent>[];
  for (final entry in payload) {
    final map = entry as Map<String, dynamic>;
    final start = DateTime.parse(map['start_date'] as String).toLocal();
    final end = DateTime.parse(map['end_date'] as String).toLocal();

    events.add(
      BazaarEvent(
        id: (map['id'] as num).toInt(),
        name: map['name'] as String? ?? '',
        // The venue. Named `establishment` server-side; `Company` here.
        companyId: (map['establishment'] as num?)?.toInt() ?? 0,
        startDate: start,
        endDate: end,
        status: statusFor(start, end),
        acceptedPaymentMethods: fallbackMethods,
        customOtherMethods: fallbackCustomMethods,
      ),
    );
  }
  return events;
}

/// Turns `GET /api/bazaar/event/<id>/stock/` into allocations by combination.
///
/// The server allocates against a `ProductVariant`; the app allocates against
/// its own combination key. [allocationKeyForVariant] bridges the two and comes
/// from the already-loaded catalogue, which is why the products have to be
/// fetched before an event's stock means anything.
///
/// Rows whose variant is unknown are skipped rather than guessed at: that only
/// happens when a variant was archived or belongs to a product the vendor no
/// longer lists, and inventing a combination for it would put stock in the POS
/// that cannot be sold.
/// [stockIdByAllocationKey], when given, is filled with the `EventStock` row id
/// behind each combination. Uploading a sale needs it: the server records what
/// was sold against that row, not against a product or a variant, because the
/// same variant has a separate row — and a separate count — at every bazaar it
/// was allocated to.
Map<String, int> mapEventStockResponse(
  List<dynamic> payload, {
  required String? Function(int variantId) allocationKeyForVariant,
  Map<String, int>? stockIdByAllocationKey,
}) {
  final allocations = <String, int>{};
  for (final entry in payload) {
    final row = entry as Map<String, dynamic>;
    final variantId = (row['variant'] as num?)?.toInt();
    if (variantId == null) {
      continue;
    }
    final key = allocationKeyForVariant(variantId);
    if (key == null) {
      continue;
    }

    // What is left on the table, not what was brought to it. `amount_allocated`
    // is the opening figure and does not move as the day goes on; the POS needs
    // what can still be sold.
    final allocated = (row['amount_allocated'] as num?)?.toInt() ?? 0;
    final sold = (row['amount_sold'] as num?)?.toInt() ?? 0;
    final remaining = allocated - sold;
    allocations[key] = (allocations[key] ?? 0) + (remaining < 0 ? 0 : remaining);

    final stockId = (row['id'] as num?)?.toInt();
    if (stockId != null) {
      stockIdByAllocationKey?[key] = stockId;
    }
  }
  return allocations;
}
