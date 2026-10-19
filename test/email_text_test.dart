import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/ingestion/email/email_source.dart';
import 'package:pckt/ingestion/email/email_text.dart';
import 'package:pckt/ingestion/email/gmail_api_source.dart';
import 'package:pckt/ingestion/email/imap_source.dart';

void main() {
  test('htmlToText drops head, scripts, styles and keeps structure', () {
    final t = htmlToText('''
<html><head><title>T</title><style>.a{color:red}</style><script>var x = "Rs 999";</script></head>
<body><!-- tracking --><div>Hello&nbsp;there</div><table><tr><td>Order Total</td><td>&#8377;475.00</td></tr></table>
<p>Fish &amp; Chips</p><br/>Line&#x20B9;2</body></html>''');
    expect(t, 'Hello there\nOrder Total ₹475.00\nFish & Chips\nLine₹2');
  });

  test('pickBodyText prefers real plain text, falls back to HTML', () {
    expect(pickBodyText(plain: 'View this email in your browser', html: '<p>Rs 10 debited</p>'), 'Rs 10 debited');
    final plain = 'Dear Customer, Rs.250.00 has been debited from account 4521 to VPA x@y on 12-10-26.';
    expect(pickBodyText(plain: plain, html: '<p>other</p>'), plain);
  });

  test('composeEmailBody strips footers and safety warnings, caps length', () {
    final body = composeEmailBody(
      subject: 'UPI txn alert',
      plain:
          'Dear Customer,\nRs.250.00 has been debited from account 4521. Never share your OTP or PIN with anyone.\n'
          'Warm regards, HDFC Bank\n${'Some marketing line here.\n' * 3}'
          'This is a system generated email, please do not reply.\nDisclaimer: lots of legal text that goes on.',
    );
    expect(body.split('\n').first, 'UPI txn alert');
    expect(body, contains('Rs.250.00 has been debited from account 4521.'));
    expect(body, isNot(contains('OTP')));
    expect(body, isNot(contains('Disclaimer')));
    expect(body, isNot(contains('system generated')));

    final long = composeEmailBody(subject: 's', plain: 'word ' * 3000);
    expect(long.length, maxEmailBodyChars);
  });

  test('IMAP search narrows by date, sender domains and subjects', () {
    expect(imapDate(DateTime(2026, 9, 5)), '5-Sep-2026');
    expect(imapOr(['A', 'B', 'C']), 'OR A OR B C');
    final q = imapSearchCriteria(DateTime(2026, 9, 5));
    expect(q, startsWith('SINCE 5-Sep-2026 OR FROM "'));
    expect(q, contains('FROM "hdfcbank"'));
    expect(q, contains('SUBJECT "debited"'));
    expect(gmailQuery(DateTime(2026, 9, 5)), startsWith('after:2026/9/4 {from:('));
  });

  test('header pre-filter', () {
    expect(looksFinancialHeader('alerts@hdfcbank.net', 'anything'), isTrue);
    expect(looksFinancialHeader('friend@gmail.com', 'Dinner on Friday?'), isFalse);
    expect(looksFinancialHeader('billing@someshop.in', 'Your payment receipt'), isTrue);
  });

  test('Gmail API message → RawInput', () {
    final input = gmailMessageToInput({
      'id': 'abc',
      'internalDate': '${DateTime(2026, 10, 12, 20).millisecondsSinceEpoch}',
      'payload': {
        'mimeType': 'multipart/alternative',
        'headers': [
          {'name': 'From', 'value': 'Swiggy <noreply@swiggy.in>'},
          {'name': 'Subject', 'value': 'Your order'},
          {'name': 'Message-ID', 'value': '<m1@swiggy.in>'},
        ],
        'parts': [
          {
            'mimeType': 'text/html',
            'body': {'data': 'PGI-T3JkZXIgVG90YWw8L2I-IOKCuTQ3NS4wMA'},
          },
        ],
      },
    })!;
    expect(input.externalId, '<m1@swiggy.in>');
    expect(input.sender, 'noreply@swiggy.in');
    expect(input.body, 'Your order\nOrder Total ₹475.00');
    expect(input.receivedAt, DateTime(2026, 10, 12, 20));
  });
}
