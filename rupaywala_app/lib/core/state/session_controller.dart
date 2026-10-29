import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/api_exception.dart';
import '../models/auth_models.dart';

enum SessionStatus { restoring, signedOut, signedIn }

/// Owns the signed-in user and the routing decision that follows from it.
///
/// The app previously kept the token in a static field and pushed role
/// dashboards by hand from the login screen, which meant a cold start always
/// landed on the phone screen. Restoring the session here fixes that and keeps
/// role routing in exactly one place.
class SessionController extends ChangeNotifier {
  SessionController(this._api) {
    _api.client.onUnauthorized = _handleUnauthorized;
  }

  final Api _api;

  SessionStatus _status = SessionStatus.restoring;
  AppSession? _session;
  String? _error;

  SessionStatus get status => _status;
  AppSession? get session => _session;
  String? get error => _error;
  AppRole? get role => _session?.role;
  bool get isSignedIn => _status == SessionStatus.signedIn && _session != null;

  /// Called once at startup. A stored token is validated against `/auth/me`;
  /// anything that fails simply drops the user back to the login screen.
  Future<void> restore() async {
    _set(SessionStatus.restoring, session: null, error: null);

    final token = await _api.tokens.read();
    if (token == null || token.isEmpty) {
      _set(SessionStatus.signedOut, session: null, error: null);
      return;
    }

    try {
      final session = await _api.auth.me();
      _set(SessionStatus.signedIn, session: session, error: null);
    } on ApiException catch (e) {
      if (e.isNetworkError) {
        // The server being unreachable is not a reason to delete the token —
        // keep it so the user can retry without signing in again.
        _set(
          SessionStatus.signedOut,
          session: null,
          error: e.message,
        );
        return;
      }
      await _api.tokens.clear();
      _set(SessionStatus.signedOut, session: null, error: null);
    }
  }

  Future<void> login(
      {required String identifier, required String password}) async {
    _set(SessionStatus.restoring, session: null, error: null);
    try {
      final result =
          await _api.auth.login(identifier: identifier, password: password);
      await _adopt(result);
    } on ApiException catch (e, stack) {
      _fail(e, stack);
    }
  }

  Future<void> register({
    required String phoneNumber,
    required String username,
    required String password,
  }) async {
    _set(SessionStatus.restoring, session: null, error: null);
    try {
      final result = await _api.auth.register(
        phoneNumber: phoneNumber,
        username: username,
        password: password,
      );
      await _adopt(result);
    } on ApiException catch (e, stack) {
      _fail(e, stack);
    }
  }

  Future<void> loginWithResult(AuthResult result) async {
    _set(SessionStatus.restoring, session: null, error: null);
    try {
      await _adopt(result);
    } on ApiException catch (e, stack) {
      _fail(e, stack);
    }
  }

  Future<void> logout() async {
    await _api.tokens.clear();
    _set(SessionStatus.signedOut, session: null, error: null);
  }

  Future<String> changeUsername({
    required String username,
    String? currentPassword,
  }) async {
    final updatedUsername = await _api.auth.changeUsername(
      username: username,
      currentPassword: currentPassword,
    );
    final currentSession = _session;
    if (_status == SessionStatus.signedIn && currentSession != null) {
      _set(
        SessionStatus.signedIn,
        session: currentSession.copyWith(username: updatedUsername),
        error: null,
      );
    }
    return updatedUsername;
  }

  /// Re-reads `/auth/me` so visit counts and profile flags stay fresh after
  /// a payment is approved or a visit is consumed.
  Future<void> refresh() async {
    if (!isSignedIn) return;
    try {
      final session = await _api.auth.me();
      _set(SessionStatus.signedIn, session: session, error: null);
    } on ApiException {
      /* keep the previous session; individual screens surface their own errors */
    }
  }

  Future<void> _adopt(AuthResult result) async {
    await _api.tokens.writeToken(
      result.accessToken,
      role: result.role.wireName,
      displayName: result.fullName,
    );
    try {
      final session = await _api.auth.me();
      _set(SessionStatus.signedIn, session: session, error: null);
    } on ApiException {
      // The token is valid but the profile call is unavailable; fall back to
      // what login already told us so the user is not stuck on the loader.
      _set(
        SessionStatus.signedIn,
        session: AppSession(
          userId: result.userId,
          role: result.role,
          username: result.username,
          fullName: result.fullName,
          phoneNumber: result.phoneNumber,
          profileCompleted: result.profileCompleted,
          hasPassword: result.hasPassword,
        ),
        error: null,
      );
    }
  }

  void _handleUnauthorized() {
    if (_status == SessionStatus.signedOut) return;
    _api.tokens.clear();
    _set(SessionStatus.signedOut,
        session: null,
        error: 'Your session has expired. Please sign in again.');
  }

  void _fail(ApiException e, StackTrace stack) {
    debugPrint('Session error: $e (${e.debugDetail})');
    _set(SessionStatus.signedOut, session: null, error: e.message);
  }

  void _set(SessionStatus status, {AppSession? session, String? error}) {
    _status = status;
    _session = session;
    _error = error;
    notifyListeners();
  }
}
