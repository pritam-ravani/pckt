import 'dart:convert';

/// How much of a tool result a small-context model gets. Every character
/// sent to an on-device model is prefilled on the phone (roughly 3 chars per
/// token), so a 25-row result can cost more time than the answer itself.
class ToolResultBudget {
  const ToolResultBudget({required this.maxRows, required this.maxChars});

  /// Sized so a result stays around a quarter of the context window.
  factory ToolResultBudget.forContext(int contextTokens) => switch (contextTokens) {
    <= 2048 => const ToolResultBudget(maxRows: 6, maxChars: 1400),
    <= 4096 => const ToolResultBudget(maxRows: 10, maxChars: 2800),
    _ => const ToolResultBudget(maxRows: 25, maxChars: 8000),
  };

  final int maxRows;
  final int maxChars;
}

/// Compact JSON of [json] for a small model:
///
/// * a raw number is dropped when its `*_formatted` twin is present (the
///   prompt tells the model to quote those),
/// * nulls are dropped and whole doubles written as ints,
/// * lists of rows keep the first [ToolResultBudget.maxRows] and say how many
///   were left out (`<key>_omitted`); `returned` is kept in sync,
/// * if it is still over [ToolResultBudget.maxChars], the longest list is
///   halved until it fits (totals always survive — they are not in lists).
String compactToolJson(Map<String, dynamic> json, ToolResultBudget budget) {
  var rows = budget.maxRows;
  var out = _encode(json, rows);
  while (out.length > budget.maxChars && rows > 1) {
    rows = rows ~/ 2;
    out = _encode(json, rows);
  }
  return out;
}

String _encode(Map<String, dynamic> json, int maxRows) => jsonEncode(_compactMap(json, maxRows));

Map<String, dynamic> _compactMap(Map<String, dynamic> m, int maxRows) {
  final out = <String, dynamic>{};
  for (final e in m.entries) {
    final v = e.value;
    if (v == null || (e.key == 'returned' && out.containsKey('returned'))) continue;
    if (v is num && m.containsKey('${e.key}_formatted')) continue;
    if (v is List && v.length > maxRows && v.every((x) => x is Map)) {
      out[e.key] = [for (final x in v.take(maxRows)) _compact(x, maxRows)];
      out['${e.key}_omitted'] = v.length - maxRows + (m['${e.key}_omitted'] as int? ?? 0);
      if (e.key == 'transactions' && m.containsKey('returned')) out['returned'] = maxRows;
      continue;
    }
    out[e.key] = _compact(v, maxRows);
  }
  return out;
}

Object? _compact(Object? v, int maxRows) => switch (v) {
  Map<String, dynamic>() => _compactMap(v, maxRows),
  Map() => _compactMap(v.cast<String, dynamic>(), maxRows),
  List() => [for (final x in v) _compact(x, maxRows)],
  double() when v.isFinite && v == v.roundToDouble() && v.abs() < 1e15 => v.toInt(),
  _ => v,
};
