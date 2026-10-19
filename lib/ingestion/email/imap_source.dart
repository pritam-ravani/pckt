import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:enough_mail/enough_mail.dart';

import '../parser/email_senders.dart';
import '../parser/parsed_txn.dart';
import 'email_source.dart';

/// Reads the INBOX over IMAP with an app password. All network and MIME
/// work runs in a background isolate so big first imports don't jank the UI.
class ImapEmailSource implements EmailSource {
  ImapEmailSource(this.account, this.password);

  final EmailAccount account;
  final String password;

  @override
  Future<void> test() {
    final a = account, p = password;
    return Isolate.run(() async {
      final client = await _login(a, p);
      try {
        await client.selectInbox();
      } finally {
        await _close(client);
      }
    });
  }

  @override
  Future<List<RawInput>> fetchSince(DateTime since, {int limit = defaultEmailFetchLimit}) {
    final a = account, p = password;
    return Isolate.run(() => _fetch(a, p, since, limit));
  }
}

Future<ImapClient> _login(EmailAccount a, String password) async {
  final host = a.effectiveHost;
  if (host.isEmpty) throw const EmailConnectException('Enter the IMAP server address');
  final client = ImapClient(defaultResponseTimeout: const Duration(seconds: 90));
  try {
    await client.connectToServer(host, a.port, isSecure: a.ssl, timeout: const Duration(seconds: 20));
    if (!a.ssl) await client.startTls();
  } on SocketException catch (_) {
    throw EmailConnectException("Couldn't reach $host:${a.port}. Check the server and your connection.");
  } on HandshakeException catch (_) {
    throw EmailConnectException('Secure connection to $host failed. Check the port / SSL setting.');
  } on TimeoutException catch (_) {
    throw EmailConnectException('$host:${a.port} did not respond in time.');
  } catch (e) {
    throw EmailConnectException('Could not connect to $host: ${_short(e)}');
  }
  try {
    await client.login(a.address, password);
  } catch (e) {
    await _close(client);
    throw EmailConnectException(_loginHelp(a.provider, e));
  }
  return client;
}

String _loginHelp(EmailProvider p, Object e) {
  final detail = e is ImapException ? (e.message ?? '') : _short(e);
  final hint = switch (p) {
    EmailProvider.gmail => 'Gmail needs an App Password (not your normal password). Turn on 2-Step Verification, then create one at myaccount.google.com/apppasswords.',
    EmailProvider.yahoo => 'Yahoo needs an app password: Account security → Generate app password.',
    EmailProvider.outlook => 'Microsoft may block password sign-in for IMAP on personal Outlook.com accounts. Try an app password, or forward bank alerts to a Gmail/Zoho mailbox.',
    EmailProvider.zoho => 'Enable IMAP access in Zoho Mail settings, and use an app-specific password if 2FA is on. Non-India accounts use imap.zoho.com.',
    _ => 'Check the address, password and server settings.',
  };
  return 'Sign-in failed${detail.isEmpty ? '' : ' ($detail)'}. $hint';
}

String _short(Object e) {
  final s = e.toString();
  return s.length > 140 ? '${s.substring(0, 140)}…' : s;
}

Future<void> _close(ImapClient c) async {
  try {
    await c.logout().timeout(const Duration(seconds: 5));
  } catch (_) {}
  try {
    await c.disconnect();
  } catch (_) {}
}

const _imapMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String imapDate(DateTime d) => '${d.day}-${_imapMonths[d.month - 1]}-${d.year}';

/// `OR a OR b c` — IMAP's OR is binary and prefix.
String imapOr(List<String> keys) => keys.length == 1 ? keys.first : 'OR ${keys.first} ${imapOr(keys.sublist(1))}';

/// SINCE + (known sender domains OR money-ish subject words).
String imapSearchCriteria(DateTime since) {
  final keys = [
    for (final d in EmailSenders.searchDomains) 'FROM "$d"',
    for (final s in EmailSenders.searchSubjects) 'SUBJECT "$s"',
  ];
  return 'SINCE ${imapDate(since)} ${imapOr(keys)}';
}

Future<List<RawInput>> _fetch(EmailAccount a, String password, DateTime since, int limit) async {
  final client = await _login(a, password);
  try {
    await client.selectInbox();
    var uids = <int>[];
    try {
      final r = await client.uidSearchMessages(searchCriteria: imapSearchCriteria(since));
      uids = r.matchingSequence?.toList() ?? [];
    } catch (_) {
      // Server refused the long OR query: narrow by date only, then filter
      // on headers (cheap) before downloading bodies.
      final r = await client.uidSearchMessages(searchCriteria: 'SINCE ${imapDate(since)}');
      uids = await _filterByHeaders(client, r.matchingSequence?.toList() ?? [], limit);
    }
    uids.sort();
    if (uids.length > limit) uids = uids.sublist(uids.length - limit);

    final out = <RawInput>[];
    for (var i = 0; i < uids.length; i += 20) {
      final chunk = uids.sublist(i, (i + 20).clamp(0, uids.length));
      final res = await client.uidFetchMessages(MessageSequence.fromIds(chunk, isUid: true), '(UID BODY.PEEK[])');
      for (final m in res.messages) {
        final input = _toInput(m);
        if (input != null) out.add(input);
      }
    }
    return out;
  } finally {
    await _close(client);
  }
}

Future<List<int>> _filterByHeaders(ImapClient client, List<int> uids, int limit) async {
  uids.sort();
  // Look at no more than ~10x the body cap of the newest messages.
  final recent = uids.length > limit * 10 ? uids.sublist(uids.length - limit * 10) : uids;
  final keep = <int>[];
  for (var i = 0; i < recent.length; i += 200) {
    final chunk = recent.sublist(i, (i + 200).clamp(0, recent.length));
    final res = await client.uidFetchMessages(MessageSequence.fromIds(chunk, isUid: true), '(UID ENVELOPE)');
    for (final m in res.messages) {
      final from = m.from?.firstOrNull?.email ?? m.fromEmail ?? '';
      if (m.uid != null && looksFinancialHeader(from, m.decodeSubject() ?? '')) keep.add(m.uid!);
    }
  }
  return keep;
}

RawInput? _toInput(MimeMessage m) {
  final from = m.from?.firstOrNull?.email ?? m.fromEmail;
  if (from == null) return null;
  final id = m.getHeaderValue('message-id')?.trim();
  return emailToRawInput(
    externalId: id != null && id.isNotEmpty ? id : 'imap-uid:${m.uid}',
    from: from,
    subject: m.decodeSubject() ?? '',
    date: (m.decodeDate() ?? DateTime.now()).toLocal(),
    plain: m.decodeTextPlainPart(),
    html: m.decodeTextHtmlPart(),
  );
}
