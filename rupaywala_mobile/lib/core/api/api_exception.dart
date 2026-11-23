/// A failure that is safe to show to the user.
///
/// The backend already returns human readable `detail` strings, so those are
/// surfaced verbatim. Transport level problems get a friendly message instead
/// of a socket exception, and the technical cause is kept separately for the
/// logs.
class ApiException implements Exception {
  /// Message intended for the user. Never contains a stack trace.
  final String message;

  /// HTTP status code, or null when the request never reached the server.
  final int? statusCode;

  /// Raw body / transport error, for debugging only.
  final String? debugDetail;

  /// True when the request never reached the server, which almost always
  /// means the base URL is wrong or the backend is not running.
  final bool isNetworkError;

  const ApiException(
    this.message, {
    this.statusCode,
    this.debugDetail,
    this.isNetworkError = false,
  });

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  /// True when the user simply needs to wait before trying again.
  bool get isRateLimited => statusCode == 429;

  /// True when the request needs a field the client did not send.
  bool get isValidation => statusCode == 422;

  @override
  String toString() => message;
}
