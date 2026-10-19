/// Turns email bodies into the compact plain text the parsers read.
library;

const maxEmailBodyChars = 4000;

final _comment = RegExp(r'<!--.*?-->', dotAll: true);
final _dropBlocks = RegExp(
  r'<(head|script|style|title|noscript|template)\b[^>]*>.*?</\1\s*>',
  caseSensitive: false,
  dotAll: true,
);
final _lineBreakTags = RegExp(
  r'<\s*(br|hr)\b[^>]*>|<\s*/\s*(p|div|tr|li|h[1-6]|table|tbody|thead|ul|ol|section|article|header|footer|blockquote|center)\s*>|<\s*(p|div|tr|li|table|h[1-6])\b[^>]*>',
  caseSensitive: false,
);
final _cellTags = RegExp(r'<\s*/\s*(td|th)\s*>', caseSensitive: false);
final _anyTag = RegExp(r'<[^>]+>');
final _entity = RegExp(r'&(#x[0-9a-f]+|#\d+|[a-z]+);', caseSensitive: false);

const _named = <String, String>{
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'rsquo': "'",
  'lsquo': "'",
  'rdquo': '"',
  'ldquo': '"',
  'ndash': '-',
  'mdash': '-',
  'bull': '•',
  'middot': '·',
  'hellip': '...',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'zwnj': '',
  'zwj': '',
  'shy': '',
  'rupee': '₹',
  'inr': '₹',
};

String decodeEntities(String s) => s.replaceAllMapped(_entity, (m) {
  final e = m.group(1)!;
  if (e.startsWith('#')) {
    final hex = e[1] == 'x' || e[1] == 'X';
    final code = int.tryParse(e.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
    if (code == null || code <= 0 || code > 0x10FFFF) return '';
    // Zero-width / soft hyphen characters only add noise.
    if (code == 0xAD || (code >= 0x200B && code <= 0x200D) || code == 0xFEFF || code == 0x34F) return '';
    return code == 0xA0 ? ' ' : String.fromCharCode(code);
  }
  return _named[e.toLowerCase()] ?? m.group(0)!;
});

/// Minimal, dependency-free HTML → text: drops head/scripts/styles, keeps
/// block structure as line breaks and table cells on one line.
String htmlToText(String html) {
  var s = html
      .replaceAll(_comment, ' ')
      .replaceAll(_dropBlocks, ' ')
      .replaceAll(_lineBreakTags, '\n')
      .replaceAll(_cellTags, ' ')
      .replaceAll(_anyTag, ' ');
  s = decodeEntities(s);
  return collapseLines(s);
}

/// Collapses runs of spaces, trims lines and removes blank ones.
String collapseLines(String s) => s
    .replaceAll(RegExp(r'[ ​-‍﻿͏­]'), ' ')
    .split(RegExp(r'\r?\n|\r'))
    .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
    .where((l) => l.isNotEmpty)
    .join('\n');

/// Lines like "Never share your OTP / PIN" — present in nearly every bank
/// email and enough to make a payment alert look like an OTP message.
final _safetyLine = RegExp(
  r"(never|do not|don't|not to|will not|won't)\b.{0,80}\b(share|disclose|ask|call|reveal|request)\b|"
  r'\b(share|disclose)\b.{0,40}\b(otp|pin|password|cvv)\b.{0,40}\b(with anyone|to anyone)\b|'
  r'beware of (fraud|phishing)|report (it|fraud|unauthori[sz]ed)',
  caseSensitive: false,
);

/// Removes "never share your OTP"-style warning sentences.
String removeSafetyWarnings(String text) => [
  for (final line in text.split('\n'))
    if (!_safetyLine.hasMatch(line))
      line
    else
      line.split(RegExp(r'(?<=[.!?])\s+')).where((s) => !_safetyLine.hasMatch(s)).join(' ').trim(),
].where((l) => l.isNotEmpty).join('\n');

/// Boilerplate that typically starts a footer.
final _footerStart = RegExp(
  r'^(disclaimer|this (e-?mail|message|communication) (and any .{0,30})?(is|was|has been) (confidential|intended|sent|generated|auto)|'
  r'this is a (system|computer|auto(matically)?)[- ]generated|please do not reply|do not reply|'
  r'(to )?unsubscribe|you are receiving this|you received this|privacy policy|terms (and|&) conditions|'
  r'©|copyright|\(c\) \d{4}|registered office|corporate office|cin[: ]|follow us|download (the|our) app|'
  r'for any (queries|assistance|clarification)|in case of any (queries|discrepancy))',
  caseSensitive: false,
);

/// Drops footers, legal text and safety warnings.
String stripBoilerplate(String text) {
  final lines = text.split('\n');
  final kept = <String>[];
  var chars = 0;
  final total = text.length;
  for (final line in lines) {
    // Only treat footer markers as the end once we're past the top of the
    // message, so a "Do not reply" banner at the top doesn't eat the alert.
    if (chars > total * 0.35 && chars > 120 && _footerStart.hasMatch(line)) break;
    chars += line.length + 1;
    kept.add(line);
  }
  // Plain-text alerts are often one long line: drop only the warning sentences.
  return removeSafetyWarnings(kept.join('\n'));
}

/// Plain part unless it is missing or a "view this in HTML" stub.
String pickBodyText({String? plain, String? html}) {
  final p = plain == null ? '' : collapseLines(decodeEntities(plain));
  final plainUsable =
      p.length >= 60 &&
      !RegExp(r'(html|view (it|this) in (a|your) browser)', caseSensitive: false).hasMatch(p.split('\n').first);
  if (plainUsable || html == null || html.trim().isEmpty) return p;
  return htmlToText(html);
}

/// The text the pipeline stores for an email: subject on the first line,
/// cleaned body below, capped at [maxEmailBodyChars].
String composeEmailBody({required String subject, String? plain, String? html}) {
  final body = stripBoilerplate(pickBodyText(plain: plain, html: html));
  final s = '${collapseLines(subject)}\n$body'.trim();
  return s.length <= maxEmailBodyChars ? s : s.substring(0, maxEmailBodyChars);
}
