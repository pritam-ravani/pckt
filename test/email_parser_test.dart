import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/tables.dart';
import 'package:pckt/ingestion/email/email_source.dart';
import 'package:pckt/ingestion/parser/email_parser.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';

final received = DateTime(2026, 10, 12, 20, 30);

ParseResult p(String from, String subject, {String? plain, String? html, DateTime? at}) => const EmailParser().parse(
  emailToRawInput(externalId: '<1@x>', from: from, subject: subject, date: at ?? received, plain: plain, html: html),
);

ParsedTxn ok(String from, String subject, {String? plain, String? html}) {
  final r = p(from, subject, plain: plain, html: html);
  expect(
    r,
    isA<Parsed>(),
    reason:
        'expected parse, got $r ${r is Ignored
            ? r.reason
            : r is Unparsed
            ? r.reason
            : ''}',
  );
  return (r as Parsed).txn;
}

void ignored(String from, String subject, {String? plain, String? html, String? reason}) {
  final r = p(from, subject, plain: plain, html: html);
  expect(r, isA<Ignored>(), reason: 'expected ignore, got $r ${r is Parsed ? r.txn : ''}');
  if (reason != null) expect((r as Ignored).reason, reason);
}

void main() {
  group('bank alerts', () {
    test('HDFC UPI debit (HTML)', () {
      final t = ok(
        'HDFC Bank InstaAlerts <alerts@hdfcbank.net>',
        '❗  You have done a UPI txn. Check details!',
        html: '''
<html><head><style>p{color:red}</style><title>HDFC</title></head><body>
<table><tr><td>Dear Customer,</td></tr>
<tr><td>Rs.250.00 has been debited from account 4521 to VPA swiggy.stores@axb SWIGGY on 12-10-26.</td></tr>
<tr><td>Your UPI transaction reference number is 528512345678.</td></tr>
<tr><td>Please call 18002586161 to report if this transaction was not authorized by you. Never share your OTP, PIN or password with anyone.</td></tr>
<tr><td>Warm Regards,<br>HDFC Bank</td></tr></table>
<p>This is a system generated email. Please do not reply. &copy; HDFC Bank Ltd.</p>
</body></html>''',
      );
      expect(t.amountMinor, 25000);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '4521');
      expect(t.reference, '528512345678');
      expect(t.institution, 'HDFC Bank');
      expect(t.mode, PaymentMode.upi);
      expect(t.merchant, isNotNull);
      expect(t.confidence, greaterThanOrEqualTo(0.75));
    });

    test('HDFC credit card "thank you for using"', () {
      final t = ok(
        'alerts@hdfcbank.net',
        'Alert : Update on your HDFC Bank Credit Card',
        plain:
            'Dear Card Member,\nThank you for using your HDFC Bank Credit Card ending 7788 for Rs 1299.00 at AMAZON on '
            '12-10-2026 20:01:33.\nAuthorization code:- 012345\nIf you have not done this transaction, please call 18002586161.',
      );
      expect(t.amountMinor, 129900);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '7788');
      expect(t.merchant, 'Amazon');
      expect(t.mode, PaymentMode.card);
      expect(t.occurredAt, DateTime(2026, 10, 12, 20, 1, 33));
    });

    test('ICICI credit card with Info line and US-style date', () {
      final t = ok(
        'credit_cards@icicibank.com',
        'Transaction alert for your ICICI Bank Credit Card',
        plain:
            'Dear Customer,\nYour ICICI Bank Credit Card XX9012 has been used for a transaction of INR 2,450.00 on '
            'Oct 12, 2026 at 08:01:33 PM. Info: FLIPKART.\nThe Available Credit Limit on your card is INR 1,52,300.00 '
            'and Total Credit Limit is INR 2,00,000.00.',
      );
      expect(t.amountMinor, 245000);
      expect(t.direction, TxnDirection.debit);
      expect(t.accountHint, '9012');
      expect(t.merchant, 'Flipkart');
      expect(t.institution, 'ICICI Bank');
      expect(t.occurredAt, DateTime(2026, 10, 12, 20, 1, 33));
    });

    test('Axis UPI path', () {
      final t = ok(
        'alerts@axisbank.com',
        'Debit transaction alert for Axis Bank A/c',
        plain:
            'Dear Customer, INR 500.00 has been debited from A/c no. XX4321 on 12-10-2026 20:05:11 IST at '
            'UPI/P2M/528512349999/ZOMATO. Available balance: INR 10,000.00. If this transaction was not initiated '
            'by you, please call 18604195555.',
      );
      expect(t.amountMinor, 50000);
      expect(t.reference, '528512349999');
      expect(t.merchant, 'Zomato');
      expect(t.accountHint, '4321');
      expect(t.institution, 'Axis Bank');
    });

    test('SBI Card spend', () {
      final t = ok(
        'onlinesbicard@sbicard.com',
        'Transaction Alert from SBI Card',
        plain: 'Dear Cardholder, Rs.799.00 spent on your SBI Credit Card ending with 3456 at NETFLIX on 12/10/26.',
      );
      expect(t.amountMinor, 79900);
      expect(t.institution, 'SBI Card');
      expect(t.accountHint, '3456');
      expect(t.merchant, 'Netflix');
      expect(t.mode, PaymentMode.card);
    });

    test('salary credit', () {
      final t = ok(
        'alerts@kotak.com',
        'Credit alert',
        plain: 'Your account XX5555 has been credited with INR 85,000.00 on 01-10-2026 by NEFT from ACME CORP.',
      );
      expect(t.direction, TxnDirection.credit);
      expect(t.amountMinor, 8500000);
      expect(t.institution, 'Kotak Bank');
    });
  });

  group('merchant receipts', () {
    test('Swiggy delivered order with bill', () {
      final t = ok(
        'Swiggy <noreply@swiggy.in>',
        'Your Swiggy order was successfully delivered',
        html: '''
<div>Order No: 182345678901</div><div>Restaurant: Meghana Foods</div>
<table><tr><td>Item Total</td><td>₹420.00</td></tr>
<tr><td>Delivery Fee</td><td>₹30.00</td></tr>
<tr><td>Taxes</td><td>&#8377;25.00</td></tr>
<tr><td><b>Order Total</b></td><td><b>₹475.00</b></td></tr>
<tr><td>Paid Via</td><td>UPI</td></tr></table>
<p>Rate your order</p>''',
      );
      expect(t.amountMinor, 47500);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchant, 'Swiggy');
      expect(t.reference, isNull);
      expect(t.mode, PaymentMode.upi);
    });

    test('Amazon order confirmation', () {
      final t = ok(
        'Amazon.in <auto-confirm@amazon.in>',
        'Your Amazon.in order #403-1234567-1234567 of 1 item',
        plain:
            'Hello Asha,\nThank you for your order. We will send a confirmation when your item ships.\n'
            'Order Details\nOrder #403-1234567-1234567\nItem Subtotal: ₹1,249.00\nShipping: ₹50.00\n'
            'Order Total: ₹1,299.00\nPaid by HDFC Bank Credit Card ending in 7788',
      );
      expect(t.amountMinor, 129900);
      expect(t.merchant, 'Amazon');
      expect(t.accountHint, '7788');
      expect(t.mode, PaymentMode.card);
      expect(t.reference, isNull);
    });

    test('Flipkart confirmation with a "Track order" button still counts', () {
      final t = ok(
        'Flipkart <no-reply@flipkart.com>',
        'Your Flipkart order has been successfully placed',
        plain: 'Thank you for your order!\nTrack Order\nAmount Paid ₹2,349.00\nPaid using UPI',
      );
      expect(t.amountMinor, 234900);
      expect(t.merchant, 'Flipkart');
    });

    test('Uber trip receipt', () {
      final t = ok(
        'Uber Receipts <noreply@uber.com>',
        'Your Tuesday evening trip with Uber',
        plain: "Thanks for riding, Asha\nTotal ₹245.50\nTrip fare ₹230.00\nBooking fee ₹15.50\nPayments: UPI",
      );
      expect(t.amountMinor, 24550);
      expect(t.merchant, 'Uber');
    });

    test('Zomato refund processed is a credit', () {
      final t = ok(
        'noreply@zomato.com',
        'Refund processed for your order',
        plain: 'Your refund of ₹312.50 has been processed to your original payment method.',
      );
      expect(t.direction, TxnDirection.credit);
      expect(t.amountMinor, 31250);
      expect(t.merchant, 'Zomato');
    });
  });

  group('rejects', () {
    test('OTP email', () {
      ignored(
        'alerts@hdfcbank.net',
        'OTP for transaction',
        plain: '123456 is your One Time Password for transaction of Rs 2,000.00 at AMAZON on HDFC Bank Card 7788.',
        reason: 'OTP',
      );
    });

    test('bank promo', () {
      ignored(
        'offers@icicibank.com',
        'Exclusive offer for you!',
        plain: 'Get up to 10% cashback on your next purchase with ICICI Bank Credit Card. Apply now. T&C apply.',
      );
    });

    test('card statement', () {
      ignored(
        'statements@hdfcbank.net',
        'Your HDFC Bank Credit Card Statement for October 2026',
        plain: 'Total amount due Rs 12,345.00. Minimum amount due Rs 620.00. Payment due date 05-11-2026.',
        reason: 'Statement / bill',
      );
    });

    test('login alert', () {
      ignored(
        'alerts@icicibank.com',
        'New login to ICICI Bank Internet Banking',
        plain: 'You have successfully logged in to Internet Banking on 12-10-2026 20:00.',
      );
    });

    test('Amazon shipped (has total but is not a new payment)', () {
      ignored(
        'shipment-tracking@amazon.in',
        "Shipped: 'boAt Airdopes 141'",
        plain: 'Your package has been shipped. Order Total: ₹1,299.00. Track your package.',
        reason: 'Shipping update',
      );
    });

    test('Flipkart delivered', () {
      ignored(
        'noreply@flipkart.com',
        'Your Flipkart order has been delivered',
        plain: 'Your item was delivered. Order total ₹999.',
        reason: 'Shipping update',
      );
    });

    test('Swiggy promo newsletter', () {
      ignored(
        'noreply@swiggy.in',
        'Flat 50% off on your next order!',
        plain: 'Craving something? Get 50% off up to ₹100 with code TRYNEW. Hurry, limited time offer!',
      );
    });

    test('cash on delivery order', () {
      ignored(
        'noreply@flipkart.com',
        'Your order has been placed',
        plain: 'Thank you for your order. Order total ₹999. Payment mode: Cash on Delivery.',
        reason: 'Cash on delivery',
      );
    });

    test('refund only initiated', () {
      ignored(
        'noreply@swiggy.in',
        'Your order was cancelled',
        plain: 'A refund of ₹475 has been initiated and will reflect in 5-7 days.',
        reason: 'Refund initiated',
      );
    });

    test('cart reminder', () {
      ignored(
        'noreply@myntra.com',
        'You left something in your cart',
        plain: 'Complete your purchase now. Cart total ₹2,499.',
      );
    });

    test('password change', () {
      ignored('no-reply@accounts.google.com', 'Security alert', plain: 'Your password was changed.');
    });
  });

  test('bodyTime ignores implausible dates', () {
    expect(EmailParser.bodyTime('on 01-01-2020 10:00', received), received);
    expect(EmailParser.bodyTime('on 12 oct 2026 8:05 pm', received), DateTime(2026, 10, 12, 20, 5));
  });
}
