import '../../core/currency.dart';
import '../../data/db/tables.dart';
import '../email/email_text.dart';
import 'currency_text.dart';
import 'email_senders.dart';
import 'parsed_txn.dart';
import 'sms_parser.dart';
import 'text_utils.dart';

/// Parser for bank alert and merchant receipt emails.
///
/// Input body is `subject + "\n" + cleaned text` (see `composeEmailBody`).
///  * Bank / card / wallet alerts are read with the SMS rules, after the
///    email-only noise (safety warnings, footers) is removed.
///  * Merchant receipts (Swiggy, Amazon, Uber, …) are read with
///    receipt-specific rules; the merchant comes from the sender domain.
///    They never carry a reference id (order ids aren't bank refs), so
///    dedup can merge them with the bank alert for the same payment.
///
/// Strict about what counts as a completed payment: OTPs, security alerts,
/// statements, promos, shipping updates, cart reminders, COD orders and
/// pending/initiated refunds are all ignored.
class EmailParser implements MessageParser {
  const EmailParser({this.sms = const SmsParser()});

  final SmsParser sms;

  // ---- rejections ---------------------------------------------------------

  static final _otp = RegExp(
    r'(\botp\b|one[- ]time password|verification code|security code|passcode)'
    r'.{0,40}(\b(is|for)\b|:)|\b(your|the) (otp|verification code)\b',
  );
  static final _security = RegExp(
    r'(password (has been |was )?(changed|reset|updated)|reset your password|new (sign[- ]?in|login|device)|'
    r'(login|log-in|sign[- ]?in) (alert|attempt|notification|detected|from)|logged in|successfully logged|'
    r'security alert|registered (mobile|email) (number )?(has been )?(changed|updated)|'
    r'verify your (email|account)|activate your account)',
  );
  static final _statement = RegExp(
    r'(e-?statement|statement (for|of|is|has)|account statement|card statement|monthly statement|'
    r'statement period|bill (is )?generated|total (amount )?due|min(imum)? (amount )?due|payment due|due date|'
    r'tax invoice for the (month|period))',
  );
  static final _promo = RegExp(
    r'(\boffers?\b|% off|\bsale\b|coupon|\bdeals?\b|cashback (of )?up ?to|get up ?to|pre-?approved|apply now|'
    r'limited (period|time)|exclusive|newsletter|recommended for you|you might like|hurry|last chance|webinar|'
    r'refer (a friend|and earn)|rate (your|us)|feedback|survey|how was your)',
  );
  static final _shipping = RegExp(
    r'(\bshipped\b|has been dispatched|\bdispatched\b|out for delivery|(has been|was|is) delivered|\bdelivered:|'
    r'arriving (today|tomorrow|by|on)|on (its|the) way|in transit|track (your )?(order|package|shipment)|'
    r'delivery (attempt|update|status)|ready for pickup)',
  );
  static final _cancelled = RegExp(
    r'(order (has been |was |is )?cancel+ed|cancel+ation (request|confirmed|successful)|return (request|pickup|initiated)|'
    r'(has been|was) returned|replacement)',
  );
  static final _orderConfirmed = RegExp(
    r'order (has been |is )?(placed|confirmed|successful)|thank(s| you) for (your )?(order|purchase)|order confirmation',
  );
  static final _cod = RegExp(r'(cash on delivery|pay on delivery|\bcod\b|pay (at|on) (delivery|pickup))');
  static final _cart = RegExp(
    r'(your cart|left (something |items? )?in (your )?cart|complete your (order|purchase|booking)|still interested|'
    r'items? (are )?waiting|price drop|back in stock|wishlist)',
  );
  static final _failedOrPending = RegExp(
    r'\b(failed|declined|unsuccessful|could not be (processed|completed)|pending|awaiting payment|'
    r'payment (is )?required|retry payment|not been processed)\b',
  );
  static final _refundDone = RegExp(
    r'refund\w*\b.{0,80}\b(has been |was |is )?(processed|credited|completed|issued|successful|refunded)\b|'
    r'(processed|credited|issued) (a |your |the )?refund',
  );
  static final _refundStarted = RegExp(r'refund\w*\b.{0,60}\b(initiated|requested|will be|is being|under process)');

  /// Something that says money actually changed hands.
  static final _paidSignal = RegExp(
    r'(\bpaid\b|payment (was |has been |is )?(successful|received|confirmed|complete|done)|successfully paid|'
    r'order (has been |is )?(placed|confirmed|successful)|thank(s| you) for (your )?(order|purchase|payment|booking|riding|ride|shopping)|'
    r'\breceipt\b|\binvoice\b|booking (is |has been )?confirmed|(trip|ride) (with|on|receipt|summary|completed)|'
    r'your (ride|trip) |order total|grand total|bill total|total paid|amount paid|amount charged|total charged|'
    r'charged to|renewed|subscription (has been )?(renewed|activated|started)|membership)',
  );

  // ---- extraction ---------------------------------------------------------

  /// Group 1 is the currency marker, group 2 the amount.
  static const _amt = '$currencyTokenPattern\\s*$amountPattern';

  /// Labelled totals, most authoritative first.
  static final _totals = <RegExp>[
    for (final label in const [
      r'(?:total )?amount paid',
      r'total paid',
      r'paid amount',
      r'you paid',
      r'grand total',
      r'order total',
      r'bill total',
      r'total (?:amount )?charged',
      r'amount charged',
      r'total amount',
      r'net (?:amount|payable|total)',
      r'payment of',
      r'total fare',
      r'(?<!item )(?<!sub ?)(?<!sub-)\btotal\b',
      r'trip fare',
    ])
      RegExp('$label[^0-9₹\\n]{0,30}(?:\\n[^0-9₹\\n]{0,10})?$_amt'),
  ];

  static final _refundAmount = RegExp('refund\\w*[^0-9₹\\n]{0,40}$_amt');
  static final _anyAmount = RegExp(_amt);

  static final _cardOrAcct = RegExp(
    r'(?:card|a/?c|acct|account)[^0-9\n]{0,25}?(?:ending(?:\s*(?:in|with))?|no\.?|[x*•]{2,})\s*[:\-]?\s*[x*•]*\s*(\d{4})\b',
  );
  static final _rrn = RegExp(
    r'(?:upi\s*(?:ref(?:erence)?|txn|transaction)\s*(?:no\.?|id|number)?|rrn|utr)[^0-9\n]{0,6}(\d{12})\b',
  );

  static final _forwardedFrom = RegExp(r'^\s*from:\s*.*?([a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,})', multiLine: true);

  // A date followed by a time: 12-10-2026 20:01, 12 Oct 2026 8:01 pm,
  // Oct 12, 2026 at 08:01:33 PM, 2026-10-12:20:01:07.
  static const _time = r'[^0-9\n]{0,12}?(?<h>\d{1,2}):(?<mi>\d{2})(?::(?<s>\d{2}))?\s*(?<ap>am|pm)?';
  static final _dateTimes = <RegExp>[
    RegExp(r'\b(?<d>\d{1,2})[-/ ](?<mon>[a-z]{3,9}|\d{1,2})[-/, ]+(?<y>\d{4}|\d{2})\b' + _time),
    RegExp(r'\b(?<mon>[a-z]{3,9})\.? (?<d>\d{1,2}),? (?<y>\d{4})\b' + _time),
    RegExp(r'\b(?<y>\d{4})-(?<mon>\d{2})-(?<d>\d{2})' + _time),
  ];
  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  @override
  ParseResult parse(RawInput input) {
    final text = removeSafetyWarnings(normalizeSpace(input.body));
    final lower = text.toLowerCase();
    final subject = lower.split('\n').first;

    var sender = EmailSenders.parse(input.sender);
    // Alerts the user forwards to themselves keep the original sender inside.
    if (!sender.isKnown && RegExp(r'^(fwd?|fw)\s*:').hasMatch(subject)) {
      final orig = _forwardedFrom.firstMatch(lower)?.group(1);
      if (orig != null) sender = EmailSenders.parse(orig);
    }

    if (_otp.hasMatch(lower)) return const Ignored('OTP');
    if (_security.hasMatch(lower)) return const Ignored('Security / account alert');
    if (_statement.hasMatch(subject)) return const Ignored('Statement / bill');

    return sender.isMerchant ? _receipt(input, sender, text, lower, subject) : _alert(input, sender, text, lower);
  }

  // ---- bank / card / wallet alerts ----------------------------------------

  ParseResult _alert(RawInput input, EmailSenderInfo sender, String text, String lower) {
    if (_shipping.hasMatch(lower) && !_strongVerb(lower)) return const Ignored('Shipping update');
    if (!sender.isKnown && _promo.hasMatch(lower) && !_strongVerb(lower)) return const Ignored('Promotional');

    // Run the SMS rules with a DLT-style header so institution lookups work.
    final header =
        sender.smsHeader ?? sender.domain.split('.').first.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final result = sms.parse(
      RawInput(
        source: input.source,
        externalId: input.externalId,
        sender: 'EM-${header.isEmpty ? 'EMAIL' : header}',
        // Card emails say "Thank you for using your Credit Card ending 7788
        // for Rs 1299 at X" — no debit verb the SMS rules would recognise.
        body: text.replaceAll(_thankYouForUsing, 'spent using your'),
        receivedAt: input.receivedAt,
      ),
    );
    if (result is! Parsed) return result;
    final t = result.txn;

    // ICICI card emails put the merchant on an "Info:" line.
    final info = _infoMerchant.firstMatch(text)?.group(1);
    var merchant = info != null ? cleanMerchant(info) ?? t.merchant : _firstSentence(t.merchant);
    if (merchant != null && RegExp(r'^\d{1,2}\s\d{2}\b').hasMatch(merchant)) merchant = null; // "at 08:01 PM"

    var confidence = t.confidence;
    // A known bank's own mailbox is as trustworthy as its SMS header.
    if (sender.isInstitution) confidence = confidence < 0.75 ? 0.75 : confidence;
    if (!sender.isKnown) confidence -= 0.1;

    return Parsed(
      ParsedTxn(
        amountMinor: t.amountMinor,
        currency: t.currency,
        convertedMinor: t.convertedMinor,
        convertedCurrency: t.convertedCurrency,
        direction: t.direction,
        occurredAt: bodyTime(lower, input.receivedAt),
        mode: t.mode,
        confidence: confidence.clamp(0, 1).toDouble(),
        merchant: merchant,
        counterparty: _firstSentence(t.counterparty) ?? info?.trim(),
        accountHint: t.accountHint,
        reference: t.reference,
        institution: sender.isInstitution ? sender.name : t.institution,
        isPersonToPerson: t.isPersonToPerson,
        transferHint: t.transferHint,
      ),
    );
  }

  static final _thankYouForUsing = RegExp(r'thank you for using your', caseSensitive: false);
  static final _infoMerchant = RegExp(
    r'\binfo\s*:\s*([A-Za-z0-9][A-Za-z0-9 &*._\-]{1,40}?)\s*(?:[.\n]|$)',
    caseSensitive: false,
  );

  /// Email alerts are prose: a name captured up to "/" or a line end can run
  /// into the next sentence ("ZOMATO. Available balance…").
  static String? _firstSentence(String? s) => s?.split(RegExp(r'\.\s')).first.trim();

  static bool _strongVerb(String l) => RegExp(r'\b(debited|credited|spent|withdrawn)\b').hasMatch(l);

  // ---- merchant receipts --------------------------------------------------

  ParseResult _receipt(RawInput input, EmailSenderInfo sender, String text, String lower, String subject) {
    final kind = sender.kind!;
    final deliveredIsReceipt = kind == EmailSenderKind.food || kind == EmailSenderKind.ride;

    if (_cart.hasMatch(lower)) return const Ignored('Cart reminder');
    if (_refundStarted.hasMatch(lower) && !_refundDone.hasMatch(lower)) return const Ignored('Refund initiated');

    final refund = _refundDone.hasMatch(lower);
    if (!refund) {
      if (_cancelled.hasMatch(lower)) return const Ignored('Cancellation / return');
      // Order confirmations often carry a "Track order" button; only the
      // subject (or a body that isn't a confirmation) marks a shipping update.
      if (!deliveredIsReceipt &&
          (_shipping.hasMatch(subject) || (!_orderConfirmed.hasMatch(lower) && _shipping.hasMatch(lower)))) {
        return const Ignored('Shipping update');
      }
      if (_failedOrPending.hasMatch(lower)) return const Ignored('Failed / pending');
      if (_cod.hasMatch(lower)) return const Ignored('Cash on delivery');
      if (_statement.hasMatch(lower) && !RegExp(r'\b(paid|payment (successful|received))\b').hasMatch(lower)) {
        return const Ignored('Statement / bill');
      }
      if (!_paidSignal.hasMatch(lower)) {
        return _promo.hasMatch(lower) ? const Ignored('Promotional') : const Ignored('Not a payment');
      }
    }

    final total = refund ? _refundAmountOf(lower) : _totalOf(lower);
    if (total == null) {
      if (_promo.hasMatch(lower)) return const Ignored('Promotional');
      return _anyAmount.hasMatch(lower) ? const Unparsed('Receipt without a clear total') : const Ignored('No amount');
    }

    final acct = _cardOrAcct.firstMatch(lower)?.group(1);
    final (amount, currency) = total;
    return Parsed(
      ParsedTxn(
        amountMinor: amount,
        currency: currency,
        direction: refund ? TxnDirection.credit : TxnDirection.debit,
        occurredAt: bodyTime(lower, input.receivedAt),
        mode: _mode(lower),
        confidence: 0.8,
        merchant: sender.name,
        accountHint: acct,
        // Only a bank RRN is safe to compare; order / gateway ids would
        // make dedup treat the bank alert as a different payment.
        reference: _rrn.firstMatch(lower)?.group(1),
      ),
    );
  }

  /// Amount and currency of a match of [_amt].
  (int, String)? _read(Match m) {
    final currency = currencyOfToken(m.group(1)!, home: sms.home);
    final a = parseMinor(m.group(2)!, digits: currencyDigits(currency));
    return a != null && a > 0 ? (a, currency) : null;
  }

  (int, String)? _totalOf(String l) {
    for (final re in _totals) {
      final m = re.firstMatch(l);
      if (m == null) continue;
      final r = _read(m);
      if (r != null) return r;
    }
    return null;
  }

  (int, String)? _refundAmountOf(String l) {
    final m = _refundAmount.firstMatch(l);
    return (m == null ? null : _read(m)) ?? _totalOf(l);
  }

  static PaymentMode _mode(String l) {
    if (RegExp(r'\bupi\b|@(ybl|okaxis|oksbi|okhdfcbank|okicici|paytm|ibl|axl|apl)\b').hasMatch(l)) {
      return PaymentMode.upi;
    }
    if (RegExp(r'\b(credit|debit) card\b|\bcard (ending|no|number)|\bvisa\b|mastercard|rupay|\bamex\b').hasMatch(l)) {
      return PaymentMode.card;
    }
    if (RegExp(r'net ?banking').hasMatch(l)) return PaymentMode.netbanking;
    if (RegExp(r'wallet|amazon pay balance|paytm balance|swiggy money|zomato money|ola money').hasMatch(l)) {
      return PaymentMode.wallet;
    }
    return PaymentMode.other;
  }

  /// Transaction time printed in the email, when it is plausible. Emails can
  /// arrive hours after the payment, which matters for dedup.
  static DateTime bodyTime(String lower, DateTime receivedAt) {
    for (final m in _dateTimes.expand((re) => re.allMatches(lower))) {
      final day = int.parse(m.namedGroup('d')!);
      final monRaw = m.namedGroup('mon')!;
      final idx = monRaw.length >= 3 ? _months.indexOf(monRaw.substring(0, 3)) : -1;
      final month = int.tryParse(monRaw) ?? idx + 1;
      var year = int.parse(m.namedGroup('y')!);
      if (year < 100) year += 2000;
      var hour = int.parse(m.namedGroup('h')!);
      final minute = int.parse(m.namedGroup('mi')!);
      final second = int.tryParse(m.namedGroup('s') ?? '') ?? 0;
      final ampm = m.namedGroup('ap');
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
      if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) continue;
      final t = DateTime(year, month, day, hour, minute, second);
      if (t.month != month) continue; // e.g. 31 Feb
      final lag = receivedAt.difference(t);
      if (lag >= const Duration(minutes: -5) && lag <= const Duration(days: 3)) return t;
    }
    return receivedAt;
  }
}
