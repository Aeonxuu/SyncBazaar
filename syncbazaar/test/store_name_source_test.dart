import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';

/// The store name is a fact about the business, not a preference of the
/// tablet.
///
/// It heads every receipt and is printed six times on the statement of
/// account -- and that document is rendered by the *server*. While the name
/// was kept locally the two could disagree, and a second vendor signing into
/// this app would have printed the first vendor's name on their receipts.
/// These pin the name to the session.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('without a session it falls back to the device setting', () async {
    // The no-backend build still has to print something on a receipt.
    final settings = SettingsRepository();

    expect(await settings.storeName(), 'SyncBazaar');
    await settings.setStoreName('Corner Store');
    expect(await settings.storeName(), 'Corner Store');
    expect(settings.storeNameIsVendor, isFalse);
  });

  test(
    'signed in, the vendor name wins over anything stored locally',
    () async {
      final auth = AuthRepository()
        ..vendorId = 4
        ..vendorName = 'SV KICKz';
      final settings = SettingsRepository(auth: auth);

      // A stale local value from before the account existed must not win: this
      // is the drift that put one name on screen and another on the paperwork.
      SharedPreferences.setMockInitialValues({
        'settings.storeName': 'Some Old Name',
      });

      expect(await settings.storeName(), 'SV KICKz');
      expect(settings.storeNameIsVendor, isTrue);
    },
  );

  test('a different vendor signing in gets their own name', () async {
    final auth = AuthRepository()
      ..vendorId = 9
      ..vendorName = 'Tita Baby Ukay-Ukay';
    final settings = SettingsRepository(auth: auth);

    expect(await settings.storeName(), 'Tita Baby Ukay-Ukay');
  });

  test(
    'an empty vendor name falls through rather than printing blank',
    () async {
      // A receipt must never be headed by an empty line.
      final auth = AuthRepository()
        ..vendorId = 4
        ..vendorName = '   ';
      final settings = SettingsRepository(auth: auth);

      expect(await settings.storeName(), 'SyncBazaar');
    },
  );

  test('renaming without a session refuses rather than pretending', () async {
    final auth = AuthRepository();

    await expectLater(
      auth.renameVendor('Anything'),
      throwsA(isA<StateError>()),
    );
  });

  test('an empty rename is rejected before it reaches the server', () async {
    final auth = AuthRepository()
      ..vendorId = 4
      ..vendorName = 'SV KICKz';

    await expectLater(
      auth.renameVendor('   '),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.badRequest,
        ),
      ),
    );
    // The old name survives a rejected rename.
    expect(auth.vendorName, 'SV KICKz');
  });
}
