import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification.dart';

/// Store for the notices the app raises about its own work -- [SyncService]
/// reporting what it pushed, and things the user did that should leave a trace.
///
/// Read state lives here rather than in the UI so the sidebar badge and the
/// Notifications screen can never disagree about how many are unread.
///
/// Kept on the device, not just in memory: marking a notice read and then
/// restarting the app brought every one of them back as unread, or lost them
/// altogether. Notices are device-local by nature (the server keeps its own,
/// separate notifications), so nothing here waits on the network.
class NotificationService {
  static const _kKey = 'notifications.v1';

  /// Oldest are dropped past this, so a tablet that syncs all day does not
  /// grow the stored list without limit.
  static const _kMaxKept = 200;

  final List<AppNotification> _notifications = [];
  int _nextId = 1;
  Future<void>? _loading;

  /// Shared, so two callers arriving at once wait on the same read instead of
  /// the second seeing an empty list.
  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      _notifications.insertAll(
        0,
        decoded.map(AppNotification.tryFromJson).whereType<AppNotification>(),
      );
      for (final n in _notifications) {
        if (n.id >= _nextId) {
          _nextId = n.id + 1;
        }
      }
    } catch (_) {
      // Unreadable storage means starting empty, not failing to open the app.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kKey,
        jsonEncode(_notifications.map((n) => n.toJson()).toList()),
      );
    } catch (_) {
      // Still held in memory for this run; only the next launch loses it.
    }
  }

  /// Newest first, which is the order the screen shows and the only order
  /// anyone reads a notification list in.
  Future<List<AppNotification>> listAll() async {
    await _ensureLoaded();
    return _notifications.reversed.toList();
  }

  Future<int> unreadCount() async {
    await _ensureLoaded();
    return _notifications.where((n) => !n.read).length;
  }

  Future<void> add({required String type, required String message}) async {
    await _ensureLoaded();
    _notifications.add(
      AppNotification(
        id: _nextId++,
        type: type,
        message: message,
        createdAt: DateTime.now(),
        read: false,
      ),
    );
    if (_notifications.length > _kMaxKept) {
      _notifications.removeRange(0, _notifications.length - _kMaxKept);
    }
    await _save();
  }

  Future<void> markAllRead() async {
    await _ensureLoaded();
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].read) {
        _notifications[i] = _notifications[i].copyWith(read: true);
      }
    }
    await _save();
  }

  Future<void> markRead(int id) async {
    await _ensureLoaded();
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _notifications[index] = _notifications[index].copyWith(read: true);
    await _save();
  }
}
