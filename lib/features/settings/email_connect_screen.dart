import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../ingestion/email/email_source.dart';
import '../../ingestion/email/email_sync.dart';
import '../../ingestion/email/gmail_api_source.dart';
import '../../ui/widgets.dart';

/// Connect a mailbox: provider picker, app-password how-to, server
/// settings, test connection and import range.
class EmailConnectScreen extends ConsumerStatefulWidget {
  const EmailConnectScreen({super.key});

  @override
  ConsumerState<EmailConnectScreen> createState() => _EmailConnectScreenState();
}

class _EmailConnectScreenState extends ConsumerState<EmailConnectScreen> {
  static const _imapProviders = [
    EmailProvider.gmail,
    EmailProvider.outlook,
    EmailProvider.yahoo,
    EmailProvider.zoho,
    EmailProvider.other,
  ];

  var _provider = EmailProvider.gmail;
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _host = TextEditingController(text: EmailProvider.gmail.defaultHost);
  final _port = TextEditingController(text: '993');
  var _ssl = true;
  var _months = 3;
  var _obscure = true;
  var _busy = false;

  /// (ok, message) from the last test / connect attempt.
  (bool, String)? _result;

  @override
  void initState() {
    super.initState();
    final previous = ref.read(emailSyncProvider).account;
    if (previous != null && previous.provider.isImap) {
      _provider = previous.provider;
      _address.text = previous.address;
      _host.text = previous.effectiveHost;
      _port.text = '${previous.port}';
      _ssl = previous.ssl;
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _pick(EmailProvider p) => setState(() {
    _provider = p;
    _host.text = p.defaultHost;
    _port.text = '993';
    _ssl = true;
    _result = null;
  });

  EmailAccount get _account => EmailAccount(
    provider: _provider,
    address: _address.text.trim(),
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 993,
    ssl: _ssl,
  );

  /// App passwords are shown in groups ("abcd efgh ijkl mnop"); the spaces
  /// aren't part of them.
  String get _secret => _provider == EmailProvider.gmail || _provider == EmailProvider.yahoo
      ? _password.text.replaceAll(RegExp(r'\s'), '')
      : _password.text;

  String? _validate() {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_address.text.trim())) return 'Enter your email address';
    if (_password.text.isEmpty) return 'Enter the app password';
    if (_host.text.trim().isEmpty) return 'Enter the IMAP server';
    return null;
  }

  Future<void> _test() async {
    final invalid = _validate();
    if (invalid != null) return setState(() => _result = (false, invalid));
    setState(() => _busy = true);
    final error = await ref.read(emailSyncProvider.notifier).testConnection(_account, _secret);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = error == null ? (true, 'Connected — inbox found.') : (false, error);
    });
  }

  Future<void> _connect() async {
    final invalid = _validate();
    if (invalid != null) return setState(() => _result = (false, invalid));
    setState(() => _busy = true);
    final ctrl = ref.read(emailSyncProvider.notifier);
    final ok = await ctrl.connect(_account, password: _secret, months: _months);
    if (!mounted) return;
    if (ok) return _done();
    setState(() {
      _busy = false;
      _result = (false, ref.read(emailSyncProvider).error ?? 'Could not connect');
    });
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    final ok = await ref.read(emailSyncProvider.notifier).connectGoogle(months: _months);
    if (!mounted) return;
    if (ok) return _done();
    setState(() {
      _busy = false;
      _result = (false, ref.read(emailSyncProvider).error ?? 'Google sign-in failed');
    });
  }

  void _done() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Email connected — importing in the background')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final googleReady = GoogleGmailAuth.instance.isConfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('Connect email')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(PhosphorIconsFill.shieldCheck, color: Palette.mint),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Pckt only reads messages that look like bank alerts or receipts, on this phone. '
                    'Your password stays in the Android keystore and is only sent to your mail server.',
                    style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          if (googleReady) ...[
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Gmail', style: context.text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in with Google and allow read-only access. No app password needed.',
                    style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: _busy ? null : _google,
                    icon: const Icon(PhosphorIconsBold.googleLogo, size: 18),
                    label: const Text('Sign in with Google'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'or connect any mailbox with an app password',
                textAlign: TextAlign.center,
                style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
          ] else
            const SizedBox(height: 16),
          const SectionHeader('Provider'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _imapProviders)
                ChoiceChip(label: Text(p.label), selected: _provider == p, onSelected: (_) => _pick(p)),
            ],
          ),
          const SizedBox(height: 12),
          _HowTo(provider: _provider, googleReady: googleReady),
          const SizedBox(height: 20),
          const SectionHeader('Account'),
          TextField(
            controller: _address,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(PhosphorIconsBold.at)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: _provider == EmailProvider.other ? 'Password' : 'App password',
              prefixIcon: const Icon(PhosphorIconsBold.key),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? PhosphorIconsBold.eye : PhosphorIconsBold.eyeSlash),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey(_provider),
              initiallyExpanded: _provider == EmailProvider.other,
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(PhosphorIconsRegular.hardDrives),
              title: const Text('Server settings'),
              subtitle: Text(
                '${_host.text.isEmpty ? 'not set' : _host.text}:${_port.text} · ${_ssl ? 'SSL' : 'STARTTLS'}',
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                TextField(
                  controller: _host,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'IMAP server', hintText: 'imap.example.com'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('SSL/TLS'),
                        value: _ssl,
                        onChanged: (v) => setState(() {
                          _ssl = v;
                          _port.text = v ? '993' : '143';
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader('Import history from'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 mo')),
              ButtonSegment(value: 3, label: Text('3 mo')),
              ButtonSegment(value: 6, label: Text('6 mo')),
              ButtonSegment(value: 12, label: Text('12 mo')),
            ],
            selected: {_months},
            onSelectionChanged: (s) => setState(() => _months = s.first),
          ),
          if (_result != null) ...[const SizedBox(height: 16), _ResultBanner(ok: _result!.$1, message: _result!.$2)],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _test,
                  icon: const Icon(PhosphorIconsBold.plugsConnected, size: 18),
                  label: const Text('Test'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                      : const Text('Connect & import'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.ok, required this.message});
  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = ok ? Palette.mint : Palette.coral;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.warningCircle, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}

/// Short, provider-specific steps for creating an app password.
class _HowTo extends StatelessWidget {
  const _HowTo({required this.provider, required this.googleReady});
  final EmailProvider provider;
  final bool googleReady;

  @override
  Widget build(BuildContext context) {
    final (title, steps, note) = switch (provider) {
      EmailProvider.gmail => (
        'Gmail needs an App Password',
        const [
          'Turn on 2-Step Verification: myaccount.google.com/security',
          'Open myaccount.google.com/apppasswords, name it "Pckt" and tap Create',
          'Copy the 16-character password and paste it below (spaces are fine)',
        ],
        googleReady
            ? null
            : 'Work or school accounts may have app passwords turned off by their admin. '
                  'Google sign-in is not set up in this build.',
      ),
      EmailProvider.outlook => (
        'Outlook / Hotmail',
        const [
          'Turn on two-step verification: account.microsoft.com/security',
          'Under Advanced security options, create an app password',
          'Paste it below',
        ],
        'Microsoft is phasing out password sign-in for IMAP on personal accounts. If it fails, '
            'forward bank alerts to a Gmail or Zoho mailbox and connect that instead.',
      ),
      EmailProvider.yahoo => (
        'Yahoo Mail',
        const [
          'Open login.yahoo.com/account/security',
          'Tap "Generate app password", name it "Pckt"',
          'Paste the password below',
        ],
        null,
      ),
      EmailProvider.zoho => (
        'Zoho Mail',
        const [
          'Mail Settings → Mail Accounts → IMAP Access: enable IMAP',
          'If you use 2FA: accounts.zoho.in → Security → App passwords → Generate',
          'Paste it below',
        ],
        'Accounts outside India use imap.zoho.com — change it under Server settings.',
      ),
      _ => (
        'Any IMAP mailbox',
        const [
          "Find your provider's IMAP server (usually imap.<domain>, port 993, SSL)",
          'Use an app password if your provider offers one',
        ],
        null,
      ),
    };
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsBold.info, size: 18, color: Palette.violet),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: context.text.titleSmall)),
            ],
          ),
          const SizedBox(height: 10),
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Palette.violet.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: context.text.labelSmall?.copyWith(color: Palette.violet, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: SelectableText(s, style: context.text.bodyMedium)),
                ],
              ),
            ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
