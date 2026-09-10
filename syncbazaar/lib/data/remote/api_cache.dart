import 'dart:convert';

import '../../services/local_store.dart';

/// The last good answer the server gave to each GET.
///
/// Kept so the app can open and be worked with when the server cannot be
/// reached. A bazaar is exactly where that happens: the stall has no signal,
/// the cashier reopens the app, and without this the catalogue, the bazaars and
/// the venues are all simply absent.
///
/// Responses are stored as the server sent them, not as parsed models. The
/// mappers stay the only thing that knows how to read the API, so a cached
/// answer and a live one go through identical code and cannot drift apart. It
/// also means nothing new has to learn to serialise itself.
///
/// Only GETs, and only successful ones. A 403 or a 500 is a real answer and
/// must not be papered over with yesterday's data.
class ApiCache {
  const ApiCache({LocalStore store = const LocalStore()}) : _store = store;

  final LocalStore _store;

  static const String _prefix = 'api.cache.';

  String _keyFor(String path) => '$_prefix$path';

  Future<void> write(String path, String body) async {
    try {
      await _store.writeRaw(
        _keyFor(path),
        jsonEncode({
          'stored_at': DateTime.now().toIso8601String(),
          'body': body,
        }),
      );
    } catch (_) {
      // A cache that cannot be written is a missing convenience, never a
      // failed request. The live answer has already been returned.
    }
  }

  /// The stored answer for [path], or null if there is none to give.
  Future<CachedResponse?> read(String path) async {
    try {
      final raw = await _store.readRaw(_keyFor(path));
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) {
        return null;
      }
      final body = envelope['body'];
      if (body is! String) {
        return null;
      }
      return CachedResponse(
        body: jsonDecode(body),
        storedAt:
            DateTime.tryParse(envelope['stored_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      // Unreadable cache is no cache. The caller falls back to the error it
      // already had, which is the truthful outcome.
      return null;
    }
  }

  /// Forgets everything, for a sign-out. A cache outliving the session it was
  /// fetched under would show one vendor's data to the next person to log in.
  Future<void> clearAll() async {
    try {
      for (final key in await _store.keysWithPrefix(_prefix)) {
        await _store.clear(key);
      }
    } catch (_) {
      // Nothing useful to do, and a failed sign-out is worse than a stale key.
    }
  }
}

/// A stored answer, and when it was stored.
class CachedResponse {
  const CachedResponse({required this.body, required this.storedAt});

  /// Already decoded, so it reaches a mapper in the same shape a live response
  /// would.
  final dynamic body;

  final DateTime storedAt;
}
