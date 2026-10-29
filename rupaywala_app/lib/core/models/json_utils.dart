/// Defensive JSON accessors.
///
/// The backend is well behaved, but a UI that throws on a null field turns a
/// cosmetic gap into a blank screen, so every model reads through these.
library;

import 'dart:convert';
import 'dart:typed_data';

class J {
  J._();

  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry('$k', v));
    return const {};
  }

  static List<Map<String, dynamic>> asMapList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(asMap).toList();
  }

  static String? str(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  static String text(dynamic value, [String fallback = '']) =>
      str(value) ?? fallback;

  static num? numeric(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  static double dbl(dynamic value, [double fallback = 0]) =>
      numeric(value)?.toDouble() ?? fallback;

  static int integer(dynamic value, [int fallback = 0]) =>
      numeric(value)?.round() ?? fallback;

  static int? intOrNull(dynamic value) {
    final parsed = numeric(value);
    return parsed?.round();
  }

  static bool flag(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
    }
    return fallback;
  }

  /// Reads a nested object only when it is actually present, so an absent
  /// relation becomes `null` instead of an object full of empty strings.
  static Map<String, dynamic>? object(dynamic value) {
    if (value is Map && value.isNotEmpty) return asMap(value);
    return null;
  }

  static List<String> stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map(str).whereType<String>().toList();
  }

  /// Parses `YYYY-MM-DD` as well as full ISO timestamps into a local
  /// [DateTime], returning null for anything unparseable.
  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    // Some deployments return timestamps with a trailing Z that DateTime
    // parses fine, but bare dates need to become local midnight.
    return DateTime.tryParse(text) ?? DateTime.tryParse('${text}T00:00:00');
  }

  /// Decodes a base64 payload (the UPI QR code comes back this way).
  static Uint8List? base64Bytes(dynamic value) {
    final text = str(value);
    if (text == null || text.isEmpty) return null;
    try {
      return base64Decode(text);
    } on FormatException {
      return null;
    }
  }
}
