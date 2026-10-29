import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT and the cached role across app launches.
///
/// On Android `flutter_secure_storage` is backed by EncryptedSharedPreferences
/// and on the web falls back to a namespaced localStorage entry. Both work for
/// a bearer token, but a failed write must never block the login flow, so
/// every call degrades to in-memory only.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'rupaywala.token';
  static const _roleKey = 'rupaywala.role';
  static const _nameKey = 'rupaywala.name';

  String? _cachedToken;
  String? _cachedRole;

  String? get cachedToken => _cachedToken;
  String? get cachedRole => _cachedRole;

  Future<String?> read() async {
    if (_cachedToken != null) return _cachedToken;
    try {
      _cachedToken = await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
    return _cachedToken;
  }

  Future<void> writeToken(String token,
      {String? role, String? displayName}) async {
    _cachedToken = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
      if (role != null) {
        _cachedRole = role;
        await _storage.write(key: _roleKey, value: role);
      }
      if (displayName != null && displayName.trim().isNotEmpty) {
        await _storage.write(key: _nameKey, value: displayName.trim());
      }
    } catch (_) {
      /* in-memory token still works for this session */
    }
  }

  Future<String?> readRole() async {
    if (_cachedRole != null) return _cachedRole;
    try {
      _cachedRole = await _storage.read(key: _roleKey);
    } catch (_) {
      return null;
    }
    return _cachedRole;
  }

  Future<String?> readDisplayName() async {
    try {
      return await _storage.read(key: _nameKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    _cachedToken = null;
    _cachedRole = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _roleKey);
      await _storage.delete(key: _nameKey);
    } catch (_) {
      /* nothing else to do */
    }
  }
}
