/// Currency markers as alerts print them, for lower-cased text. The rupee
/// forms come first and match exactly as the original INR-only rules did;
/// the rest need a non-letter before them so words like "cadbury" or
/// "thanks" can't pass for codes. Turkish "TRY" collides with the English
/// word, so it is only read in upper case (see [normalizeCurrencyText]).
const currencyTokenPattern =
    r'(rs\.?|inr|₹|₨|(?<![a-z])(?:us|nz|s|a|c|r)\$|\$|€|£|¥|₩|₱|₫|฿|₦|₺|৳|'
    r'(?<![a-z])(?:usd|eur|gbp|aed|sar|qar|kwd|omr|bhd|sgd|myr|cad|aud|nzd|bdt|pkr|lkr|npr|idr|php|vnd|thb|ngn|'
    r'kes|zar|brl|mxn|jpy|krw)(?![a-z])|(?<![a-z])(?:rm|rp\.?)(?=\s?\d)|(?<![a-z])ksh\.?)';

/// An amount as printed: "1,23,456.78", "12.500" (three decimals for KWD).
const amountPattern = r'([0-9][0-9,]*(?:\.[0-9]{1,3})?)';

/// ISO codes that may follow the number ("12.50 USD").
final currencySuffix = RegExp(
  r'^\s?(inr|usd|eur|gbp|aed|sar|qar|kwd|omr|bhd|sgd|myr|cad|aud|nzd|bdt|pkr|lkr|npr|idr|php|vnd|thb|ngn|kes|zar|'
  r'brl|mxn|jpy|krw)(?![a-z])',
);

/// Rewrites markers that only mean a currency in their printed case
/// ("TRY 250.00") into a symbol the lower-case rules can read.
String normalizeCurrencyText(String text) => text.replaceAll(RegExp(r'(?<![A-Za-z])TRY(?=\s?\d)'), '₺');

const _rupees = {'INR', 'PKR', 'LKR', 'NPR'};
const _dollars = {'USD', 'CAD', 'AUD', 'NZD', 'SGD', 'MXN'};

const _signs = {
  '₹': 'INR',
  'inr': 'INR',
  'us\$': 'USD',
  'nz\$': 'NZD',
  's\$': 'SGD',
  'a\$': 'AUD',
  'c\$': 'CAD',
  'r\$': 'BRL',
  '€': 'EUR',
  '£': 'GBP',
  '¥': 'JPY',
  '₩': 'KRW',
  '₱': 'PHP',
  '₫': 'VND',
  '฿': 'THB',
  '₦': 'NGN',
  '₺': 'TRY',
  '৳': 'BDT',
  'rm': 'MYR',
  'rp': 'IDR',
  'ksh': 'KES',
};

/// ISO code for a matched [token]. "Rs" and "$" are shared: they mean the
/// [home] currency when it is a rupee / dollar, else INR / USD.
String currencyOfToken(String token, {required String home}) {
  final t = token.trim().replaceAll(RegExp(r'\.$'), '');
  if (t == 'rs' || t == '₨') return _rupees.contains(home) ? home : 'INR';
  if (t == r'$') return _dollars.contains(home) ? home : 'USD';
  return _signs[t] ?? t.toUpperCase();
}
