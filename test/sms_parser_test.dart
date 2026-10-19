import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/tables.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/ingestion/parser/sms_parser.dart';

ParseResult p(String sender, String body) => const SmsParser().parse(
  RawInput(
    source: SourceKind.sms,
    externalId: '1',
    sender: sender,
    body: body,
    receivedAt: DateTime(2026, 10, 12, 20, 11),
  ),
);

ParsedTxn ok(String sender, String body) {
  final r = p(sender, body);
  expect(r, isA<Parsed>(), reason: 'expected parse for: $body, got $r ${r is Ignored ? r.reason : ''}');
  return (r as Parsed).txn;
}

void main() {
  group('debits', () {
    test('HDFC UPI sent', () {
      final t = ok(
        'VM-HDFCBK-S',
        'Sent Rs.250.00\nFrom HDFC Bank A/C *4521\nTo SWIGGY\nOn 12/10/26\nRef 528512345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808',
      );
      expect(t.amountMinor, 25000);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '4521');
      expect(t.reference, '528512345678');
      expect(t.merchant, 'Swiggy');
      expect(t.institution, 'HDFC Bank');
      expect(t.mode, PaymentMode.upi);
    });

    test('HDFC card spend', () {
      final t = ok(
        'AD-HDFCBK',
        'Spent Rs.1,299 On HDFC Bank Card 7788 At AMAZON PAY INDIA On 2026-10-12:20:11:07.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 7788 to 7308080808',
      );
      expect(t.amountMinor, 129900);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '7788');
      expect(t.merchant, 'Amazon Pay');
      expect(t.mode, PaymentMode.card);
    });

    test('ICICI UPI debit with merchant before credited', () {
      final t = ok(
        'JD-ICICIT-S',
        'ICICI Bank Acct XX123 debited for Rs 180.00 on 12-Oct-26; ZOMATO LTD credited. UPI:528598765432. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.',
      );
      expect(t.amountMinor, 18000);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '123');
      expect(t.reference, '528598765432');
      expect(t.merchant, 'Zomato');
    });

    test('ICICI card spend with avl limit', () {
      final t = ok(
        'VK-ICICIT',
        'INR 2,450.00 spent using ICICI Bank Card XX9012 on 12-Oct-26 on FLIPKART. Avl Limit: INR 1,52,300.00. If not you, call 1800 2662/SMS BLOCK 9012 to 9215676766',
      );
      expect(t.amountMinor, 245000);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchant, 'Flipkart');
      expect(t.accountHint, '9012');
    });

    test('SBI UPI debit', () {
      final t = ok(
        'BZ-SBIUPI',
        'Dear UPI user A/C X3456 debited by 120.0 on date 12Oct26 trf to RAHUL SHARMA Refno 528511112222. If not u? call 1800111109. -SBI',
      );
      expect(t.amountMinor, 12000);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '3456');
      expect(t.reference, '528511112222');
      expect(t.merchant, 'Rahul Sharma');
      expect(t.isPersonToPerson, isTrue);
    });

    test('Axis UPI P2M path', () {
      final t = ok(
        'AX-AXISBK-S',
        'INR 99.00 debited\nA/c no. XX7890\n12-10-26, 20:11:12\nUPI/P2M/528533334444/BLINKIT\nNot you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank',
      );
      expect(t.amountMinor, 9900);
      expect(t.reference, '528533334444');
      expect(t.merchant, 'Blinkit');
      expect(t.accountHint, '7890');
    });

    test('Kotak sent to VPA', () {
      final t = ok(
        'VM-KOTAKB',
        'Sent Rs.60.00 from Kotak Bank AC X5555 to chaipoint.blr@okicici on 12-10-26.UPI Ref 528544445555. Not you, https://kotak.com/KBANKT/Fraud',
      );
      expect(t.amountMinor, 6000);
      expect(t.direction, TxnDirection.debit);
      expect(t.counterparty, 'chaipoint.blr@okicici');
      expect(t.merchant, 'Chaipoint Blr');
      expect(t.reference, '528544445555');
    });

    test('ATM withdrawal', () {
      final t = ok(
        'VM-SBIINB',
        'Rs.2000 withdrawn at SBI ATM S1BW000123 from A/cX3456 on 12Oct26 Txn# 1234. Avl Bal Rs 12,000.00',
      );
      expect(t.amountMinor, 200000);
      expect(t.mode, PaymentMode.atm);
    });

    test('autopay debit is a real debit', () {
      final t = ok(
        'VM-HDFCBK',
        'Rs.649.00 debited from A/c **4521 on 12-10-26 towards UPI Mandate NETFLIX. UPI Ref 528599990000.',
      );
      expect(t.amountMinor, 64900);
      expect(t.direction, TxnDirection.debit);
    });
  });

  group('real-world templates', () {
    test('HDFC NACH / SIP via Indian Clearing Corp', () {
      final t = ok(
        'JD-HDFCBK-S',
        'PAYMENT ALERT! INR 500.00 deducted from HDFC Bank A/C No 6610 towards INDIAN CLEARING CORP LTD UMRN: HDFC7021807230012345',
      );
      expect(t.amountMinor, 50000);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchant, 'Indian Clearing Corp');
      expect(t.accountHint, '6610');
    });

    test('"towards" is not "to" + "wards"', () {
      final t = ok(
        'JD-HDFCBK-S',
        'PAYMENT ALERT! INR 2,500.00 deducted from HDFC Bank A/C No 6610 towards LIC OF INDIA UMRN: HDFC7011701251001263',
      );
      expect(t.merchant, 'LIC Of India');
      expect(t.counterparty, 'LIC OF INDIA');
    });

    test('HDFC IMPS credit with dashed name', () {
      final t = ok(
        'VD-HDFCBK-S',
        'Received! INR 25,000.00 in HDFC Bank A/c xx6610 On 12-10-26 For IMPS -ANCHALDEVIUCHITRAM- 628512345678 Avl bal INR 1,23,456.00',
      );
      expect(t.direction, TxnDirection.credit);
      expect(t.amountMinor, 2500000);
      expect(t.merchant, 'Anchaldeviuchitram');
      expect(t.mode, PaymentMode.imps);
    });

    test('HDFC cash deposit machine', () {
      final t = ok(
        'AD-HDFCBK-S',
        'Deposited! INR 20,000.00 in HDFC Bank A/c XX6610 On 12/10/26 10:11:12 At Sachin Surat Via Cash Deposit Machine Bal: INR 45,000.00',
      );
      expect(t.direction, TxnDirection.credit);
      expect(t.amountMinor, 2000000);
      expect(t.merchant, 'Cash Deposit');
      expect(t.mode, PaymentMode.cash);
    });

    test('card spend is never person-to-person', () {
      final t = ok(
        'AD-HDFCBK-S',
        'Spent Rs.12000 From HDFC Bank Card x9590 At BAPS PRAMUKH SWAMI HOS On 2026-10-12:10:11:12 Bal Rs.5000.00 Not You? Call 18002586161/SMS BLOCK DC 9590 to 7308080808',
      );
      expect(t.mode, PaymentMode.card);
      expect(t.isPersonToPerson, isFalse);
    });

    test('IME remittance without currency symbol', () {
      final t = ok(
        'AD-IMEIND-S',
        'Successfully sent 15000.00 to DASHI RAM THARU. Please provide ICN: 12345678901 to the beneficiary only. -IME India',
      );
      expect(t.amountMinor, 1500000);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchant, 'Dashi Ram Tharu');
    });
  });

  group('credits', () {
    test('HDFC credit alert', () {
      final t = ok(
        'VM-HDFCBK',
        'Credit Alert!\nRs.500.00 credited to HDFC Bank A/c XX4521 on 12-10-26 from VPA priya.k@okaxis (UPI 528577778888)',
      );
      expect(t.amountMinor, 50000);
      expect(t.direction, TxnDirection.credit);
      expect(t.reference, '528577778888');
      expect(t.counterparty, 'priya.k@okaxis');
    });

    test('Salary NEFT', () {
      final t = ok(
        'VM-ICICIB',
        'Dear Customer, your A/c XX123 has been credited with INR 85,000.00 on 01-Oct-26 by NEFT from ACME TECHNOLOGIES PVT LTD. Avl Bal INR 1,02,345.67',
      );
      expect(t.amountMinor, 8500000);
      expect(t.direction, TxnDirection.credit);
      expect(t.mode, PaymentMode.neft);
      expect(t.merchant, 'Acme');
    });

    test('refund is a credit even if it says debited earlier', () {
      final t = ok(
        'VM-HDFCBK',
        'Refund of Rs.299.00 for txn debited on 10-10-26 has been credited to your A/c XX4521.',
      );
      expect(t.direction, TxnDirection.credit);
      expect(t.amountMinor, 29900);
    });

    test('credit card bill payment received is flagged as transfer', () {
      final t = ok(
        'AD-HDFCBK',
        'Payment of Rs.15,000.00 has been received on your HDFC Bank Credit Card ending 7788 on 12-10-26. Thank you.',
      );
      expect(t.direction, TxnDirection.credit);
      expect(t.transferHint, isTrue);
    });
  });

  group('ignored', () {
    void ignored(String sender, String body) => expect(p(sender, body), isA<Ignored>(), reason: body);

    test('OTP', () => ignored('VM-HDFCBK', '123456 is your OTP for txn of Rs.2,000 at AMAZON. Do not share.'));
    test('reminder', () => ignored('VM-ICICIT', 'Rs 649 will be debited on 15-Oct-26 towards Netflix mandate.'));
    test(
      'failed',
      () => ignored('VM-HDFCBK', 'Your UPI txn of Rs.250 to SWIGGY has failed. Amount if debited will be refunded.'),
    );
    test(
      'collect request',
      () => ignored('VM-SBIUPI', 'RAHUL has requested money Rs 500 from you on UPI. Pay via BHIM.'),
    );
    test(
      'statement',
      () => ignored(
        'AD-HDFCBK',
        'Statement for HDFC Credit Card 7788: Total Amt Due Rs 15,000; Min Amt Due Rs 750, due by 20-10-26.',
      ),
    );
    test(
      'promo',
      () => ignored('VM-HDFCBK-P', 'Get a pre-approved loan of up to Rs 5,00,000 at lowest EMI! Apply now.'),
    );
    test('personal sms', () => ignored('+919876543210', 'Sent you Rs 200 for lunch'));
    test('balance alert', () => ignored('VM-SBIINB', 'Avl Bal in A/c X3456 is Rs 12,000.00 as on 12-10-26.'));
  });
}
