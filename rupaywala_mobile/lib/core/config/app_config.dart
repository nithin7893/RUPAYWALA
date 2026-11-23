import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Centralised runtime configuration for the client.
///
/// The API host is the single most common reason a build cannot reach the
/// backend, so it is resolved here once and made overridable at build time:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
class AppConfig {
  AppConfig._();

  /// Overridable at build time with `--dart-define=API_BASE_URL=...`.
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// `true` when the base URL was injected at build time.
  static bool get hasOverride => _override.trim().isNotEmpty;

  /// The API root, always without a trailing slash.
  static String get baseUrl {
    final raw = _resolveBaseUrl().trim();
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static String _resolveBaseUrl() {
    if (hasOverride) return _override;

    // The Android emulator runs its own loopback interface, so `127.0.0.1`
    // points at the emulated device instead of the developer machine. The
    // emulator maps the host loopback to 10.0.2.2.
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';

    // Web, desktop, iOS simulator and physical devices on the same machine.
    return 'http://127.0.0.1:8000';
  }

  /// Human readable host, used in error screens so the user can tell whether
  /// the app is pointed at the right machine.
  static String get baseUrlHost {
    final uri = Uri.tryParse(baseUrl);
    return uri == null ? baseUrl : '${uri.host}:${uri.port}';
  }

  /// How long a QR / UPI intent stays valid, mirrored from the backend.
  static const int qrExpiryMinutes = 10;

  /// Delay before the "resend code" button becomes available.
  static const int otpCooldownSeconds = 45;

  static const Duration requestTimeout = Duration(seconds: 20);

  /// Polling cadence used while waiting for an admin to verify a payment.
  static const Duration paymentPollInterval = Duration(seconds: 6);
}
