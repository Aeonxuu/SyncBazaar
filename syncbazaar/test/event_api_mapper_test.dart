import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/event_api_mapper.dart';
import 'package:syncbazaar/models/bazaar_event.dart';

void main() {
  BazaarStatus fixedStatus(DateTime _, DateTime __) => BazaarStatus.ongoing;

  group('events', () {
    const payload = '''
    [{"id": 15, "establishment": 6, "vendor": 3, "name": "August Fair",
      "address": "Lucena City", "start_date": "2026-08-03T00:00:00Z",
      "end_date": "2026-08-07T00:00:00Z", "is_approved": true}]
    ''';

    test('an unapproved bazaar is not a bazaar yet', () {
      // A proposal awaiting an owner. The server hands it back beside real
      // ones -- only its `?status=` queries filter on approval, and this list
      // asks for no status -- so without this it would appear in the till and
      // the sales list as something to sell against.
      const withProposal = '''
      [{"id": 15, "establishment": 6, "vendor": 3, "name": "August Fair",
        "address": "Lucena City", "start_date": "2026-08-03T00:00:00Z",
        "end_date": "2026-08-07T00:00:00Z", "is_approved": true},
       {"id": 16, "establishment": 6, "vendor": 3, "name": "Someone's Idea",
        "address": "Lucena City", "start_date": "2026-08-03T00:00:00Z",
        "end_date": "2026-08-07T00:00:00Z", "is_approved": false}]
      ''';

      final events = mapEventsResponse(
        jsonDecode(withProposal) as List,
        statusFor: fixedStatus,
      );

      expect(events.map((e) => e.name), ['August Fair']);
    });

    test('a bazaar from a server without the field is kept', () {
      // Absent is not false: dropping these would empty the app against any
      // backend that has not deployed the approval flow.
      const noField = '''
      [{"id": 15, "establishment": 6, "vendor": 3, "name": "August Fair",
        "address": "Lucena City", "start_date": "2026-08-03T00:00:00Z",
        "end_date": "2026-08-07T00:00:00Z"}]
      ''';

      final events = mapEventsResponse(
        jsonDecode(noField) as List,
        statusFor: fixedStatus,
      );

      expect(events, hasLength(1));
    });

    test(
      'maps the venue from establishment, which the app calls a company',
      () {
        final events = mapEventsResponse(
          jsonDecode(payload) as List,
          statusFor: fixedStatus,
        );

        expect(events.single.name, 'August Fair');
        expect(events.single.companyId, 6);
      },
    );

    test('defers the status decision to the caller', () {
      // The whole-day truncation rule lives in EventRepository; duplicating it
      // here is how the two would drift.
      var seen = 0;
      mapEventsResponse(
        jsonDecode(payload) as List,
        statusFor: (_, __) {
          seen++;
          return BazaarStatus.ended;
        },
      );
      expect(seen, 1);
    });

    test('applies the fallback payment methods to every event', () {
      final events = mapEventsResponse(
        jsonDecode(payload) as List,
        statusFor: fixedStatus,
        fallbackMethods: const ['CASH', 'GCASH'],
        fallbackCustomMethods: const [
          BazaarPaymentMethod(
            name: 'GCASH',
            extraFieldLabel: 'Reference Number',
          ),
        ],
      );

      expect(events.single.acceptedPaymentMethods, ['CASH', 'GCASH']);
      expect(
        events.single.customOtherMethods.single.extraFieldLabel,
        'Reference Number',
      );
    });
  });

  group('event stock', () {
    // 208 and 209 are known combinations; 999 is not.
    String? keyFor(int variantId) => switch (variantId) {
      208 => '16:10:7',
      209 => '16:11:7',
      _ => null,
    };

    test('reports what is left to sell, not what was allocated', () {
      // The POS needs remaining stock: amount_allocated is the opening figure
      // and does not move as the day goes on.
      final allocations = mapEventStockResponse(
        jsonDecode('''
        [{"id": 1, "event": 15, "variant": 208,
          "amount_allocated": 10, "amount_sold": 3}]
        ''')
            as List,
        allocationKeyForVariant: keyFor,
      );

      expect(allocations['16:10:7'], 7);
    });

    test('never reports negative stock', () {
      final allocations = mapEventStockResponse(
        jsonDecode('''
        [{"id": 1, "event": 15, "variant": 208,
          "amount_allocated": 2, "amount_sold": 5}]
        ''')
            as List,
        allocationKeyForVariant: keyFor,
      );

      expect(allocations['16:10:7'], 0);
    });

    test('skips variants the catalogue does not know', () {
      // An archived variant, or one whose product the vendor no longer lists.
      // Inventing a combination would put unsellable stock in the POS.
      final allocations = mapEventStockResponse(
        jsonDecode('''
        [{"id": 1, "event": 15, "variant": 999,
          "amount_allocated": 10, "amount_sold": 0},
         {"id": 2, "event": 15, "variant": 209,
          "amount_allocated": 4, "amount_sold": 1}]
        ''')
            as List,
        allocationKeyForVariant: keyFor,
      );

      expect(allocations, {'16:11:7': 3});
    });

    test('sums rows that land on the same combination', () {
      final allocations = mapEventStockResponse(
        jsonDecode('''
        [{"id": 1, "event": 15, "variant": 208,
          "amount_allocated": 5, "amount_sold": 1},
         {"id": 2, "event": 15, "variant": 208,
          "amount_allocated": 3, "amount_sold": 0}]
        ''')
            as List,
        allocationKeyForVariant: keyFor,
      );

      expect(allocations['16:10:7'], 7);
    });
  });
}
