/// What kind of organisation sent an email. Banks, cards and wallets send
/// payment alerts; merchants send receipts that name who was paid.
enum EmailSenderKind { bank, card, wallet, ecommerce, food, ride, travel, subscription, utility, merchant }

class EmailSenderInfo {
  const EmailSenderInfo({required this.address, required this.domain, this.name, this.kind, this.smsHeader});

  final String address;
  final String domain;

  /// Institution (for banks / cards / wallets) or brand (for merchants).
  final String? name;
  final EmailSenderKind? kind;

  /// DLT-style header the SMS rules know (e.g. `HDFCBK`), so bank alert
  /// emails can be read with the same institution lookups as SMS.
  final String? smsHeader;

  bool get isKnown => kind != null;
  bool get isInstitution =>
      kind == EmailSenderKind.bank || kind == EmailSenderKind.card || kind == EmailSenderKind.wallet;
  bool get isMerchant => isKnown && !isInstitution;
}

class _Org {
  const _Org(this.pattern, this.name, this.kind, {this.sms});
  final String pattern;
  final String name;
  final EmailSenderKind kind;
  final String? sms;
}

/// Sender-domain directory for Indian banks, cards, UPI apps and the
/// merchants whose receipts are worth reading.
abstract final class EmailSenders {
  // Order matters: the first entry whose pattern occurs in the domain wins,
  // so specific ones (sbicard) come before generic ones (sbi).
  static const _orgs = <_Org>[
    // Cards
    _Org('sbicard', 'SBI Card', EmailSenderKind.card, sms: 'SBICRD'),
    _Org('americanexpress', 'American Express', EmailSenderKind.card, sms: 'AMEX'),
    _Org('aexp', 'American Express', EmailSenderKind.card, sms: 'AMEX'),
    _Org('getonecard', 'OneCard', EmailSenderKind.card, sms: 'ONECRD'),
    _Org('sliceit', 'slice', EmailSenderKind.card, sms: 'SLICE'),
    // Banks
    _Org('hdfcbank', 'HDFC Bank', EmailSenderKind.bank, sms: 'HDFCBK'),
    _Org('hdfc.bank', 'HDFC Bank', EmailSenderKind.bank, sms: 'HDFCBK'),
    _Org('icicibank', 'ICICI Bank', EmailSenderKind.bank, sms: 'ICICIB'),
    _Org('icici.bank', 'ICICI Bank', EmailSenderKind.bank, sms: 'ICICIB'),
    _Org('axisbank', 'Axis Bank', EmailSenderKind.bank, sms: 'AXISBK'),
    _Org('axis.bank', 'Axis Bank', EmailSenderKind.bank, sms: 'AXISBK'),
    _Org('onlinesbi', 'SBI', EmailSenderKind.bank, sms: 'SBIINB'),
    _Org('sbi.co.in', 'SBI', EmailSenderKind.bank, sms: 'SBIINB'),
    _Org('sbi.bank', 'SBI', EmailSenderKind.bank, sms: 'SBIINB'),
    _Org('kotak', 'Kotak Bank', EmailSenderKind.bank, sms: 'KOTAKB'),
    _Org('idfcfirstbank', 'IDFC First', EmailSenderKind.bank, sms: 'IDFCFB'),
    _Org('yesbank', 'Yes Bank', EmailSenderKind.bank, sms: 'YESBNK'),
    _Org('indusind', 'IndusInd Bank', EmailSenderKind.bank, sms: 'INDUSB'),
    _Org('pnb.co.in', 'PNB', EmailSenderKind.bank, sms: 'PNBSMS'),
    _Org('bankofbaroda', 'Bank of Baroda', EmailSenderKind.bank, sms: 'BOBTXN'),
    _Org('canarabank', 'Canara Bank', EmailSenderKind.bank, sms: 'CANBNK'),
    _Org('unionbankofindia', 'Union Bank', EmailSenderKind.bank, sms: 'UNIONB'),
    _Org('federalbank', 'Federal Bank', EmailSenderKind.bank, sms: 'FEDBNK'),
    _Org('aubank', 'AU Bank', EmailSenderKind.bank, sms: 'AUBANK'),
    _Org('rblbank', 'RBL Bank', EmailSenderKind.bank, sms: 'RBLBNK'),
    _Org('idbibank', 'IDBI Bank', EmailSenderKind.bank, sms: 'IDBIBK'),
    _Org('dbs.com', 'DBS Bank', EmailSenderKind.bank, sms: 'DBSBNK'),
    _Org('sc.com', 'Standard Chartered', EmailSenderKind.bank, sms: 'SCBANK'),
    _Org('citi', 'Citibank', EmailSenderKind.bank, sms: 'CITIBK'),
    _Org('hsbc', 'HSBC', EmailSenderKind.bank, sms: 'HSBCIN'),
    _Org('jupiter.money', 'Jupiter', EmailSenderKind.bank, sms: 'JUPITR'),
    _Org('fi.money', 'Fi', EmailSenderKind.bank, sms: 'FIMONY'),
    _Org('airtelbank', 'Airtel Payments Bank', EmailSenderKind.bank, sms: 'AIRBNK'),
    // Wallets / UPI apps
    _Org('paytm', 'Paytm', EmailSenderKind.wallet, sms: 'PAYTM'),
    _Org('phonepe', 'PhonePe', EmailSenderKind.wallet, sms: 'PHONPE'),
    _Org('mobikwik', 'MobiKwik', EmailSenderKind.wallet, sms: 'MOBIKW'),
    _Org('cred.club', 'CRED', EmailSenderKind.wallet),
    _Org('amazonpay', 'Amazon Pay', EmailSenderKind.wallet, sms: 'AMZPAY'),
    // Merchants
    _Org('amazon', 'Amazon', EmailSenderKind.ecommerce),
    _Org('flipkart', 'Flipkart', EmailSenderKind.ecommerce),
    _Org('myntra', 'Myntra', EmailSenderKind.ecommerce),
    _Org('ajio', 'AJIO', EmailSenderKind.ecommerce),
    _Org('nykaa', 'Nykaa', EmailSenderKind.ecommerce),
    _Org('meesho', 'Meesho', EmailSenderKind.ecommerce),
    _Org('tatacliq', 'Tata CLiQ', EmailSenderKind.ecommerce),
    _Org('croma', 'Croma', EmailSenderKind.ecommerce),
    _Org('decathlon', 'Decathlon', EmailSenderKind.ecommerce),
    _Org('swiggy', 'Swiggy', EmailSenderKind.food),
    _Org('zomato', 'Zomato', EmailSenderKind.food),
    _Org('blinkit', 'Blinkit', EmailSenderKind.food),
    _Org('zeptonow', 'Zepto', EmailSenderKind.food),
    _Org('zepto', 'Zepto', EmailSenderKind.food),
    _Org('bigbasket', 'BigBasket', EmailSenderKind.food),
    _Org('dominos', "Domino's", EmailSenderKind.food),
    _Org('uber', 'Uber', EmailSenderKind.ride),
    _Org('olacabs', 'Ola', EmailSenderKind.ride),
    _Org('rapido', 'Rapido', EmailSenderKind.ride),
    _Org('irctc', 'IRCTC', EmailSenderKind.travel),
    _Org('makemytrip', 'MakeMyTrip', EmailSenderKind.travel),
    _Org('goibibo', 'Goibibo', EmailSenderKind.travel),
    _Org('cleartrip', 'Cleartrip', EmailSenderKind.travel),
    _Org('ixigo', 'ixigo', EmailSenderKind.travel),
    _Org('redbus', 'redBus', EmailSenderKind.travel),
    _Org('goindigo', 'IndiGo', EmailSenderKind.travel),
    _Org('airindia', 'Air India', EmailSenderKind.travel),
    _Org('bookmyshow', 'BookMyShow', EmailSenderKind.travel),
    _Org('netflix', 'Netflix', EmailSenderKind.subscription),
    _Org('spotify', 'Spotify', EmailSenderKind.subscription),
    _Org('youtube', 'YouTube', EmailSenderKind.subscription),
    _Org('hotstar', 'JioHotstar', EmailSenderKind.subscription),
    _Org('apple.com', 'Apple', EmailSenderKind.subscription),
    _Org('google.com', 'Google', EmailSenderKind.subscription),
    _Org('airtel', 'Airtel', EmailSenderKind.utility),
    _Org('jio.com', 'Jio', EmailSenderKind.utility),
    _Org('tatapower', 'Tata Power', EmailSenderKind.utility),
    _Org('bescom', 'BESCOM', EmailSenderKind.utility),
  ];

  /// Domain fragments used to narrow the mailbox search server-side.
  static List<String> get searchDomains => [for (final o in _orgs) o.pattern];

  /// Subject words that catch alerts from senders not in the directory.
  static const searchSubjects = <String>[
    'debited',
    'credited',
    'transaction',
    'payment',
    'UPI',
    'spent',
    'receipt',
    'order',
    'invoice',
  ];

  static final _addr = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');

  /// Accepts a bare address or a `Name <address>` header.
  static String addressOf(String from) => (_addr.firstMatch(from)?.group(0) ?? from).trim().toLowerCase();

  static EmailSenderInfo parse(String from) {
    final address = addressOf(from);
    final domain = address.contains('@') ? address.split('@').last : address;
    for (final o in _orgs) {
      if (domain.contains(o.pattern)) {
        return EmailSenderInfo(address: address, domain: domain, name: o.name, kind: o.kind, smsHeader: o.sms);
      }
    }
    return EmailSenderInfo(address: address, domain: domain);
  }

  /// Whether [from] is a merchant whose receipts carry an authoritative
  /// merchant name (better than whatever a bank alert called it).
  static bool isMerchant(String from) => parse(from).isMerchant;
}
