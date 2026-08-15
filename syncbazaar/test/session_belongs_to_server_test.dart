import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';

/// A session belongs to the backend that issued it.
///
/// This app is pointed at different servers by a launch flag — a laptop while
/// testing API changes, the hosted one otherwise — and they are separate
/// databases. The same email is user 64 on one and user 2 on the other, under
/// different vendors. Carrying a session across that boundary sent a token the
/// other server had never seen and asked for a vendor belonging to somebody
/// else, which showed up as "invalid token" beside an empty app.
void main() {
  const local = 'http://127.0.0.1:8000';
  const hosted = 'https://syncbazaar-backend.onrender.com';

  /// A remembered session, as `login` would have left it.
  void storeSessionFrom(String server) {
    SharedPreferences.setMockInitialValues({
      'remember_me': true,
      'user_json': jsonEncode({
        'id': 64,
        'name': 'Lalaine',
        'email': 'owner@syncbazaar.com',
        'role': 'owner',
      }),
      'auth_token': 'a-token-only-that-server-knows',
      'vendor_id': 4,
      'vendor_name': 'SV KICKz',
      'session_server': server,
    });
  }

  test('a session restores against the server that issued it', () async {
    storeSessionFrom(local);
    final auth = AuthRepository(apiClient: ApiClient(baseUrl: local));

    final user = await auth.restoreSession();

    expect(user, isNotNull);
    expect(auth.vendorId, 4);
    expect(auth.api.token, 'a-token-only-that-server-knows');
  });

  test('a session from another server is dropped, not carried over', () async {
    storeSessionFrom(local);
    final auth = AuthRepository(apiClient: ApiClient(baseUrl: hosted));

    final user = await auth.restoreSession();

    // Signed out rather than signed in to the wrong place. One login is a
    // cheaper price than an app that shows nothing and blames the token.
    expect(user, isNull);
    expect(auth.api.token, isNull);
    expect(auth.vendorId, isNull);
  });

  test('the dropped session does not come back on the next launch', () async {
    storeSessionFrom(local);
    await AuthRepository(
      apiClient: ApiClient(baseUrl: hosted),
    ).restoreSession();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token'), isNull);
    expect(prefs.getInt('vendor_id'), isNull);
    expect(prefs.getString('session_server'), isNull);
  });

  test('a session stored before this existed is still honoured', () async {
    // Upgrading the app should not sign anyone out on the spot.
    SharedPreferences.setMockInitialValues({
      'remember_me': true,
      'user_json': jsonEncode({
        'id': 64,
        'name': 'Lalaine',
        'email': 'owner@syncbazaar.com',
        'role': 'owner',
      }),
      'auth_token': 'older-session',
      'vendor_id': 4,
    });
    final auth = AuthRepository(apiClient: ApiClient(baseUrl: local));

    expect(await auth.restoreSession(), isNotNull);
  });
}
