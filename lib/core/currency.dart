import 'dart:math' as math;

import 'package:intl/intl.dart';

/// A currency Pckt can track. Symbols and decimal digits come from `intl`
/// (CLDR data); only the English name is ours.
class Currency {
  const Currency(this.code, this.name);

  /// ISO 4217 code, e.g. `INR`.
  final String code;
  final String name;

  /// Digits after the decimal point: 2 for most, 0 for JPY/KRW/VND/IDR,
  /// 3 for KWD/BHD/OMR. Amounts are stored in these minor units.
  int get digits => currencyDigits(code);

  @override
  String toString() => '$name ($code)';
}

/// Supported currencies, most likely users first: India, the Gulf and the
/// Indian diaspora, neighbouring markets, then large Android markets.
const supportedCurrencies = <Currency>[
  Currency('INR', 'Indian Rupee'),
  Currency('AED', 'UAE Dirham'),
  Currency('SAR', 'Saudi Riyal'),
  Currency('QAR', 'Qatari Riyal'),
  Currency('KWD', 'Kuwaiti Dinar'),
  Currency('OMR', 'Omani Rial'),
  Currency('BHD', 'Bahraini Dinar'),
  Currency('SGD', 'Singapore Dollar'),
  Currency('MYR', 'Malaysian Ringgit'),
  Currency('USD', 'US Dollar'),
  Currency('GBP', 'British Pound'),
  Currency('CAD', 'Canadian Dollar'),
  Currency('AUD', 'Australian Dollar'),
  Currency('NZD', 'New Zealand Dollar'),
  Currency('EUR', 'Euro'),
  Currency('BDT', 'Bangladeshi Taka'),
  Currency('PKR', 'Pakistani Rupee'),
  Currency('LKR', 'Sri Lankan Rupee'),
  Currency('NPR', 'Nepalese Rupee'),
  Currency('IDR', 'Indonesian Rupiah'),
  Currency('PHP', 'Philippine Peso'),
  Currency('VND', 'Vietnamese Dong'),
  Currency('THB', 'Thai Baht'),
  Currency('NGN', 'Nigerian Naira'),
  Currency('KES', 'Kenyan Shilling'),
  Currency('ZAR', 'South African Rand'),
  Currency('BRL', 'Brazilian Real'),
  Currency('MXN', 'Mexican Peso'),
  Currency('TRY', 'Turkish Lira'),
  Currency('JPY', 'Japanese Yen'),
  Currency('KRW', 'South Korean Won'),
];

final _byCode = {for (final c in supportedCurrencies) c.code: c};

Currency? currencyFor(String code) => _byCode[code.toUpperCase()];

bool isSupportedCurrency(String code) => _byCode.containsKey(code.toUpperCase());

/// The user's home currency: what totals, budgets and the assistant use.
/// Held here (like `Intl.defaultLocale`) so formatting helpers need no
/// context; `homeCurrencyProvider` keeps it in sync with the setting.
abstract final class Currencies {
  static String home = 'INR';
}

final _digits = <String, int>{};
final _symbols = <String, String>{};

int currencyDigits(String code) =>
    _digits[code] ??= NumberFormat.simpleCurrency(locale: 'en', name: code).decimalDigits ?? 2;

/// 10^digits: minor units per major unit (100 for INR, 1 for JPY).
int minorPerUnit(String code) => math.pow(10, currencyDigits(code)).toInt();

/// The CLDR "simple" symbol: ₹, $, €, Rs, RM, dh, Riyal…
String _simpleSymbol(String code) =>
    _symbols[code] ??= NumberFormat.simpleCurrency(locale: 'en', name: code).currencySymbol;

/// What to print before an amount, including any trailing space.
///
/// * A sign shared by several supported currencies ($, Rs) is only used for
///   the [home] currency; others show their code ("USD 12.50" for an INR
///   user, "$12.50" for a USD user).
/// * Word-like symbols ("dh", "Riyal", "din") read badly glued to digits,
///   so those currencies show their code too ("AED 120.50").
/// * Short letter symbols are kept with a space ("Rs 1,250", "RM 18.00").
String currencyPrefix(String code, {String? home}) {
  home ??= Currencies.home;
  final s = _simpleSymbol(code);
  final letters = RegExp(r'^[A-Za-z]+$').hasMatch(s);
  if (letters && (s.length > 2 || s[0] == s[0].toLowerCase())) return '$code ';
  final shared = supportedCurrencies.any((c) => c.code != code && _simpleSymbol(c.code) == s);
  if (shared && code != home) return '$code ';
  return letters ? '$s ' : s;
}

/// Short symbol for compact UI (input prefixes, chips): "₹", "$", "AED".
String currencySymbol(String code, {String? home}) => currencyPrefix(code, home: home).trim();

/// Indian lakh/crore grouping only for INR; everything else groups by
/// thousands. Digits are always ASCII.
String _locale(String code) => code == 'INR' ? 'en_IN' : 'en';

final _formats = <String, NumberFormat>{};

NumberFormat _format(String code, String home, int digits) => _formats['$code/$home/$digits'] ??= NumberFormat.currency(
  locale: _locale(code),
  name: code,
  symbol: currencyPrefix(code, home: home),
  decimalDigits: digits,
);

NumberFormat _compactFormat(String code, String home) =>
    _formats['$code/$home/compact'] ??= NumberFormat.compactCurrency(
      locale: _locale(code),
      name: code,
      symbol: currencyPrefix(code, home: home),
      decimalDigits: 1,
    );

/// Formats [minor] units of [currency] (home currency by default):
/// ₹1,23,456 · $1,234.50 · ¥1,200 · KWD 12.500. Drops the fraction when it
/// is zero unless [forceDecimals].
String formatMoney(int minor, {String? currency, bool forceDecimals = false}) {
  final code = currency ?? Currencies.home;
  final digits = currencyDigits(code);
  final per = minorPerUnit(code);
  final whole = minor % per == 0;
  return _format(code, Currencies.home, forceDecimals || !whole ? digits : 0).format(minor / per);
}

/// ₹1.2L, $45K — for chart axes and tight spaces. Below a thousand units it
/// is the whole-unit amount.
String formatMoneyCompact(int minor, {String? currency}) {
  final code = currency ?? Currencies.home;
  final value = minor / minorPerUnit(code);
  return value.abs() < 1000
      ? _format(code, Currencies.home, 0).format(value)
      : _compactFormat(code, Currencies.home).format(value);
}

/// Plain number in major units with the currency's digits, no grouping or
/// symbol — for CSV and machine-readable output ("1250.50", "1200").
String plainAmount(int minor, String currency) =>
    (minor / minorPerUnit(currency)).toStringAsFixed(currencyDigits(currency));

/// Minor units → major units as a double, for JSON tool output.
double toMajor(int minor, String currency) => minor / minorPerUnit(currency);

/// Major units → minor units, rounded.
int toMinor(num major, String currency) => (major * minorPerUnit(currency)).round();

/// Currency for a device locale such as `en_AE` or `ar-SA`: the country's
/// currency when supported, USD for other countries, INR when the locale
/// names no country (the app's original market).
String defaultCurrencyForLocale(String? locale) {
  final parts = (locale ?? '').split(RegExp(r'[-_]'));
  final country = parts.skip(1).firstWhere((p) => RegExp(r'^[A-Za-z]{2}$').hasMatch(p), orElse: () => '').toUpperCase();
  if (country.isEmpty) return 'INR';
  return _countryCurrency[country] ?? (_euro.contains(country) ? 'EUR' : 'USD');
}

const _countryCurrency = {
  'IN': 'INR', 'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'KW': 'KWD', 'OM': 'OMR', 'BH': 'BHD', //
  'SG': 'SGD', 'MY': 'MYR', 'US': 'USD', 'GB': 'GBP', 'CA': 'CAD', 'AU': 'AUD', 'NZ': 'NZD', //
  'BD': 'BDT', 'PK': 'PKR', 'LK': 'LKR', 'NP': 'NPR', 'ID': 'IDR', 'PH': 'PHP', 'VN': 'VND', //
  'TH': 'THB', 'NG': 'NGN', 'KE': 'KES', 'ZA': 'ZAR', 'BR': 'BRL', 'MX': 'MXN', 'TR': 'TRY', //
  'JP': 'JPY', 'KR': 'KRW',
};

const _euro = {
  'AT', 'BE', 'HR', 'CY', 'EE', 'FI', 'FR', 'DE', 'GR', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PT', //
  'SK', 'SI', 'ES',
};
