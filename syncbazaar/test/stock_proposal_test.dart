import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/stock_proposal.dart';

/// The proposal blob is the only description of the bazaar an owner is being
/// asked to agree to. It is written by the pre-bazaar form and read twice --
/// once to create the placeholder bazaar, once to fill it in on approval -- so
/// anything it drops is a detail the approved bazaar silently loses.
void main() {
  String encode(Map<String, dynamic> fields) => jsonEncode(fields);

  test('reads a complete proposal as the form writes it', () {
    final proposal = StockProposal.parse(
      encode({
        'eventName': 'Stardew Valley Crop Fest',
        'locationName': 'SM City Lucena',
        'companyId': 2,
        'dateStart': '2026-08-13T00:00:00.000',
        'dateEnd': '2026-08-17T00:00:00.000',
        'acceptedPaymentMethods': ['CASH', 'GCASH'],
        'customOtherMethods': [
          {'name': 'GCASH', 'extraFieldLabel': 'Reference Number'},
        ],
        'allocationsByAllocationKey': {'1-2-3': 5, '1-2-4': 2},
      }),
    );

    expect(proposal.eventName, 'Stardew Valley Crop Fest');
    expect(proposal.companyId, 2);
    expect(proposal.startDate, DateTime(2026, 8, 13));
    expect(proposal.endDate, DateTime(2026, 8, 17));
    expect(proposal.acceptedPaymentMethods, ['CASH', 'GCASH']);
    expect(proposal.customOtherMethods.single.name, 'GCASH');
    expect(
      proposal.customOtherMethods.single.extraFieldLabel,
      'Reference Number',
    );
    expect(proposal.allocationsByAllocationKey, {'1-2-3': 5, '1-2-4': 2});
  });

  test('a nameless proposal still names the bazaar something', () {
    // The bazaar is created from this, and a blank name is not a bazaar.
    expect(StockProposal.parse(encode({})).eventName, 'Approved Bazaar');
    expect(
      StockProposal.parse(encode({'eventName': '   '})).eventName,
      'Approved Bazaar',
    );
  });

  test('a missing end date makes it a single-day bazaar', () {
    final proposal = StockProposal.parse(
      encode({'dateStart': '2026-08-13T00:00:00.000'}),
    );

    // Not open-ended: a bazaar with no end sells forever.
    expect(proposal.endDate, proposal.startDate);
  });

  test('no payment method means cash', () {
    // A till that accepts nothing cannot take money at all.
    expect(StockProposal.parse(encode({})).acceptedPaymentMethods, ['CASH']);
    expect(
      StockProposal.parse(
        encode({'acceptedPaymentMethods': <String>[]}),
      ).acceptedPaymentMethods,
      ['CASH'],
    );
  });

  test('an over-long field label is cut to fit the till', () {
    final proposal = StockProposal.parse(
      encode({
        'customOtherMethods': [
          {'name': 'BANK', 'extraFieldLabel': 'A' * 60},
        ],
      }),
    );

    expect(proposal.customOtherMethods.single.extraFieldLabel!.length, 28);
  });

  test('an older proposal\'s employee-id flag still reads', () {
    // Written before the label was free text. Someone updating the app
    // mid-bazaar leaves requests of both shapes pending at once.
    final proposal = StockProposal.parse(
      encode({
        'customOtherMethods': [
          {'name': 'COOP', 'requiresEmployeeId': true},
        ],
      }),
    );

    expect(proposal.customOtherMethods.single.extraFieldLabel, 'Employee ID');
  });

  test('allocation counts written as text are still counts', () {
    final proposal = StockProposal.parse(
      encode({
        'allocationsByAllocationKey': {'1-2-3': '5', '1-2-4': 'nonsense'},
      }),
    );

    expect(proposal.allocationsByAllocationKey['1-2-3'], 5);
    // Unparseable reads as none rather than taking the approval down.
    expect(proposal.allocationsByAllocationKey['1-2-4'], 0);
  });

  test('a corrupt blob yields a proposal rather than an exception', () {
    // An approval that throws is one nobody can clear off the screen.
    final proposal = StockProposal.parse('this is not json');

    expect(proposal.eventName, 'Approved Bazaar');
    expect(proposal.allocationsByAllocationKey, isEmpty);
    expect(proposal.acceptedPaymentMethods, ['CASH']);
  });

  test('a proposal with no allocations commits no stock', () {
    expect(
      StockProposal.parse(
        encode({'eventName': 'Empty'}),
      ).allocationsByAllocationKey,
      isEmpty,
    );
  });
}
