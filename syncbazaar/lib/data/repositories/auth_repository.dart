import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart';

class AuthRepository {
  static const _rememberKey = 'remember_me';
  static const _userKey = 'user_json';
  static const _defaultPassword = '123456';

  final List<AppUser> _users = [
    AppUser(
      id: 1,
      name: 'Amrei',
      email: 'admin@syncbazaar.com',
      role: UserRole.admin,
    ),
    AppUser(
      id: 2,
      name: 'Lalaine',
      email: 'owner@syncbazaar.com',
      role: UserRole.owner,
    ),
    AppUser(
      id: 3,
      name: 'Via',
      email: 'employee@syncbazaar.com',
      role: UserRole.employee,
      assignedEventId: 1,
      assignedEventIds: [1],
    ),
    AppUser(
      id: 4,
      name: 'Missy',
      email: 'missy@syncbazaar.com',
      role: UserRole.employee,
    ),
    AppUser(
      id: 5,
      name: 'TG',
      email: 'tg@syncbazaar.com',
      role: UserRole.employee,
    ),
    AppUser(
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
    final created = AppUser(
      id: nextId,
      name: name,
      email: email,
      role: role,
    );
    _users.add(created);
    _passwordByUserId[nextId] =
      (password != null && password.isNotEmpty) ? password : _defaultPassword;
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

  Future<AppUser?> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final user = _users
        .where((u) => u.email.toLowerCase() == email.toLowerCase())
        .cast<AppUser?>()
        .firstWhere((u) => u != null, orElse: () => null);
    if (user == null) {
      return null;
    }

    final expectedPassword = _passwordByUserId[user.id] ?? _defaultPassword;
    if (password != expectedPassword) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, rememberMe);
    if (rememberMe) {
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    } else {
      await prefs.remove(_userKey);
    }
    return user;
  }

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
    return AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberKey);
    await prefs.remove(_userKey);
  }

  Future<void> _syncRememberedUserIfAffected(AppUser updatedUser) async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getString(_userKey);
    if (remembered == null) {
      return;
    }
    final stored = AppUser.fromJson(jsonDecode(remembered) as Map<String, dynamic>);
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
    final stored = AppUser.fromJson(jsonDecode(remembered) as Map<String, dynamic>);
    if (stored.id != userId) {
      return;
    }
    await prefs.remove(_rememberKey);
    await prefs.remove(_userKey);
  }
}
