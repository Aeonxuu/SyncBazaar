import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';

/// Why a call failed, at the granularity the UI actually branches on.
///
/// The split that earns its keep is [network]/[timeout] versus everything else:
/// a till that cannot reach the server should keep selling and queue the sale,
/// while a 400 means the request itself was wrong and retrying changes nothing.
/// [ApiException.isOffline] is the question callers ask most, so it has a name.
enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  badRequest,
  server,
}

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

  /// When the server last answered anything at all.
  ///
  /// Any reply counts, including a 401: the question this tracks is whether
  /// the host is awake, and a refusal proves it just as well as a success.
  DateTime? _lastReplyAt;

  /// The allowance for the next call.
  ///
  /// Long only while it is unknown whether the host is awake. During a bazaar
  /// calls are constant, so this is [ApiConfig.timeout] throughout and a
  /// cashier still learns within ten seconds that there is no signal.
  Duration get _nextTimeout {
    final last = _lastReplyAt;
    if (last == null || DateTime.now().difference(last) > ApiConfig.warmFor) {
      return ApiConfig.coldStartTimeout;
    }
    return ApiConfig.timeout;
  }

  /// Visible for tests, which have no real server to wake.
  @visibleForTesting
  Duration get nextTimeout => _nextTimeout;

  @visibleForTesting
  void markAwake([DateTime? at]) => _lastReplyAt = at ?? DateTime.now();

  /// The token from `POST /api/auth/login/`, or null once logged out.
  ///
  /// Held in memory here and persisted by `AuthRepository`; this class is not
  /// responsible for remembering it across launches.
  String? token;

  Future<dynamic> get(String path) => _send('GET', path);

  /// Fetches a file rather than JSON.
  ///
  /// The report endpoints answer with a .docx or a .csv, and [get] would try to
  /// parse those as JSON and throw on the first byte. Returns the body and the
  /// name the server chose, which is worth honouring: it already names the file
  /// after the bazaar, and inventing one here would drift from the server's.
  Future<ApiDownload> getFile(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = http.Request('GET', uri);
    final token = this.token;
    if (token != null) {
      request.headers['Authorization'] = 'Token $token';
    }

    try {
      final streamed = await _http.send(request).timeout(_fileTimeout);
      final response = await http.Response.fromStream(streamed);
      _lastReplyAt = DateTime.now();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _kindFor(response.statusCode),
          _messageFor(response, response.statusCode),
          statusCode: response.statusCode,
        );
      }
      return ApiDownload(
        bytes: response.bodyBytes,
        fileName: _fileNameFrom(response.headers['content-disposition']),
      );
    } on TimeoutException {
      throw const ApiException(
        ApiErrorKind.timeout,
        'The server took too long to prepare the file.',
      );
    } on SocketException {
      throw const ApiException(
        ApiErrorKind.network,
        'Cannot reach the server. Check your connection.',
      );
    } on http.ClientException {
      throw const ApiException(
        ApiErrorKind.network,
        'Cannot reach the server. Check your connection.',
      );
    }
  }

  /// A document takes longer than a normal call: the server renders it before
  /// it answers. Built on [_nextTimeout] so a file fetched while the host is
  /// still waking gets the same allowance every other call does, plus the
  /// rendering time on top.
  ///
  /// Warm this is 60s, unchanged from when it was a constant.
  Duration get _fileTimeout => _nextTimeout + const Duration(seconds: 50);

  /// Pulls the filename out of `Content-Disposition`, or null if absent.
  static String? _fileNameFrom(String? header) {
    if (header == null) {
      return null;
    }
    final match = RegExp(
      'filename\\*?=(?:UTF-8\'\')?"?([^";]+)"?',
    ).firstMatch(header);
    final name = match?.group(1)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

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
      final streamed = await _http.send(request).timeout(_nextTimeout);
      final response = await http.Response.fromStream(streamed);
      _lastReplyAt = DateTime.now();
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

/// A file fetched from the API, with the name the server gave it.
class ApiDownload {
  const ApiDownload({required this.bytes, this.fileName});

  final Uint8List bytes;

  /// From `Content-Disposition`, e.g. `SOA_August_Fair.docx`. Null when the
  /// server did not say, in which case the caller names it.
  final String? fileName;

  /// The name without its extension, which is what `file_saver` wants — it
  /// appends the extension itself and would otherwise produce "x.docx.docx".
  String? get stem {
    final name = fileName;
    if (name == null) return null;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }
}
