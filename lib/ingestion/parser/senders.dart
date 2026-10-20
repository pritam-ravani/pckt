/// Indian DLT sender headers look like `VM-HDFCBK`, `AD-ICICIT-S`.
/// The 2-letter prefix is the operator/circle, the optional suffix is the
/// TRAI category: S = service, T = transactional, P = promotional, G = govt.
class SenderInfo {
  const SenderInfo({required this.header, required this.isPromotional, required this.isPhoneNumber, this.institution});

  final String header;
  final bool isPromotional;
  final bool isPhoneNumber;
  final String? institution;

  bool get isKnownFinancial => institution != null;
}

abstract final class Senders {
  static final _phone = RegExp(r'^\+?\d[\d\s-]{6,}$');
  static final _dlt = RegExp(r'^[A-Z]{2}-([A-Z0-9]{3,9})(?:-([SPTG]))?$');

  static SenderInfo parse(String raw) {
    final s = raw.trim().toUpperCase();
    if (_phone.hasMatch(s)) {
      return SenderInfo(header: s, isPromotional: false, isPhoneNumber: true);
    }
    final m = _dlt.firstMatch(s);
    final header = m?.group(1) ?? s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return SenderInfo(
      header: header,
      isPromotional: m?.group(2) == 'P',
      isPhoneNumber: false,
      institution: institutionFor(header),
    );
  }

  /// Header fragment → display name. Matched by `contains` so variants such
  /// as `HDFCBK`, `HDFCBN`, `HDFCCC` all resolve.
  static const _institutions = <String, String>{
    'HDFC': 'HDFC Bank',
    'ICICI': 'ICICI Bank',
    'SBICRD': 'SBI Card',
    'SBMCRD': 'SBI Card',
    'SBI': 'SBI',
    'CBSSBI': 'SBI',
    'AXIS': 'Axis Bank',
    'KOTAK': 'Kotak Bank',
    'KMBL': 'Kotak Bank',
    'IDFC': 'IDFC First',
    'YESB': 'Yes Bank',
    'INDUS': 'IndusInd Bank',
    'PNB': 'PNB',
    'BOIIND': 'Bank of India',
    'BOBTXN': 'Bank of Baroda',
    'BOBSMS': 'Bank of Baroda',
    'BARODA': 'Bank of Baroda',
    'CANBNK': 'Canara Bank',
    'UNIONB': 'Union Bank',
    'UBOI': 'Union Bank',
    'FEDBNK': 'Federal Bank',
    'FEDFIB': 'Federal Bank',
    'AUBANK': 'AU Bank',
    'AUBNK': 'AU Bank',
    'RBL': 'RBL Bank',
    'IOB': 'Indian Overseas Bank',
    'INDBNK': 'Indian Bank',
    'CENTBK': 'Central Bank',
    'IDBI': 'IDBI Bank',
    'DBS': 'DBS Bank',
    'SCBANK': 'Standard Chartered',
    'CITI': 'Citibank',
    'HSBC': 'HSBC',
    'AMEX': 'American Express',
    'PAYTM': 'Paytm',
    'PYTM': 'Paytm',
    'PHONPE': 'PhonePe',
    'AMAZON': 'Amazon Pay',
    'AMZPAY': 'Amazon Pay',
    'MOBIKW': 'MobiKwik',
    'ONECRD': 'OneCard',
    'JUPITR': 'Jupiter',
    'FIMONY': 'Fi',
    'SLCEIT': 'slice',
    'SLICE': 'slice',
    'AIRBNK': 'Airtel Payments Bank',
    'JIOPBS': 'Jio Payments Bank',
    'EQUTAS': 'Equitas Bank',
    'UJJIVN': 'Ujjivan Bank',
    'BANDHN': 'Bandhan Bank',
    'KVBANK': 'Karur Vysya Bank',
    'SIBSMS': 'South Indian Bank',
    'CSBBNK': 'CSB Bank',
    'DCBBNK': 'DCB Bank',
    'IMEIND': 'IME India',
  };

  static String? institutionFor(String header) {
    for (final e in _institutions.entries) {
      if (header.contains(e.key)) return e.value;
    }
    return null;
  }
}
