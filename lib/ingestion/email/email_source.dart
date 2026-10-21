import '../../data/db/tables.dart';
import '../parser/currency_text.dart';
import '../parser/email_senders.dart';
import '../parser/parsed_txn.dart';
import 'email_text.dart';

/// Mail providers the connect screen offers. [gmailOAuth] uses the Gmail
/// REST API; everything else is IMAP with an app password.
enum EmailProvider {
  gmail('Gmail', 'imap.gmail.com'),
  outlook('Outlook / Hotmail', 'outlook.office365.com'),
  yahoo('Yahoo Mail', 'imap.mail.yahoo.com'),
  zoho('Zoho Mail', 'imap.zoho.in'),
  other('Other (IMAP)', ''),
  gmailOAuth('Google account', '');

  const EmailProvider(this.label, this.defaultHost);
  final String label;
  final String defaultHost;

  bool get isImap => this != gmailOAuth;
}

/// Non-secret connection settings (persisted in SharedPreferences).
/// The password lives in [SecretStore] only.
class EmailAccount {
  const EmailAccount({required this.provider, required this.address, String? host, this.port = 993, this.ssl = true})
    : host = host ?? '';

  final EmailProvider provider;
  final String address;
  final String host;
  final int port;
  final bool ssl;

  String get effectiveHost => host.isNotEmpty ? host : provider.defaultHost;
}

class EmailConnectException implements Exception {
  const EmailConnectException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A mailbox the sync can read. IMAP and the Gmail API implement this; tests
/// use a fake.
abstract interface class EmailSource {
  /// Signs in and opens the inbox; throws [EmailConnectException] with a
  /// user-facing message on failure.
  Future<void> test();

  /// Likely-financial messages received on/after [since], newest [limit] at most.
  Future<List<RawInput>> fetchSince(DateTime since, {int limit = defaultEmailFetchLimit});
}

const defaultEmailFetchLimit = 400;

/// Client-side check used when the server could not narrow the search.
bool looksFinancialHeader(String from, String subject) {
  if (EmailSenders.parse(from).isKnown) return true;
  final s = subject.toLowerCase();
  return EmailSenders.searchSubjects.any((k) => s.contains(k.toLowerCase())) ||
      RegExp(r'(₹|\brs\.?\s?\d|\binr\b|spent|paid|alert)').hasMatch(s) ||
      RegExp('$currencyTokenPattern\\s?\\d').hasMatch(s);
}

/// Builds the pipeline input for one email.
RawInput emailToRawInput({
  required String externalId,
  required String from,
  required String subject,
  required DateTime date,
  String? plain,
  String? html,
}) => RawInput(
  source: SourceKind.email,
  externalId: externalId,
  sender: EmailSenders.addressOf(from),
  body: composeEmailBody(subject: subject, plain: plain, html: html),
  receivedAt: date,
);
