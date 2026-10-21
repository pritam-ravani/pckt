import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/tables.dart';
import 'package:pckt/ingestion/parser/currency_text.dart';
import 'package:pckt/ingestion/parser/email_parser.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/ingestion/parser/sms_parser.dart';

ParseResult p(String sender, String body, {String home = 'INR'}) => SmsParser(home: home).parse(
  RawInput(
    source: SourceKind.sms,
    externalId: '1',
    sender: sender,
    body: body,
    receivedAt: DateTime(2026, 10, 12, 20, 11),
  ),
);

ParsedTxn ok(String sender, String body, {String home = 'INR'}) {
  final r = p(sender, body, home: home);
  expect(r, isA<Parsed>(), reason: 'expected parse for: $body, got $r ${r is Ignored ? r.reason : ''}');
  return (r as Parsed).txn;
}

/// Below the ingestion review threshold (0.7): stored but flagged.
const reviewed = 0.7;

void main() {
  group('Indian cards abroad', () {
    test('HDFC: USD spend is stored as USD, not rupees', () {
      final t = ok(
        'VM-HDFCBK',
        'Spent USD 12.50 On HDFC Bank Card 1234 At AMAZON WEB SERVICES On 2026-10-12:20:01:07. '
            'Not You? Call 18002586161/SMS BLOCK DC 1234 to 7308080808',
      );
      expect(t.amountMinor, 1250);
      expect(t.currency, 'USD');
      expect(t.convertedMinor, isNull);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '1234');
      expect(t.institution, 'HDFC Bank');
      expect(t.mode, PaymentMode.card);
      expect(t.merchant, startsWith('Amazon Web'));
    });

    test('stated rupee equivalent is kept as the converted amount', () {
      final t = ok(
        'JD-SBICRD-S',
        'Transaction of USD 12.50 (INR 1,045.30) done on your SBI Card ending 5678 at NETFLIX.COM on 12/10/26.',
      );
      expect((t.amountMinor, t.currency), (1250, 'USD'));
      expect((t.convertedMinor, t.convertedCurrency), (104530, 'INR'));
    });

    test('available limit in rupees is not mistaken for the equivalent', () {
      final t = ok(
        'AD-ICICIT',
        'AED 250.00 spent on ICICI Bank Card XX9002 on 12-Oct-26 at DUBAI MALL. Avl Limit: INR 2,34,567.00',
      );
      expect((t.amountMinor, t.currency), (25000, 'AED'));
      expect(t.convertedMinor, isNull);
    });

    test('a rupee-first alert stays in rupees', () {
      final t = ok(
        'AD-ICICIT',
        'INR 1,045.30 spent on ICICI Bank Card XX9002 on 12-Oct-26 at AWS (USD 12.50). Avl Limit: INR 2,34,567.00',
      );
      expect((t.amountMinor, t.currency), (104530, 'INR'));
    });

    test('JPY has no minor unit; KWD has three decimals', () {
      final jpy = ok('VM-HDFCBK', 'Spent JPY 1,200 On HDFC Bank Card 1234 At LAWSON TOKYO On 2026-10-12:20:01:07.');
      expect((jpy.amountMinor, jpy.currency), (1200, 'JPY'));
      final kwd = ok('AD-ICICIT', 'KWD 12.500 spent on ICICI Bank Card XX9002 on 12-Oct-26 at ALSHAYA.');
      expect((kwd.amountMinor, kwd.currency), (12500, 'KWD'));
      final yen = ok('VM-HDFCBK', 'Spent ¥3,400 On HDFC Bank Card 1234 At UNIQLO GINZA On 2026-10-12.');
      expect((yen.amountMinor, yen.currency), (3400, 'JPY'));
    });

    test('symbols: £, €, US\$, S\$', () {
      expect(ok('VM-HDFCBK', 'Spent £8.40 On HDFC Bank Card 1234 At PRET A MANGER').currency, 'GBP');
      expect(ok('VM-HDFCBK', 'Spent €19.99 On HDFC Bank Card 1234 At FNAC PARIS').currency, 'EUR');
      expect(ok('VM-HDFCBK', 'Spent US\$5.00 On HDFC Bank Card 1234 At STARBUCKS').currency, 'USD');
      expect(ok('VM-HDFCBK', 'Spent S\$25.60 On HDFC Bank Card 1234 At GRAB').currency, 'SGD');
    });

    test('code after the number', () {
      final t = ok('VM-HDFCBK', 'Your HDFC Bank Card 1234 was charged 49.99 EUR at BOOKING.COM on 12-10-26.');
      expect((t.amountMinor, t.currency), (4999, 'EUR'));
    });
  });

  group('alerts from outside India', () {
    test('UAE debit card purchase (unknown sender → review)', () {
      final t = ok(
        'EmiratesNBD',
        'Purchase of AED 120.50 with Debit Card ending 4321 at CARREFOUR CITY CENTRE on 12/10/2026 14:22. '
            'Avl Bal AED 5,230.10.',
        home: 'AED',
      );
      expect((t.amountMinor, t.currency, t.direction), (12050, 'AED', TxnDirection.debit));
      expect(t.accountHint, '4321');
      expect(t.merchant, 'Carrefour City Centre');
      expect(t.confidence, lessThan(reviewed));
    });

    test('UAE salary credit', () {
      final t = ok(
        'ADCBAlert',
        'AED 3,500.00 has been credited to your account XXXX5678 on 12-OCT-2026. Avl Bal AED 8,730.10',
        home: 'AED',
      );
      expect((t.amountMinor, t.currency, t.direction), (350000, 'AED', TxnDirection.credit));
    });

    test('US card purchase from a short code', () {
      final t = ok(
        '93557',
        'BofA: Debit card purchase of \$45.20 at TARGET T-1234 on 10/12 with card ending in 1234.',
        home: 'USD',
      );
      expect((t.amountMinor, t.currency, t.direction), (4520, 'USD', TxnDirection.debit));
      expect(t.merchant, startsWith('Target'));
      expect(t.confidence, lessThan(reviewed));
    });

    test('US direct deposit', () {
      final t = ok(
        '93557',
        'Wells Fargo: \$1,250.00 direct deposit was credited to your account ending 9876.',
        home: 'USD',
      );
      expect((t.amountMinor, t.currency, t.direction), (125000, 'USD', TxnDirection.credit));
    });

    test('UK card spend and transfer in', () {
      final spend = ok('Barclays', 'Barclays: You spent £12.50 at TESCO STORES on your card ending 4455.', home: 'GBP');
      expect((spend.amountMinor, spend.currency, spend.direction), (1250, 'GBP', TxnDirection.debit));
      expect(spend.merchant, 'Tesco Stores');
      final rent = ok('Monzo', 'Monzo: £850.00 received from J SMITH. Ref: RENT OCT', home: 'GBP');
      expect((rent.amountMinor, rent.currency, rent.direction), (85000, 'GBP', TxnDirection.credit));
    });

    test('Singapore card use and PayNow', () {
      final card = ok(
        'DBS',
        'DBS: Your card ending 1234 was used for SGD 25.60 on 12 OCT 14:02 (SGT) at GRAB*RIDE. '
            'If unauthorised, call 1800 111 1111.',
        home: 'SGD',
      );
      expect((card.amountMinor, card.currency, card.direction), (2560, 'SGD', TxnDirection.debit));
      expect(card.institution, 'DBS Bank');
      final paynow = ok('OCBC', 'OCBC: You have sent SGD 50.00 to JOHN TAN via PayNow on 12 Oct 14:05.', home: 'SGD');
      expect((paynow.amountMinor, paynow.currency, paynow.direction), (5000, 'SGD', TxnDirection.debit));
      expect(paynow.merchant, 'John Tan');
    });

    test('generic "debited <currency> <amount>" from an unknown sender parses for review', () {
      final t = ok('BANKX', 'Alert: USD 30.00 debited from your account ending 1111 at UBER.');
      expect((t.amountMinor, t.currency, t.direction), (3000, 'USD', TxnDirection.debit));
      expect(t.confidence, lessThan(reviewed));
    });

    test('a bare \$ is the home dollar, else USD', () {
      expect(ok('BANKX', 'You spent \$9.99 at APPLE.COM/BILL', home: 'CAD').currency, 'CAD');
      expect(ok('BANKX', 'You spent \$9.99 at APPLE.COM/BILL', home: 'AUD').currency, 'AUD');
      expect(ok('BANKX', 'You spent \$9.99 at APPLE.COM/BILL').currency, 'USD');
    });

    test('Rs is the home rupee for PKR / LKR / NPR users', () {
      expect(ok('MEEZAN', 'Rs.1,500 debited from your A/C XX1234 at KFC', home: 'PKR').currency, 'PKR');
      expect(ok('VM-HDFCBK', 'Rs.1,500 debited from your A/C XX1234 at KFC').currency, 'INR');
    });

    test('foreign OTPs, declines and balance alerts are still ignored', () {
      expect(p('DBS', 'DBS: Your OTP for SGD 25.60 at GRAB is 123456.', home: 'SGD'), isA<Ignored>());
      expect(p('93557', 'Your card purchase of \$45.20 at TARGET was declined.', home: 'USD'), isA<Ignored>());
      expect(p('ENBD', 'Your available balance is AED 5,230.10.', home: 'AED'), isA<Ignored>());
    });

    test('Turkish lira only when written in capitals', () {
      final lira = ok('BANKX', 'You spent TRY 250.00 at MIGROS with card ending 1234.', home: 'TRY');
      expect((lira.amountMinor, lira.currency), (25000, 'TRY'));
      final t = ok('BANKX', 'Please try 2 days later. Rs 100 debited from A/C XX12 at KFC');
      expect((t.amountMinor, t.currency), (10000, 'INR'));
    });
  });

  group('currency tokens', () {
    test('resolve to ISO codes', () {
      expect(currencyOfToken('rs.', home: 'INR'), 'INR');
      expect(currencyOfToken('us\$', home: 'CAD'), 'USD');
      expect(currencyOfToken('\$', home: 'SGD'), 'SGD');
      expect(currencyOfToken('\$', home: 'GBP'), 'USD');
      expect(currencyOfToken('£', home: 'INR'), 'GBP');
      expect(currencyOfToken('aed', home: 'INR'), 'AED');
      expect(currencyOfToken('rm', home: 'INR'), 'MYR');
    });

    test('words that look like codes are not currencies', () {
      final re = RegExp('$currencyTokenPattern\\s*$amountPattern');
      expect(re.hasMatch('cadbury 200'), isFalse);
      expect(re.hasMatch('thanks 2 u'), isFalse);
      expect(re.hasMatch('usd 2'), isTrue);
    });
  });

  group('email', () {
    test('a receipt in dollars keeps its currency', () {
      final r = const EmailParser(sms: SmsParser(home: 'USD')).parse(
        RawInput(
          source: SourceKind.email,
          externalId: 'e1',
          sender: 'noreply@uber.com',
          body: 'Your Tuesday evening trip with Uber\nThanks for riding, Asha\nTotal \$18.40\nTrip fare \$15.00',
          receivedAt: DateTime(2026, 10, 12, 20),
        ),
      );
      expect(r, isA<Parsed>());
      final t = (r as Parsed).txn;
      expect((t.amountMinor, t.currency), (1840, 'USD'));
    });

    test('a bank alert email abroad keeps its currency', () {
      final r = const EmailParser().parse(
        RawInput(
          source: SourceKind.email,
          externalId: 'e2',
          sender: 'alerts@hdfcbank.net',
          body:
              'Alert : Update on your HDFC Bank Credit Card\nDear Customer, Thank you for using your HDFC Bank Credit Card '
              'ending 7788 for USD 12.50 at AMAZON WEB SERVICES on 12-10-2026 20:01:07.',
          receivedAt: DateTime(2026, 10, 12, 20, 5),
        ),
      );
      expect(r, isA<Parsed>());
      final t = (r as Parsed).txn;
      expect((t.amountMinor, t.currency), (1250, 'USD'));
    });
  });
}
