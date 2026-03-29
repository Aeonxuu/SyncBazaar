import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart';

class AuthRepository {
  static const _rememberKey = 'remember_me';
  static const _userKey = 'user_json';

  final List<AppUser> demoUsers = const [
    AppUser(
      id: 1,
      name: 'Admin Demo',
      email: 'admin@syncbazaar.com',
      role: UserRole.admin,
    ),
    AppUser(
      id: 2,
      name: 'Owner Demo',
      email: 'owner@syncbazaar.com',
      role: UserRole.owner,
    ),
    AppUser(
      id: 3,
      name: 'Employee Demo',
      email: 'employee@syncbazaar.com',
      role: UserRole.employee,
      assignedEventId: 1,
    ),
  ];

  Future<AppUser?> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final user = demoUsers
        .where((u) => u.email.toLowerCase() == email.toLowerCase())
        .cast<AppUser?>()
        .firstWhere((u) => u != null, orElse: () => null);
    if (user == null || password != '123456') {
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
}
