/// Presentation helpers shared by every screen.
///
/// `intl` is not a dependency, so date and number formatting live here in one
/// place instead of being re-implemented per screen.
class Fmt {
  Fmt._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `1234.5` -> `Rs 1,235`. Whole amounts drop the decimals, which is what
  /// customers expect to see next to a rupee sign.
  static String money(num? amount,
      {bool decimals = false, String symbol = 'Rs '}) {
    if (amount == null) return '${symbol}0';
    final text = decimals
        ? amount.toDouble().toStringAsFixed(2)
        : amount.toDouble().round().toString();
    return '$symbol${_group(text)}';
  }

  /// `12.3456` -> `12.3 km`
  static String km(num? value, {int fractionDigits = 1}) {
    if (value == null) return '0 km';
    return '${value.toDouble().toStringAsFixed(fractionDigits)} km';
  }

  /// `125` -> `2 hr 5 min`
  static String duration(num? minutes) {
    if (minutes == null) return '-';
    final total = minutes.round();
    if (total < 1) return 'Less than a minute';
    if (total < 60) return '$total min';
    final hours = total ~/ 60;
    final mins = total % 60;
    if (mins == 0) return '$hours hr';
    return '$hours hr $mins min';
  }

  /// Accepts `YYYY-MM-DD` as well as full ISO timestamps.
  static DateTime? parse(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return DateTime.tryParse(text);
  }

  /// `2026-12-25` -> `25 Dec 2026`
  static String date(Object? value) {
    final parsed = parse(value);
    if (parsed == null) return '-';
    return dateFrom(parsed);
  }

  static String dateFrom(DateTime value) {
    return '${value.day} ${_months[value.month - 1]} ${value.year}';
  }

  /// `2026-12-25` -> `25 Dec`
  static String shortDate(Object? value) {
    final parsed = parse(value);
    if (parsed == null) return '-';
    return '${parsed.day} ${_months[parsed.month - 1]}';
  }

  /// `2026-09-15T18:42:00` -> `15 Sep, 7:42 pm`
  static String dateTime(Object? value) {
    final parsed = parse(value);
    if (parsed == null) return '-';
    final hour24 = parsed.hour;
    final suffix = hour24 >= 12 ? 'pm' : 'am';
    var hour = hour24 % 12;
    if (hour == 0) hour = 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '${parsed.day} ${_months[parsed.month - 1]}, $hour:$minute $suffix';
  }

  /// `1234` -> `1,234`
  static String count(num? value) {
    if (value == null) return '0';
    return _group(value.round().toString());
  }

  /// "2 minutes ago" style text used in request and notification lists.
  static String relative(Object? value) {
    final parsed = parse(value);
    if (parsed == null) return '-';
    final delta = DateTime.now().difference(parsed.toLocal());
    if (delta.isNegative) return 'just now';
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours} hr ago';
    if (delta.inDays < 30) {
      return '${delta.inDays} day${delta.inDays == 1 ? '' : 's'} ago';
    }
    return dateFrom(parsed.toLocal());
  }

  /// Countdown used on the payment screen, e.g. `4m 12s`.
  static String countdown(DateTime until) {
    final delta = until.difference(DateTime.now());
    if (delta.isNegative) return 'Expired';
    if (delta.inHours > 0) return '${delta.inHours}h ${delta.inMinutes % 60}m';
    return '${delta.inMinutes}m ${delta.inSeconds % 60}s';
  }

  static String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Up to two initials for an avatar, e.g. "Ravi Kumar" -> "RK".
  static String initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final only = parts.first;
      return only.substring(0, only.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String _group(String digits) {
    final negative = digits.startsWith('-');
    final bare = negative ? digits.substring(1) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < bare.length; i++) {
      if (i > 0 && (bare.length - i) % 3 == 0) buffer.write(',');
      buffer.write(bare[i]);
    }
    return negative ? '-$buffer' : buffer.toString();
  }
}
