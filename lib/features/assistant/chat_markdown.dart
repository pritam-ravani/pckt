import 'package:flutter/material.dart';

/// Just enough Markdown for chat answers: paragraphs, `-`/`*`/`1.` lists,
/// `#` headings (rendered bold), **bold**, *italic* and `code`.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
  static final _numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
  static final _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');
  static final _inline = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`([^`]+)`|(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?!\w)');

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final blocks = <Widget>[];
    final para = <String>[];

    void flush() {
      if (para.isEmpty) return;
      blocks.add(Text.rich(TextSpan(children: spans(para.join(' '), base)), style: base));
      para.clear();
    }

    for (final line in text.trim().split('\n')) {
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final b = _bullet.firstMatch(line), n = _numbered.firstMatch(line), h = _heading.firstMatch(line);
      if (b != null || n != null) {
        flush();
        final marker = b != null ? '•' : '${n!.group(1)}.';
        final body = b != null ? b.group(1)! : n!.group(2)!;
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 20, child: Text(marker, style: base)),
                Expanded(
                  child: Text.rich(TextSpan(children: spans(body, base)), style: base),
                ),
              ],
            ),
          ),
        );
      } else if (h != null) {
        flush();
        blocks.add(
          Text.rich(
            TextSpan(children: spans(h.group(1)!, base)),
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        para.add(line.trim());
      }
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, w) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: w,
          ),
      ],
    );
  }

  /// Inline formatting → spans. Exposed for tests.
  static List<InlineSpan> spans(String s, TextStyle base) {
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > at) out.add(TextSpan(text: s.substring(at, m.start)));
      if (m.group(1) != null || m.group(2) != null) {
        out.add(
          TextSpan(
            text: m.group(1) ?? m.group(2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (m.group(3) != null) {
        out.add(
          TextSpan(
            text: m.group(3),
            style: TextStyle(fontFamily: 'monospace', backgroundColor: base.color?.withValues(alpha: 0.08)),
          ),
        );
      } else {
        out.add(
          TextSpan(
            text: m.group(4),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      at = m.end;
    }
    if (at < s.length) out.add(TextSpan(text: s.substring(at)));
    return out;
  }
}
