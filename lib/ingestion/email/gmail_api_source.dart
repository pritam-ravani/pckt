import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../parser/email_senders.dart';
import '../parser/parsed_txn.dart';
import 'email_source.dart';

/// OAuth "Web application" client id from Google Cloud Console, passed at
/// build time: `--dart-define=GOOGLE_OAUTH_CLIENT_ID=1234-abc.apps.googleusercontent.com`.
/// Android's Credential Manager needs it as the *server* client id; the
/// Android client (package + SHA-1) must exist in the same project.
/// See README → "Gmail sign-in (OAuth)".
const googleOAuthClientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

const gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';

/// Wraps google_sign_in v7 (initialize once → authenticate → authorize scopes).
class GoogleGmailAuth {
  GoogleGmailAuth._();
  static final instance = GoogleGmailAuth._();

  bool get isConfigured => googleOAuthClientId.isNotEmpty && Platform.isAndroid;

  Future<void>? _init;

  Future<void> _ensureInit() => _init ??= GoogleSignIn.instance.initialize(serverClientId: googleOAuthClientId);

  /// Interactive sign-in + Gmail consent. Returns the account's address.
  Future<String> signIn() async {
    if (!isConfigured) throw const EmailConnectException('Google sign-in is not configured in this build');
    await _ensureInit();
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const [gmailReadonlyScope]);
      await account.authorizationClient.authorizeScopes(const [gmailReadonlyScope]);
      return account.email;
    } on GoogleSignInException catch (e) {
      throw EmailConnectException(
        e.code == GoogleSignInExceptionCode.canceled
            ? 'Sign-in cancelled'
            : 'Google sign-in failed: ${e.description ?? e.code.name}',
      );
    }
  }

  /// Access token for background syncs. Never shows UI; throws when the user
  /// has to sign in again.
  Future<String> accessToken() async {
    if (!isConfigured) throw const EmailConnectException('Google sign-in is not configured in this build');
    await _ensureInit();
    final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    final authz = await account?.authorizationClient.authorizationForScopes(const [gmailReadonlyScope]);
    if (authz == null) throw const EmailConnectException('Google access expired — reconnect Gmail in Settings');
    return authz.accessToken;
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    await _ensureInit();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
  }
}

/// Reads mail through the Gmail REST API (`gmail.readonly`).
class GmailApiSource implements EmailSource {
  GmailApiSource({Future<String> Function()? token}) : _token = token ?? GoogleGmailAuth.instance.accessToken;

  final Future<String> Function() _token;

  @override
  Future<void> test() async {
    final token = await _token();
    final r = await http.get(Uri.parse('$_base/profile'), headers: {'Authorization': 'Bearer $token'});
    if (r.statusCode != 200) throw EmailConnectException('Gmail API error ${r.statusCode}');
  }

  @override
  Future<List<RawInput>> fetchSince(DateTime since, {int limit = defaultEmailFetchLimit}) async {
    final token = await _token();
    return Isolate.run(() => _gmailFetch(token, since, limit));
  }
}

const _base = 'https://gmail.googleapis.com/gmail/v1/users/me';

/// Gmail search syntax equivalent of the IMAP query.
String gmailQuery(DateTime since) {
  final d = since.subtract(const Duration(days: 1)); // `after:` is exclusive and in PST
  final from = EmailSenders.searchDomains.join(' OR ');
  final subj = EmailSenders.searchSubjects.join(' OR ');
  return 'after:${d.year}/${d.month}/${d.day} {from:($from) subject:($subj)} -in:chats';
}

Future<List<RawInput>> _gmailFetch(String token, DateTime since, int limit) async {
  final client = http.Client();
  final headers = {'Authorization': 'Bearer $token'};
  try {
    final ids = <String>[];
    String? page;
    do {
      final uri = Uri.parse('$_base/messages').replace(
        queryParameters: {
          'q': gmailQuery(since),
          'maxResults': '${(limit - ids.length).clamp(1, 500)}',
          'pageToken': ?page,
        },
      );
      final r = await client.get(uri, headers: headers);
      if (r.statusCode == 401) throw const EmailConnectException('Google access expired — reconnect Gmail in Settings');
      if (r.statusCode != 200) throw EmailConnectException('Gmail API error ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      for (final m in (j['messages'] as List? ?? const [])) {
        ids.add((m as Map)['id'] as String);
      }
      page = j['nextPageToken'] as String?;
    } while (page != null && ids.length < limit);

    final out = <RawInput>[];
    // Small parallel batches: quick without tripping per-user rate limits.
    for (var i = 0; i < ids.length; i += 10) {
      final batch = ids.sublist(i, (i + 10).clamp(0, ids.length));
      final results = await Future.wait(
        batch.map((id) async {
          final r = await client.get(Uri.parse('$_base/messages/$id?format=full'), headers: headers);
          return r.statusCode == 200 ? gmailMessageToInput(jsonDecode(r.body) as Map<String, dynamic>) : null;
        }),
      );
      out.addAll(results.whereType<RawInput>());
    }
    return out;
  } finally {
    client.close();
  }
}

/// Converts a Gmail API `format=full` message into a pipeline input.
RawInput? gmailMessageToInput(Map<String, dynamic> msg) {
  final payload = msg['payload'] as Map<String, dynamic>?;
  if (payload == null) return null;
  final headers = {
    for (final h in (payload['headers'] as List? ?? const []))
      ((h as Map)['name'] as String).toLowerCase(): h['value'] as String,
  };
  final from = headers['from'];
  if (from == null) return null;

  String? plain, html;
  void walk(Map<String, dynamic> part) {
    final mime = (part['mimeType'] as String? ?? '').toLowerCase();
    final data = (part['body'] as Map?)?['data'] as String?;
    if (data != null && (mime == 'text/plain' || mime == 'text/html')) {
      final text = _b64url(data);
      if (mime == 'text/plain') {
        plain ??= text;
      } else {
        html ??= text;
      }
    }
    for (final p in (part['parts'] as List? ?? const [])) {
      walk(p as Map<String, dynamic>);
    }
  }

  walk(payload);
  final internal = int.tryParse('${msg['internalDate'] ?? ''}');
  final messageId = headers['message-id']?.trim();
  return emailToRawInput(
    externalId: messageId != null && messageId.isNotEmpty ? messageId : 'gmail:${msg['id']}',
    from: from,
    subject: headers['subject'] ?? '',
    date: internal != null ? DateTime.fromMillisecondsSinceEpoch(internal) : DateTime.now(),
    plain: plain,
    html: html,
  );
}

String _b64url(String data) {
  try {
    return utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);
  } catch (_) {
    return '';
  }
}
