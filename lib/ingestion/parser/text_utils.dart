String normalizeSpace(String s) => s.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ').replaceAll(RegExp(r'\n\s*'), '\n').trim();

/// "1,23,456.7" → 12345670 (paise).
int? parseMinor(String s) {
  final cleaned = s.replaceAll(',', '');
  final v = double.tryParse(cleaned);
  if (v == null) return null;
  return (v * 100).round();
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

/// Turns raw counterparty strings into a short display name.
/// Returns null for things that are clearly not names (numbers, ids).
String? cleanMerchant(String raw) {
  var s = raw.trim();
  if (s.contains('@')) return merchantFromVpa(s.split(RegExp(r'\s')).firstWhere((w) => w.contains('@')));
  s = s
      .replaceAll(RegExp(r'[^A-Za-z0-9&\x27 .\-]'), ' ')
      .replaceAll(_merchantJunk, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.\-]+|[\s.\-]+$'), '')
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
