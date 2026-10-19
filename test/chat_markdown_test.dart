import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/features/assistant/chat_markdown.dart';

void main() {
  test('inline bold, italic and code become styled spans', () {
    final spans = ChatMarkdown.spans('You spent **₹1,23,456** on *food* via `UPI`.', const TextStyle());
    final texts = spans.cast<TextSpan>().map((s) => s.text).toList();
    expect(texts, ['You spent ', '₹1,23,456', ' on ', 'food', ' via ', 'UPI', '.']);
    expect((spans[1] as TextSpan).style?.fontWeight, FontWeight.w700);
    expect((spans[3] as TextSpan).style?.fontStyle, FontStyle.italic);
  });

  testWidgets('renders bullets and paragraphs', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChatMarkdown('Top categories:\n\n- **Food** ₹4,200\n- Travel ₹1,100\n1. First')),
      ),
    );
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('1.'), findsOneWidget);
    expect(find.textContaining('Travel', findRichText: true), findsOneWidget);
  });
}
