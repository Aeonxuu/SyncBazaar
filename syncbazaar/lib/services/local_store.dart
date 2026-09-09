import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small durable store for the handful of things that must outlive the app.
///
/// Backed by `shared_preferences` rather than a database on purpose. The whole
/// seeded dataset is 112 KB and a day's trading is a few hundred sales, which
/// is far below where sqflite, hive or drift earn their code generation,
/// migrations and separate web implementation. It is already a dependency, it
/// behaves the same on the tablet, macOS and web, and a test can replace it
/// with one line.
///
/// Deliberately knows nothing about models. It moves JSON, so it can be tested
/// on its own and reused by whatever needs persisting next.
///
/// If sales ever outgrow this, the backing changes here without touching a
/// caller.
class LocalStore {
  const LocalStore();

  /// Reads rows previously written under [key], or an empty list.
  ///
  /// Unreadable content is discarded rather than thrown. This runs during
  /// start-up, and a till that will not open is worse than one that has
  /// forgotten something: the same rule the stored QR codes already follow.
  Future<List<Map<String, dynamic>>> readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Replaces everything under [key]. An empty list removes it, so nothing is
  /// left behind holding `"[]"`.
  Future<void> writeList(String key, List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    if (rows.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(rows));
  }

  Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
