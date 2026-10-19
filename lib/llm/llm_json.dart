import 'dart:convert';

/// Pulls the first JSON object/array out of a model reply, tolerating code
/// fences and chatter around it. Returns null when nothing parses.
Object? extractJson(String text) {
  var s = text.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  try {
    return jsonDecode(s);
  } on FormatException {
    // Try the outermost {...} or [...] span.
  }
  for (final (open, close) in const [('{', '}'), ('[', ']')]) {
    final a = s.indexOf(open), b = s.lastIndexOf(close);
    if (a >= 0 && b > a) {
      try {
        return jsonDecode(s.substring(a, b + 1));
      } on FormatException {
        continue;
      }
    }
  }
  return null;
}

/// `{"results": [...]}` or a bare list → list of maps.
List<Map<String, dynamic>> extractResults(String text) {
  final j = extractJson(text);
  final list = j is Map ? (j['results'] ?? j['items'] ?? j['data']) : j;
  if (list is! List) return const [];
  return [
    for (final e in list)
      if (e is Map) e.cast<String, dynamic>(),
  ];
}

/// Number or numeric string ("1,299.50", "₹ 250") → double.
double? asNumber(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  return null;
}

int? asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null));

String? asString(Object? v, {int max = 80}) {
  if (v is! String) return null;
  final s = v.trim();
  if (s.isEmpty || s.toLowerCase() == 'null' || s.toLowerCase() == 'none') return null;
  return s.length > max ? s.substring(0, max) : s;
}
