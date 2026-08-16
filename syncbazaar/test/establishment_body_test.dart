import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/establishment_api_mapper.dart';
import 'package:syncbazaar/models/company.dart';

/// What a venue looks like on the wire.
///
/// The address and contact are offered as optional in the editor, and the
/// server rejects either being blank outright -- so a venue saved without
/// them came back 400 and, with nothing catching it, simply never appeared.
void main() {
  Company venue({String address = 'Lucena City', String contact = '0917'}) =>
      Company(
        id: 1,
        name: 'SM City Lucena',
        address: address,
        contact: contact,
        incentivePercent: 10,
        bufferPercent: 5,
      );

  test('a filled address and contact are sent as typed', () {
    final body = establishmentBody(
      company: venue(),
      acceptedPaymentMethodIds: const [1],
    );

    expect(body['address'], 'Lucena City');
    expect(body['contact'], '0917');
  });

  test('a blank address is sent as a placeholder, not as blank', () {
    final body = establishmentBody(
      company: venue(address: ''),
      acceptedPaymentMethodIds: const [1],
    );

    // "This field may not be blank" is what the server says otherwise.
    expect(body['address'], isNot(''));
    expect(body['address'], '-');
  });

  test('whitespace counts as blank', () {
    final body = establishmentBody(
      company: venue(contact: '   '),
      acceptedPaymentMethodIds: const [1],
    );

    expect(body['contact'], '-');
  });

  test('percentages are whole numbers', () {
    // The column is an integer, so a fractional rate would be truncated
    // server-side where nobody would see it happen.
    final body = establishmentBody(
      company: const Company(
        id: 1,
        name: 'X',
        address: 'a',
        contact: 'c',
        incentivePercent: 10.6,
        bufferPercent: 5.2,
      ),
      acceptedPaymentMethodIds: const [],
    );

    expect(body['incentive_percent'], 11);
    expect(body['buffer_percent'], 5);
  });
}
