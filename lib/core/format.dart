import 'package:intl/intl.dart';

final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

/// ₹1,23,456 — drops paise when they're zero.
String money(int minor, {bool forceDecimals = false}) =>
    (forceDecimals || minor % 100 != 0 ? _inr2 : _inr0).format(minor / 100);

/// ₹1.2L, ₹45K — for chart axes and tight spaces.
String moneyCompact(int minor) => minor.abs() < 100000 ? _inr0.format(minor / 100) : _compact.format(minor / 100);

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
