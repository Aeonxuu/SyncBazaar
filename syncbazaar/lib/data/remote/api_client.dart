import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';

/// Why a call failed, at the granularity the UI actually branches on.
///
/// The split that earns its keep is [network]/[timeout] versus everything else:
/// a till that cannot reach the server should keep selling and queue the sale,
/// while a 400 means the request itself was wrong and retrying changes nothing.
/// [ApiException.isOffline] is the question callers ask most, so it has a name.
enum ApiErrorKind { network, timeout, unauthorized, forbidden, notFound, badRequest, server }

/// A failed API call, carrying something printable.
///
/// Thrown rather than returned so repositories can stay on their current
/// signatures — `Future<AppUser?>` and friends already exist, and threading a
/// result type through every one of them is a bigger change than this slice
/// warrants.
class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  final ApiErrorKind kind;

  /// Safe to show a cashier: no stack traces, no JSON fragments.
  final String message;

  final int? statusCode;

  /// Whether the device could not reach the server at all, as opposed to
  /// reaching it and being told no. The offline queue keys off this.
  bool get isOffline =>
      kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  @override
  String toString() => message;
}

/// Thin wrapper over `http` that adds the token, decodes JSON, and turns every
/// failure into an [ApiException].
///
/// Deliberately not a repository: it knows nothing about products or sales, so
/// each repository can keep owning its own endpoints and shapes. It exists so
/// that the token header, the timeout, and error mapping are written once
/// rather than at every call site.
class ApiClient {
  ApiClient({http.Client? httpClient, String baseUrl = ApiConfig.baseUrl})
    : _http = httpClient ?? http.Client(),
      _baseUrl = baseUrl;

  final http.Client _http;
  final String _baseUrl;

  /// The token from `POST /api/auth/login/`, or null once logged out.
  ///
  /// Held in memory here and persisted by `AuthRepository`; this class is not
  /// responsible for remembering it across launches.
  String? token;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json';

    // Django REST Framework's TokenAuthentication expects the "Token " prefix
    // (not "Bearer "), per the backend's DEFAULT_AUTHENTICATION_CLASSES.
    final token = this.token;
    if (token != null) {
      request.headers['Authorization'] = 'Token $token';
    }

    if (body != null) {
      request.body = jsonEncode(body);
    }

    try {
      final streamed = await _http.send(request).timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on TimeoutException {
      throw const ApiException(
        ApiErrorKind.timeout,
        'The server took too long to respond. Check your connection.',
      );
    } on SocketException {
      throw const ApiException(
        ApiErrorKind.network,
        'Cannot reach the server. Check your connection.',
      );
    } on http.ClientException {
      // What the web build raises where dart:io would raise SocketException,
      // so an unreachable server reads the same on every platform.
      throw const ApiException(
        ApiErrorKind.network,
        'Cannot reach the server. Check your connection.',
      );
    }
  }

  dynamic _decode(http.Response response) {
    final status = response.statusCode;

    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) {
        return null;
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    }

    throw ApiException(
      _kindFor(status),
      _messageFor(response, status),
      statusCode: status,
    );
  }

  static ApiErrorKind _kindFor(int status) => switch (status) {
    401 => ApiErrorKind.unauthorized,
    403 => ApiErrorKind.forbidden,
    404 => ApiErrorKind.notFound,
    >= 400 && < 500 => ApiErrorKind.badRequest,
    _ => ApiErrorKind.server,
  };

  /// Pulls a sentence out of a DRF error body.
  ///
  /// The API answers in at least three shapes — `{"error": "..."}` from the
  /// hand-written login view, `{"detail": "..."}` from generic views, and
  /// `{"email": ["This field is required."]}` from serializer validation — so
  /// this tries each rather than assuming one and printing raw JSON at a
  /// cashier when it guesses wrong.
  static String _messageFor(http.Response response, int status) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        for (final key in const ['error', 'detail', 'message']) {
          final value = decoded[key];
          if (value is String && value.isNotEmpty) {
            return value;
          }
        }
        // Serializer errors: take the first field's first message, which is
        // the one the user needs to fix first anyway.
        for (final value in decoded.values) {
          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }
          if (value is String && value.isNotEmpty) {
            return value;
          }
        }
      }
    } on FormatException {
      // Not JSON — a Django HTML error page, most likely. Fall through.
    }

    return switch (status) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You do not have permission to do that.',
      404 => 'That item no longer exists.',
      >= 500 => 'The server ran into a problem. Try again shortly.',
      _ => 'Something went wrong (error $status).',
    };
  }

  void close() => _http.close();
}
