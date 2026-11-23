import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Low level HTTP client shared by every repository.
///
/// Responsibilities that used to be duplicated (and got wrong) across the
/// codebase live here exactly once:
///  * attach the bearer token;
///  * serialise and decode JSON;
///  * turn every failure into a user-safe [ApiException];
///  * decode the `Retry-After` header so rate limits can be explained.
class ApiClient {
  ApiClient({http.Client? httpClient, TokenStore? tokenStore})
      : _http = httpClient ?? http.Client(),
        _tokens = tokenStore ?? TokenStore();

  final http.Client _http;
  final TokenStore _tokens;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Called when the backend reports the token is no longer valid, so the app
  /// can bounce the user back to the login screen exactly once.
  VoidCallback? onUnauthorized;

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{..._jsonHeaders};
    if (auth) {
      final token = await _tokens.read();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // ---------------------------------------------------------------------
  // Verbs
  // ---------------------------------------------------------------------
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return _send(
      () async => _http.get(_uri(path, query), headers: await _headers()),
    );
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    return _send(
      () async => _http.post(
        _uri(path, query),
        headers: await _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    return _send(
      () async => _http.put(
        _uri(path, query),
        headers: await _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    return _send(
      () async => _http.patch(
        _uri(path, query),
        headers: await _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) async {
    return _send(
      () async => _http.delete(_uri(path, query), headers: await _headers()),
    );
  }

  /// Fetch raw bytes with auth headers (used for authenticated document viewing).
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    late final http.Response response;
    try {
      response = await _http
          .get(_uri(path, query), headers: await _headers())
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException(
        'The server took too long to respond. Please try again.',
        isNetworkError: true,
      );
    } on SocketException catch (e) {
      throw _connectionFailure(e.osError?.message ?? e.message);
    } on http.ClientException catch (e) {
      throw _connectionFailure(e.message);
    }
    if (response.statusCode == 401) onUnauthorized?.call();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    final decoded = _decodeBody(response);
    throw ApiException(
      _extractMessage(response, decoded),
      statusCode: response.statusCode,
      debugDetail: response.body,
    );
  }

  /// Multipart upload, used by the field member proof photo.
  Future<dynamic> multipart(
    String path, {
    required Map<String, String> fields,
    Map<String, dynamic>? query,
    String fileField = 'proof',
    String? filePath,
    List<int>? fileBytes,
    String? fileName,
  }) async {
    return _send(() async {
      final request = http.MultipartRequest('POST', _uri(path, query));
      request.headers.addAll(await _headers());
      request.fields.addAll(fields);
      if (filePath != null || fileBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            fileField,
            fileBytes ?? (await File(filePath!).readAsBytes()),
            filename: fileName ?? 'proof.jpg',
          ),
        );
      }
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  Uri _uri(String path, Map<String, dynamic>? query) {
    final normalised = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${AppConfig.baseUrl}$normalised');
    if (query == null || query.isEmpty) return uri;
    final cleaned = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      final text = '$value';
      if (text.isEmpty) return;
      cleaned[key] = text;
    });
    if (cleaned.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...cleaned});
  }

  // ---------------------------------------------------------------------
  // Response handling
  // ---------------------------------------------------------------------
  Future<dynamic> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request().timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException(
        'The server took too long to respond. Please try again.',
        isNetworkError: true,
        debugDetail: 'timeout after ${AppConfig.requestTimeout.inSeconds}s',
      );
    } on SocketException catch (e) {
      throw _connectionFailure(e.osError?.message ?? e.message);
    } on http.ClientException catch (e) {
      throw _connectionFailure(e.message);
    } on HandshakeException {
      throw const ApiException(
        'Could not establish a secure connection to the server.',
        isNetworkError: true,
      );
    }

    if (response.statusCode == 401) {
      // Let the session layer react, but still surface the normal message so
      // the calling screen can show it if it wants to.
      onUnauthorized?.call();
    }

    final decoded = _decodeBody(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw ApiException(
      _extractMessage(response, decoded),
      statusCode: response.statusCode,
      debugDetail: response.body,
    );
  }

  ApiException _connectionFailure(String detail) {
    return ApiException(
      'Cannot reach the server at ${AppConfig.baseUrlHost}. '
      'Check that the backend is running and that the app is pointed at the right address.',
      isNetworkError: true,
      debugDetail: detail,
    );
  }

  dynamic _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('text/') ||
        contentType.contains('application/json') ||
        _looksLikeJson(response.body)) {
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        return response.body;
      }
    }
    return response.body;
  }

  bool _looksLikeJson(String body) {
    final trimmed = body.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  String _extractMessage(http.Response response, dynamic decoded) {
    if (decoded is Map && decoded['detail'] != null) {
      final detail = decoded['detail'];
      if (detail is String) return detail;
      // FastAPI validation errors arrive as a list of objects.
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return '${first['msg']}'
                  '${_fieldSuffix(first['loc'])}'
              .replaceFirst('Value error, ', '');
        }
      }
    }

    final retryAfter = response.headers['retry-after'];
    if (response.statusCode == 429) {
      return retryAfter != null
          ? 'Too many attempts. Please wait $retryAfter seconds and try again.'
          : 'Too many attempts. Please wait a moment and try again.';
    }
    if (response.statusCode >= 500) {
      return 'Something went wrong on our side. Please try again shortly.';
    }
    return 'That request could not be completed (error ${response.statusCode}).';
  }

  String _fieldSuffix(dynamic loc) {
    if (loc is! List || loc.isEmpty) return '';
    final field = loc.skip(1).join('.').replaceAll('_', ' ');
    return field.isEmpty ? '' : ' ($field)';
  }
}
