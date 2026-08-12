import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart';
import '../remote/api_client.dart';

/// Signing in goes to the API; everything else here is still in memory.
///
/// [login] and [restoreSession] talk to `/api/auth/login/`. The `_users` list
/// below still backs [listUsers], [addUser] and the rest, which the Staff and
/// Approvals screens read — so the signed-in user is real while the staff list
/// is not, until `/api/user/` is wired up next. Deliberate: one endpoint at a
/// time is what keeps this reviewable.
class AuthRepository {
  AuthRepository({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// Exposed so other repositories can share the authenticated client as they
  /// migrate, rather than each creating one and re-authenticating.
  ApiClient get api => _api;

  static const _rememberKey = 'remember_me';
  static const _userKey = 'user_json';
  static const _tokenKey = 'auth_token';
  static const _vendorKey = 'vendor_id';
  static const _vendorNameKey = 'vendor_name';
  static const _defaultPassword = '123456';

  /// Which vendor the signed-in user belongs to, from the login response.
  ///
  /// Every product URL is `/api/core/vendor/<vendor_id>/product/`, so this is
  /// required for anything inventory-shaped. Read from the session rather than
  /// hardcoded: the backend is already multi-vendor, so supporting more than
  /// one later needs no client change — a different login returns a different
  /// id.
  int? vendorId;

  String? vendorName;

  final List<AppUser> _users = [
    const AppUser(
      id: 1,
      name: 'Amrei',
      email: 'admin@syncbazaar.com',
      role: UserRole.admin,
    ),
    const AppUser(
      id: 2,
      name: 'Lalaine',
      email: 'owner@syncbazaar.com',
      role: UserRole.owner,
    ),
    // No assignment here. This used to pin Via to event 1, which the seeder
    // creates as August Fair — while the dataset also puts her on Weekend
    // Pop-Up, whose dates swallow it. That is a double-booking: one person at
    // two stalls on the same day. Assignments come from the dataset alone now,
    // so the two cannot disagree.
    const AppUser(
      id: 3,
      name: 'Via',
      email: 'employee@syncbazaar.com',
      role: UserRole.employee,
    ),
    const AppUser(
      id: 4,
      name: 'Missy',
      email: 'missy@syncbazaar.com',
      role: UserRole.employee,
    ),
    const AppUser(
      id: 5,
      name: 'TG',
      email: 'tg@syncbazaar.com',
      role: UserRole.employee,
    ),
    const AppUser(
      id: 6,
      name: 'Sen',
      email: 'sen@syncbazaar.com',
      role: UserRole.employee,
    ),
  ];

  final Map<int, String> _passwordByUserId = {
    1: _defaultPassword,
    2: _defaultPassword,
    3: _defaultPassword,
    4: 'missy123',
    5: 'tg123',
    6: 'sen123',
  };

  Future<List<AppUser>> listUsers() async => List<AppUser>.from(_users);

  Future<AppUser> addUser({
    required String name,
    required String email,
    required UserRole role,
    String? password,
  }) async {
    final nextId = _users.isEmpty
        ? 1
        : _users.map((user) => user.id).reduce((a, b) => a > b ? a : b) + 1;
    final created = AppUser(id: nextId, name: name, email: email, role: role);
    _users.add(created);
    _passwordByUserId[nextId] = (password != null && password.isNotEmpty)
        ? password
        : _defaultPassword;
    return created;
  }

  Future<void> updateUser({
    required int id,
    required String name,
    required String email,
    required UserRole role,
    String? password,
  }) async {
    final index = _users.indexWhere((user) => user.id == id);
    if (index == -1) {
      return;
    }
    final current = _users[index];
    _users[index] = current.copyWith(
      name: name,
      email: email,
      role: role,
      clearAssignedEventId: role != UserRole.employee,
    );
    if (password != null && password.isNotEmpty) {
      _passwordByUserId[id] = password;
    }
    await _syncRememberedUserIfAffected(_users[index]);
  }

  Future<void> deleteUser(int id) async {
    _users.removeWhere((user) => user.id == id);
    _passwordByUserId.remove(id);
    await _clearRememberedIfDeleted(id);
  }

  Future<void> assignEmployeesToBazaar({
    required int eventId,
    required List<int> employeeIds,
  }) async {
    final employeeIdSet = employeeIds.toSet();
    for (final employeeId in employeeIdSet) {
      final index = _users.indexWhere(
        (user) => user.id == employeeId && user.role == UserRole.employee,
      );
      if (index == -1) {
        continue;
      }
      final user = _users[index];
      final mergedAssignedEventIds = {
        ...user.assignedEventIdsEffective,
        eventId,
      }.toList();

      _users[index] = user.copyWith(
        assignedEventId: eventId,
        assignedEventIds: mergedAssignedEventIds,
      );
      await _syncRememberedUserIfAffected(_users[index]);
    }
  }

  /// Signs in against the API.
  ///
  /// Returns null for rejected credentials, so the existing `AuthCubit`
  /// contract still holds. Anything else — server unreachable, timeout, a 500 —
  /// throws [ApiException], because "your password is wrong" and "the bazaar
  /// has no signal" need different words on screen and only the caller can say
  /// them.
  ///
  /// The token is always kept for the session in memory; [rememberMe] decides
  /// only whether it also survives a relaunch.
  Future<AppUser?> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    // Lower-cased, not just trimmed. The API matches the address exactly, so
    // "Owner@..." is rejected as unknown -- and a tablet keyboard capitalises
    // the first letter of a field by default, which makes that the *normal*
    // way a cashier types their address rather than an unlucky one. Nothing on
    // screen distinguishes it from a wrong password.
    final normalizedEmail = email.trim().toLowerCase();

    final Map<String, dynamic> body;
    try {
      body =
          await _api.post(
                '/api/auth/login/',
                body: {'email': normalizedEmail, 'password': password},
              )
              as Map<String, dynamic>;
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.unauthorized) {
        return null;
      }
      rethrow;
    }

    final user = AppUser.fromLoginResponse(body, email: normalizedEmail);
    final token = body['token'] as String?;

    _api.token = token;
    vendorId = (body['vendor_id'] as num?)?.toInt();
    vendorName = body['vendor_name'] as String?;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, rememberMe);
    if (rememberMe) {
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      if (token != null) {
        await prefs.setString(_tokenKey, token);
      }
      if (vendorId != null) {
        await prefs.setInt(_vendorKey, vendorId!);
      }
      if (vendorName != null) {
        await prefs.setString(_vendorNameKey, vendorName!);
      }
    } else {
      await _clearStoredSession(prefs);
    }
    return user;
  }

  /// Restores a remembered session, token included.
  ///
  /// The token has to come back with the user: without it every subsequent
  /// request is unauthenticated, and the app would look signed in while the API
  /// answers 401 to everything.
  Future<AppUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberKey) ?? false;
    if (!remember) {
      return null;
    }
    final userJson = prefs.getString(_userKey);
    if (userJson == null) {
      return null;
    }

    _api.token = prefs.getString(_tokenKey);
    vendorId = prefs.getInt(_vendorKey);
    vendorName = prefs.getString(_vendorNameKey);

    return AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
  }

  /// Clears the session locally, then tells the server to drop the token.
  ///
  /// Local first, and the network call is best-effort: a cashier tapping log
  /// out on a tablet with no signal must still end up logged out. The stale
  /// token left on the server is the lesser problem.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearStoredSession(prefs);
    await prefs.remove(_rememberKey);

    try {
      await _api.post('/api/auth/logout/');
    } on ApiException {
      // Already signed out as far as this device is concerned.
    }

    _api.token = null;
    vendorId = null;
    vendorName = null;
  }

  Future<void> _clearStoredSession(SharedPreferences prefs) async {
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_vendorKey);
    await prefs.remove(_vendorNameKey);
  }

  Future<void> _syncRememberedUserIfAffected(AppUser updatedUser) async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getString(_userKey);
    if (remembered == null) {
      return;
    }
    final stored = AppUser.fromJson(
      jsonDecode(remembered) as Map<String, dynamic>,
    );
    if (stored.id != updatedUser.id) {
      return;
    }
    await prefs.setString(_userKey, jsonEncode(updatedUser.toJson()));
  }

  Future<void> _clearRememberedIfDeleted(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getString(_userKey);
    if (remembered == null) {
      return;
    }
    final stored = AppUser.fromJson(
      jsonDecode(remembered) as Map<String, dynamic>,
    );
    if (stored.id != userId) {
      return;
    }
    await prefs.remove(_rememberKey);
    await prefs.remove(_userKey);
  }
}
