import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/establishment_api_mapper.dart';
import 'package:syncbazaar/models/company.dart';

void main() {
  final methodsById = mapPaymentMethodsById(
    jsonDecode('''
    [{"id": 1, "name": "Cash", "required_information_name": null},
     {"id": 2, "name": "GCash", "required_information_name": "Reference Number"}]
    ''') as List,
  );

  test('indexes payment methods by id, upper-casing the names', () {
    // The rest of the app compares method names in upper case --
    // ReceiptSectionRegistry resolves "CASH" -- and two seeders have already
    // disagreed on capitalisation once.
    expect(methodsById[1]!.name, 'CASH');
    expect(methodsById[2]!.name, 'GCASH');
    expect(methodsById[1]!.extraFieldLabel, isNull);
    expect(methodsById[2]!.extraFieldLabel, 'Reference Number');
  });

  test('maps a venue into the Company the app prints on receipts', () {
    final bundle = mapEstablishmentsResponse(
      jsonDecode('''
      [{"id": 3, "name": "SM City Lucena", "address": "Lucena City, Quezon",
        "contact": "0917-100-2000", "incentive_percent": 10,
        "buffer_percent": 5, "active": true,
        "accepted_payment_methods": [1, 2]}]
      ''') as List,
      methodsById: methodsById,
    );

    final venue = bundle.companies.single;
    expect(venue.id, 3);
    expect(venue.name, 'SM City Lucena');
    expect(venue.address, 'Lucena City, Quezon');
    expect(venue.incentivePercent, 10);
    expect(venue.bufferPercent, 5);
    expect(
      bundle.paymentMethodsByCompanyId[3]!.map((m) => m.name),
      ['CASH', 'GCASH'],
    );
  });

  test('a venue accepting nothing still offers cash', () {
    // An empty payment menu leaves the POS unable to take money at all, which
    // reads as a broken till rather than a misconfigured venue.
    final bundle = mapEstablishmentsResponse(
      jsonDecode('''
      [{"id": 9, "name": "Bare Venue", "address": "", "contact": "",
        "incentive_percent": 0, "buffer_percent": 0,
        "accepted_payment_methods": []}]
      ''') as List,
      methodsById: methodsById,
    );

    expect(bundle.paymentMethodsByCompanyId[9]!.single.name, 'CASH');
  });

  test('ignores a method id the server no longer has', () {
    final bundle = mapEstablishmentsResponse(
      jsonDecode('''
      [{"id": 9, "name": "Venue", "address": "", "contact": "",
        "incentive_percent": 0, "buffer_percent": 0,
        "accepted_payment_methods": [1, 999]}]
      ''') as List,
      methodsById: methodsById,
    );

    expect(bundle.paymentMethodsByCompanyId[9]!.map((m) => m.name), ['CASH']);
  });

  test('rounds percentages, which the server stores as whole numbers', () {
    final body = establishmentBody(
      company: const Company(
        id: 1,
        name: 'V',
        address: 'A',
        contact: 'C',
        incentivePercent: 12.6,
        bufferPercent: 5.2,
      ),
      acceptedPaymentMethodIds: [1],
    );

    // Rounded here rather than truncated silently by the server.
    expect(body['incentive_percent'], 13);
    expect(body['buffer_percent'], 5);
  });
}
