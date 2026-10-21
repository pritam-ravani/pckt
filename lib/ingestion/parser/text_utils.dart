String normalizeSpace(String s) => s.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ').replaceAll(RegExp(r'\n\s*'), '\n').trim();

/// "1,23,456.7" → 12345670 (paise). [digits] is the currency's decimal
/// places: 0 for JPY ("1,200" → 1200), 3 for KWD ("12.5" → 12500).
int? parseMinor(String s, {int digits = 2}) {
  final cleaned = s.replaceAll(',', '');
  final v = double.tryParse(cleaned);
  if (v == null) return null;
  var per = 1;
  for (var i = 0; i < digits; i++) {
    per *= 10;
  }
  return (v * per).round();
}

String titleCase(String s) => s
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => _keepUpper(w.toUpperCase()) ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

bool _keepUpper(String w) => const {'ATM', 'UPI', 'EMI', 'KFC', 'PVR', 'IRCTC', 'BBPS', 'LIC', 'HP', 'BP'}.contains(w);

final _merchantJunk = RegExp(
  r'\b(pvt\.?|private|ltd\.?|limited|llp|inc\.?|(?<!\bof )india|technologies|tech|services|payments?|retail|'
  r'online|com|www|vpa|upi|mr\.?|mrs\.?|ms\.?)\b',
  caseSensitive: false,
);

const _months =
    r'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|'
    r'oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';
const _weekdays =
    r'mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?';

/// Dates and times as banks print them: "Sep 06", "06-Sep-26", "6th Sept, 2026",
/// "12Oct26", "06/09/26", "2026-10-12", "20:11:07", "08:01 PM".
final _dateLike = RegExp(
  r'\b\d{1,2}(?:st|nd|rd|th)?[-/ .,]*(?:' +
      _months +
      r')\b\.?(?:[-/ ,.]*\d{2,4}\b)?' +
      r'|\b(?:' +
      _months +
      r')\b\.?[-/ ]*\d{1,2}(?:st|nd|rd|th)?\b(?:,?[-/ ]*\d{2,4}\b)?' +
      r'|\b\d{1,2}(?:' +
      _months +
      r')\d{2,4}\b' +
      r'|\b\d{1,4}[-/.]\d{1,2}(?:[-/.]\d{2,4})?\b' +
      r'|\b\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]\.?m\b\.?)?',
  caseSensitive: false,
);

/// A candidate that is nothing but calendar words / filler once dates are gone.
final _calendarOnly = RegExp(
  r'^(?:(?:' +
      _months +
      r'|' +
      _weekdays +
      r'|on|dated?|date|txn|transaction|the|of|for|refund(?:ed)?|reversal|reversed|am|pm|ist|hrs)\b[\s.,\-]*)+$',
  caseSensitive: false,
);

/// True when [s] is a date, time or month/weekday name rather than a name.
bool isDateLike(String s) {
  final stripped = s.replaceAll(_dateLike, ' ').replaceAll(RegExp(r'[\s.,:/\-]+'), ' ').trim();
  return stripped.isEmpty || _calendarOnly.hasMatch(stripped);
}

/// Turns raw counterparty strings into a short display name.
/// Returns null for things that are clearly not names (numbers, ids, dates).
String? cleanMerchant(String raw) {
  var s = raw.trim();
  if (s.contains('@')) return merchantFromVpa(s.split(RegExp(r'\s')).firstWhere((w) => w.contains('@')));
  if (isDateLike(s)) return null;
  s = s
      .replaceAll(_dateLike, ' ')
      .replaceAll(RegExp(r'[^A-Za-z0-9&\x27 .\-]'), ' ')
      .replaceAll(_merchantJunk, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.\-]+|[\s.\-]+$'), '')
      .replaceAll(RegExp(r'\s+(?:on|dated?|dt)$', caseSensitive: false), '')
      .trim();
  if (s.length < 2) return null;
  if (RegExp(r'^[\dXx*\s]+$').hasMatch(s)) return null;
  if (s.length > 32) s = s.substring(0, 32).trim();
  return titleCase(s);
}

/// "swiggy.stores@axb" → "Swiggy Stores"; "9876543210@ybl" → null.
String? merchantFromVpa(String vpa) {
  final local = vpa.split('@').first;
  final words = local
      .replaceAll(RegExp(r'[._\-]+'), ' ')
      .replaceAll(RegExp(r'\d+'), ' ')
      .replaceAll(RegExp(r'\b(paytmqr|bharatpe|gpay|phonepe|mab|q|qr|merchant|pay|upi)\b', caseSensitive: false), ' ')
      .trim();
  if (words.length < 3) return null;
  return titleCase(words);
}

/// Legal / payment-gateway names banks print → the brand a receipt uses.
const _brandAliases = <String, String>{
  'bundl': 'swiggy',
  'instamart': 'swiggy',
  'eternal': 'zomato',
  'grofers': 'blinkit',
  'kiranakart': 'zepto',
  'one97': 'paytm',
  'roppen': 'rapido',
  'bigtree': 'bookmyshow',
  'olacabs': 'ola',
  'amzn': 'amazon',
};

/// Lower-case alnum tokens, used for fuzzy merchant comparison.
Set<String> merchantTokens(String? s) {
  if (s == null) return <String>{};
  final tokens = s
      .toLowerCase()
      .replaceAll(RegExp(r'@.*$'), '')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 3 && !RegExp(r'^\d+$').hasMatch(t))
      .toSet();
  return {...tokens, for (final t in tokens) ?_brandAliases[t]};
}
