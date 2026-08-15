import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/models/user.dart';

/// Covers the login path against a stubbed API rather than a live server, so
/// the suite still passes with the backend switched off.
///
/// The shapes asserted here are the ones the real backend returned when this
/// was written: `{token, user_id, role, name, vendor_id, vendor_name}` on
/// success, `{"error": ...}` with 401 on bad credentials.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AuthRepository repositoryReturning(
    Object? body, {
    int status = 200,
    void Function(http.Request request)? onRequest,
  }) {
    final client = MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return AuthRepository(apiClient: ApiClient(httpClient: client));
  }

  const loginResponse = {
    'token': 'abc123',
    'user_id': 7,
    'role': 'OW',
    'name': 'Marika Mendoza',
    'vendor_id': 1,
    'vendor_name': 'FashionHub',
  };

  test(
    'maps a successful login into an AppUser and keeps the vendor',
    () async {
      final repository = repositoryReturning(loginResponse);

      final user = await repository.login(
        email: 'owner@fashionhub.com',
        password: 'ownerpass',
        rememberMe: true,
      );

      expect(user, isNotNull);
      expect(user!.id, 7);
      expect(user.name, 'Marika Mendoza');
      expect(user.email, 'owner@fashionhub.com');
      expect(user.role, UserRole.owner);
      expect(repository.vendorId, 1);
      expect(repository.vendorName, 'FashionHub');
      expect(repository.api.token, 'abc123');
    },
  );

  test('sends the credentials as JSON to the login endpoint', () async {
    late http.Request captured;
    final repository = repositoryReturning(
      loginResponse,
      onRequest: (request) => captured = request,
    );

    await repository.login(
      email: '  Owner@FashionHub.com  ',
      password: 'ownerpass',
      rememberMe: false,
    );

    expect(captured.url.path, '/api/auth/login/');
    expect(captured.method, 'POST');
    expect(jsonDecode(captured.body), {
      // Trimmed and lower-cased. The API matches the address exactly, and a
      // tablet keyboard capitalises the first letter by default -- so the way
      // a cashier normally types their address would otherwise be rejected as
      // an unknown user, indistinguishable on screen from a wrong password.
      'email': 'owner@fashionhub.com',
      'password': 'ownerpass',
    });
  });

  test('returns null for rejected credentials rather than throwing', () async {
    final repository = repositoryReturning({
      'error': 'Invalid login credentials',
    }, status: 401);

    final user = await repository.login(
      email: 'owner@fashionhub.com',
      password: 'wrong',
      rememberMe: false,
    );

    expect(user, isNull);
  });

  // Both failure shapes matter: dart:io raises SocketException on mobile and
  // desktop, while the browser build surfaces the same unreachable server as
  // http.ClientException. A cashier must get the offline message either way.
  for (final (label, error) in <(String, Object)>[
    ('SocketException', const SocketException('Connection refused')),
    ('ClientException', http.ClientException('Connection closed')),
  ]) {
    test('reports offline when the server is unreachable ($label)', () async {
      final client = MockClient((_) async => throw error);
      final repository = AuthRepository(
        apiClient: ApiClient(httpClient: client),
      );

      await expectLater(
        repository.login(
          email: 'owner@fashionhub.com',
          password: 'ownerpass',
          rememberMe: false,
        ),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'isOffline', isTrue),
        ),
      );
    });
  }

  test('restores the token alongside the user, not just the user', () async {
    final repository = repositoryReturning(loginResponse);
    await repository.login(
      email: 'owner@fashionhub.com',
      password: 'ownerpass',
      rememberMe: true,
    );

    // A fresh repository stands in for a relaunched app.
    final revived = repositoryReturning(loginResponse);
    final restored = await revived.restoreSession();

    expect(restored, isNotNull);
    expect(restored!.role, UserRole.owner);
    // Without this the app looks signed in while every call 401s.
    expect(revived.api.token, 'abc123');
    expect(revived.vendorId, 1);
  });

  test('rememberMe false leaves nothing behind to restore', () async {
    final repository = repositoryReturning(loginResponse);
    await repository.login(
      email: 'owner@fashionhub.com',
      password: 'ownerpass',
      rememberMe: false,
    );

    final revived = repositoryReturning(loginResponse);
    expect(await revived.restoreSession(), isNull);
    expect(revived.api.token, isNull);
  });

  test(
    'carries the employee event assignments off the login response',
    () async {
      final repository = repositoryReturning({
        'token': 'abc123',
        'user_id': 4,
        'role': 'EM',
        'name': 'Missy',
        'vendor_id': 1,
        'vendor_name': 'SV KICKz',
        'assigned_event_ids': [1, 3, 7, 11],
      });

      final user = await repository.login(
        email: 'missy@syncbazaar.com',
        password: 'missy123',
        rememberMe: false,
      );

      // The event list is scoped server-side *and* filtered again on the client
      // against these ids. Dropping them turned a correct list of four bazaars
      // into none, and an employee signed in to an app with nothing to sell.
      expect(user!.assignedEventIdsEffective, [1, 3, 7, 11]);
    },
  );

  test('an owner with no assignments is not scoped to nothing', () async {
    final repository = repositoryReturning({
      'token': 'abc123',
      'user_id': 2,
      'role': 'OW',
      'name': 'Lalaine',
      'vendor_id': 1,
      'vendor_name': 'SV KICKz',
      'assigned_event_ids': <int>[],
    });

    final user = await repository.login(
      email: 'owner@syncbazaar.com',
      password: '123456',
      rememberMe: false,
    );

    expect(user!.assignedEventIdsEffective, isEmpty);
    // Owners see every bazaar regardless, which is what stops an empty list
    // here from hiding the whole app from them.
    expect(user.isAdminOrOwner, isTrue);
  });

  test('maps every backend role code', () {
    expect(userRoleFromApiCode('AD'), UserRole.admin);
    expect(userRoleFromApiCode('OW'), UserRole.owner);
    expect(userRoleFromApiCode('EM'), UserRole.employee);
    // Unknown and null fail closed, to the least privileged role.
    expect(userRoleFromApiCode('??'), UserRole.employee);
    expect(userRoleFromApiCode(null), UserRole.employee);

    expect(UserRole.admin.apiCode, 'AD');
    expect(UserRole.owner.apiCode, 'OW');
    expect(UserRole.employee.apiCode, 'EM');
  });
}
