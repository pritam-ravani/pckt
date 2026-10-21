import 'package:intl/intl.dart';

import 'currency.dart';

export 'currency.dart';

/// ₹1,23,456 · $1,234.50 · ¥1,200 — [minor] units of [currency] (the home
/// currency by default). Drops the fraction when it's zero.
String money(int minor, {String? currency, bool forceDecimals = false}) =>
    formatMoney(minor, currency: currency, forceDecimals: forceDecimals);

/// ₹1.2L, $45K — for chart axes and tight spaces.
String moneyCompact(int minor, {String? currency}) => formatMoneyCompact(minor, currency: currency);

String monthLabel(DateTime m) => DateFormat('MMMM yyyy').format(m);
String monthShort(DateTime m) => DateFormat('MMM').format(m);
String timeLabel(DateTime d) => DateFormat('h:mm a').format(d);
String dateTimeLabel(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEEE').format(d);
  return DateFormat(d.year == now.year ? 'EEE, d MMM' : 'd MMM yyyy').format(d);
}

String relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return DateFormat('d MMM, h:mm a').format(d);
}

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime nextMonth(DateTime d) => DateTime(d.year, d.month + 1);
