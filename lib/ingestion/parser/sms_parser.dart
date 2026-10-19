import '../../data/db/tables.dart';
import 'parsed_txn.dart';
import 'senders.dart';
import 'text_utils.dart';

/// Rule-based parser for Indian bank / card / UPI alerts.
///
/// Philosophy: be strict about *what is a transaction* (ignore OTPs,
/// reminders, failures, promos) and lenient about *how it is phrased*.
/// Anything that looks financial but cannot be parsed is returned as
/// [Unparsed] so the LLM fallback can take a look later.
class SmsParser {
  const SmsParser();

  // ---- exclusion rules, checked in order --------------------------------

  static final _otp = RegExp(r'\b(otp|one[- ]time password|verification code|passcode)\b');
  static final _future = RegExp(
    r'(will be debited|to be debited|will be auto[- ]?debited|is scheduled|scheduled for|'
    r'due on|is due|due date|payment due|reminder|upcoming|would be debited|shall be debited)',
  );
  static final _request = RegExp(
    r'(has requested|requested money|collect request|payment request|requesting|request of rs|'
    r'sent you a request)',
  );
  static final _failed = RegExp(
    r'\b(failed|declined|unsuccessful|could not be (processed|completed)|insufficient (funds|balance)|'
    r'not been processed|rejected)\b',
  );
  static final _statement = RegExp(
    r'(total (amount )?due|min(imum)?\.? (amount )?due|statement (is )?(generated|ready)|'
    r'e-?statement|bill (is )?generated|outstanding of)',
  );
  static final _promo = RegExp(
    r"(offer|cashback (of )?up ?to|get up ?to|win |pre-?approved|apply now|click here|limited period|"
    r"loan of up ?to|lowest emi|congratulations|eligible for|t&c|hurry|discount)",
  );
  static final _balanceOnly = RegExp(r'(available balance|avl\.? bal|balance (in|of|is)|bal(ance)? enquiry)');
  static final _mandateSetup = RegExp(
    r'(mandate (is )?(created|registered|set ?up|successfully)|autopay (is )?(set ?up|registered|activated|enabled)|'
    r'e-?mandate (has been )?registered|si (has been )?registered)',
  );

  // ---- extraction -------------------------------------------------------

  static final _currencyAmount = RegExp(r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)');
  static final _verbAmount = RegExp(
    r'(?:debited|credited|deducted|withdrawn|spent|paid|sent|received)\s+(?:by|for|with|of)?\s*'
    r'(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  );

  static final _debitWords = RegExp(
    r'\b(debited|debit|spent|paid|sent|withdrawn|withdrawal|purchase|purchased|charged|deducted|'
    r'transferred to|txn of|transaction of|dr\b)',
  );
  static final _creditWords = RegExp(
    r'\b(credited|credit(?! card)|received|deposited|refund(ed)?|reversed|reversal|cashback|cr\b)',
  );

  static final _acct = RegExp(
    r'(?:a/?c|acct|account|card|ac)\s*(?:no\.?|number)?\s*(?:ending(?:\s*(?:with|in))?)?\s*[:\-]?\s*'
    r'(?:[x*.#]+\s*)?(\d{3,6})\b',
  );
  static final _acctXX = RegExp(r'\b[x*]{2,}(\d{3,6})\b');

  static final _refKeyed = RegExp(
    r'(?:upi\s*(?:ref(?:erence)?|txn|transaction)?\s*(?:no\.?|id|#)?|ref(?:erence)?\s*(?:no\.?|number|id|#)?|'
    r'rrn|utr\s*(?:no\.?)?|txn\s*(?:id|no\.?)|imps\s*(?:ref)?\s*(?:no\.?)?)\s*[:\-.]?\s*([a-z0-9]{10,22})\b',
  );
  static final _upiPath = RegExp(r'upi/(?:p2[ma]|cr|dr)/(\d{9,16})/([^/\n]+)', caseSensitive: false);
  static final _bare12 = RegExp(r'(?<![\d*x])(\d{12})(?!\d)');

  static final _vpa = RegExp(r'\b([a-z0-9][a-z0-9.\-_]{1,63}@[a-z][a-z0-9]{1,30})\b', caseSensitive: false);

  /// Ordered, most specific first. Group 1 is the counterparty.
  static final _debitParty = <RegExp>[
    RegExp(r';\s*([^.;\n]{2,40}?)\s+credited', caseSensitive: false), // ICICI: "...; SWIGGY credited."
    RegExp(r'\btrf to\s+(.{2,40}?)\s+(?:ref|refno|upi)', caseSensitive: false), // SBI
    RegExp(
      r'\bto\b\s*:?\s*(?:vpa\s+)?(.{2,50}?)(?=\s+(?:on|via|ref|upi|using|from|for|dt|date|avl|txn|at|umrn)\b|[,(\n]|\.(?=\s|$)|$)',
      caseSensitive: false,
    ),
    RegExp(r'\bat\s+(.{2,40}?)(?=\s+(?:on|via|ref|using|txn|avl|for)\b|[,(\n]|\.(?=\s|$)|$)', caseSensitive: false),
    RegExp(r'\d{2}[-/ ]?\w{3}[-/ ]?\d{2,4}\s+on\s+(.{2,40}?)(?=[.\n]|\s+avl|$)', caseSensitive: false), // ICICI card
    RegExp(r'\btowards\s+(.{2,40}?)(?=[.,\n]|\s+(?:on|ref|upi|umrn)\b|$)', caseSensitive: false),
  ];

  static final _creditParty = <RegExp>[
    RegExp(r'\bfor (?:imps|neft|rtgs)\s*-+\s*([^-\n]{2,40}?)\s*-', caseSensitive: false), // HDFC "For IMPS -NAME-"
    RegExp(
      r'\bfrom\b\s*:?\s*(?:vpa\s+)?(.{2,50}?)(?=\s+(?:on|via|ref|upi|using|to|into|in|dt|date|avl|txn|umrn)\b|[,(\n]|\.(?=\s|$)|$)',
      caseSensitive: false,
    ),
    RegExp(
      r'\bby\s+(?!neft|imps|rtgs|upi|transfer|cash|cheque)(.{2,40}?)(?=\s+(?:on|via|ref|upi|using)\b|[,(\n]|\.(?=\s|$)|$)',
      caseSensitive: false,
    ),
  ];

  static final _partyNoise = RegExp(
    r'^(your|you|a/?c|ac|acct|account|card|bank|the|self|xx|\*|rs|inr|₹)\b|'
    r'\b(a/?c|acct|account|bank card|credit card|debit card)\b|^\d+$|^[x*\d\s]+$',
    caseSensitive: false,
  );

  ParseResult parse(RawInput input) {
    final sender = Senders.parse(input.sender);
    final text = normalizeSpace(input.body);
    final lower = text.toLowerCase();

    if (sender.isPhoneNumber) return const Ignored('Personal message');
    if (_otp.hasMatch(lower)) return const Ignored('OTP');

    final hasDebitVerb = _debitWords.hasMatch(lower);
    final hasCreditVerb = _creditWords.hasMatch(lower);
    final hasAmount = _currencyAmount.hasMatch(lower) || _verbAmount.hasMatch(lower);
    final looksFinancial = hasAmount && (hasDebitVerb || hasCreditVerb);

    if (_failed.hasMatch(lower)) return const Ignored('Failed / declined');
    if (_future.hasMatch(lower)) return const Ignored('Reminder / scheduled');
    if (_request.hasMatch(lower)) return const Ignored('Payment request');
    if (_mandateSetup.hasMatch(lower)) return const Ignored('Mandate setup');
    if (_statement.hasMatch(lower) && !_strongVerb(lower)) return const Ignored('Statement / bill');
    if (sender.isPromotional) return const Ignored('Promotional');
    if (_promo.hasMatch(lower) && !_strongVerb(lower)) return const Ignored('Promotional');
    if (!hasAmount) return const Ignored('No amount');
    if (!looksFinancial) {
      return _balanceOnly.hasMatch(lower) ? const Ignored('Balance alert') : const Ignored('Not a transaction');
    }

    final amount = _extractAmount(lower);
    if (amount == null || amount <= 0) return const Unparsed('Could not read amount');

    final direction = _direction(lower);
    if (direction == null) return const Unparsed('Could not tell debit from credit');

    final reference = _reference(lower);
    final accountHint = _accountHint(lower);
    final vpa = _vpa.firstMatch(text)?.group(1)?.toLowerCase();
    final cashDeposit = lower.contains('cash deposit');
    final mode = cashDeposit ? PaymentMode.cash : _mode(lower, vpa);
    var (merchant, counterparty, p2p) = cashDeposit
        ? ('Cash Deposit', null, false)
        : _party(text, lower, direction, vpa);
    // Card and ATM rails only ever pay merchants.
    if (mode == PaymentMode.card || mode == PaymentMode.atm) p2p = false;

    var confidence = 0.45;
    if (sender.isKnownFinancial) confidence += 0.25;
    if (reference != null) confidence += 0.15;
    if (accountHint != null) confidence += 0.1;
    if (merchant != null) confidence += 0.05;
    if (!sender.isKnownFinancial && accountHint == null && reference == null) confidence -= 0.15;

    return Parsed(
      ParsedTxn(
        amountMinor: amount,
        direction: direction,
        occurredAt: input.receivedAt,
        mode: mode,
        confidence: confidence.clamp(0, 1).toDouble(),
        merchant: merchant,
        counterparty: counterparty ?? vpa,
        accountHint: accountHint,
        reference: reference,
        institution: sender.institution,
        isPersonToPerson: p2p,
        transferHint: _transferHint(lower, direction),
      ),
    );
  }

  static bool _strongVerb(String l) => RegExp(r'\b(debited|credited|spent|withdrawn)\b').hasMatch(l);

  /// First amount that is not a balance / limit figure.
  static int? _extractAmount(String l) {
    final v = _verbAmount.firstMatch(l);
    if (v != null && !_isBalanceContext(l, v.start)) {
      final a = parseMinor(v.group(1)!);
      if (a != null && a > 0) return a;
    }
    for (final m in _currencyAmount.allMatches(l)) {
      if (_isBalanceContext(l, m.start)) continue;
      final a = parseMinor(m.group(1)!);
      if (a != null && a > 0) return a;
    }
    return null;
  }

  static bool _isBalanceContext(String l, int at) {
    final before = l.substring((at - 28).clamp(0, at), at);
    return RegExp(r'(bal(ance)?|limit|avl|available|outstanding|due)[\s:.\-]*(is\s*)?$').hasMatch(before) ||
        RegExp(r'(bal(ance)?|limit)\b').hasMatch(before.split(RegExp(r'[.;]')).last);
  }

  static TxnDirection? _direction(String l) {
    // Remove phrases that contain direction words but aren't directions.
    final cleaned = l
        .replaceAll(RegExp(r'credit card|debit card|credit limit|cr\.? card|card ending'), ' ')
        .replaceAll(RegExp(r'if not (done|you)[^.]*'), ' ');
    final d = _debitWords.firstMatch(cleaned);
    final c = _creditWords.firstMatch(cleaned);
    if (d == null && c == null) return null;
    if (d == null) return TxnDirection.credit;
    if (c == null) return TxnDirection.debit;
    // Both present: e.g. "debited from A and credited to B" — the earliest wins,
    // except a refund/reversal which is always a credit to us.
    if (RegExp(r'\b(refund(ed)?|reversed|reversal)\b').hasMatch(cleaned)) return TxnDirection.credit;
    return d.start <= c.start ? TxnDirection.debit : TxnDirection.credit;
  }

  static String? _reference(String l) {
    final path = _upiPath.firstMatch(l);
    if (path != null) return path.group(1);
    for (final m in _refKeyed.allMatches(l)) {
      final r = m.group(1)!;
      if (RegExp(r'\d').allMatches(r).length >= 6) return r.toUpperCase();
    }
    // A lone 12-digit number in a UPI message is almost always the RRN.
    if (l.contains('upi')) {
      final b = _bare12.firstMatch(l);
      if (b != null) return b.group(1);
    }
    return null;
  }

  static String? _accountHint(String l) {
    final m = _acct.firstMatch(l) ?? _acctXX.firstMatch(l);
    if (m == null) return null;
    final digits = m.group(1)!;
    return digits.length > 4 ? digits.substring(digits.length - 4) : digits;
  }

  static PaymentMode _mode(String l, String? vpa) {
    if (l.contains('atm') || RegExp(r'cash withdrawal|withdrawn').hasMatch(l)) return PaymentMode.atm;
    if (l.contains('upi') || vpa != null) return PaymentMode.upi;
    if (l.contains('imps')) return PaymentMode.imps;
    if (l.contains('neft')) return PaymentMode.neft;
    if (l.contains('rtgs')) return PaymentMode.rtgs;
    if (RegExp(r'\bcard\b').hasMatch(l) || RegExp(r'\bpos\b').hasMatch(l)) return PaymentMode.card;
    if (RegExp(r'net ?banking|\binb\b').hasMatch(l)) return PaymentMode.netbanking;
    if (l.contains('wallet')) return PaymentMode.wallet;
    return PaymentMode.other;
  }

  /// Returns (merchant display name, raw counterparty, isP2P).
  static (String?, String?, bool) _party(String text, String l, TxnDirection dir, String? vpa) {
    final p2p = RegExp(r'upi/p2a/').hasMatch(l);
    final path = _upiPath.firstMatch(text);
    if (path != null) {
      final name = path.group(2)!;
      return (cleanMerchant(name), vpa ?? name.trim(), p2p);
    }

    final patterns = dir == TxnDirection.debit ? _debitParty : _creditParty;
    for (final re in patterns) {
      for (final m in re.allMatches(text)) {
        final raw = m.group(1)!.trim();
        if (_partyNoise.hasMatch(raw)) continue;
        final cleaned = cleanMerchant(raw);
        if (cleaned == null) continue;
        return (cleaned, raw, _looksLikePerson(raw, vpa));
      }
    }
    if (vpa != null) return (merchantFromVpa(vpa), vpa, false);
    return (null, null, false);
  }

  static bool _looksLikePerson(String raw, String? vpa) {
    if (vpa != null && RegExp(r'^\d{10}@').hasMatch(vpa)) return true;
    final words = raw.trim().split(RegExp(r'\s+'));
    return words.length >= 2 &&
        words.length <= 4 &&
        words.every((w) => RegExp(r'^[A-Za-z.]+$').hasMatch(w)) &&
        !RegExp(
          r'(pvt|ltd|limited|store|services|india|technologies|retail|foods|mart|enterprises)',
          caseSensitive: false,
        ).hasMatch(raw);
  }

  static bool _transferHint(String l, TxnDirection dir) =>
      RegExp(r'\b(to self|self transfer|own account|between your accounts)\b').hasMatch(l) ||
      RegExp(
        r'(payment (of .{0,25})?(has been )?received (on|towards|for|in) your .{0,25}card|'
        r'credit card (bill )?payment|towards your card)',
      ).hasMatch(l);
}
