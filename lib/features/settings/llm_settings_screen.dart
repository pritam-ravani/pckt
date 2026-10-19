import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../llm/llm_client.dart';
import '../../llm/llm_config.dart';
import '../../llm/llm_providers.dart';
import '../../ui/widgets.dart';
import 'on_device_panel.dart';

/// Settings → Connect your LLM: provider, endpoint, key, model, and the
/// privacy switches that decide what may be sent.
class LlmSettingsScreen extends ConsumerStatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  ConsumerState<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends ConsumerState<LlmSettingsScreen> {
  late LlmPreset _preset;
  final _baseUrl = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  var _obscure = true;
  var _models = <String>[];
  var _loadingModels = false;
  String? _modelsError;
  var _testing = false;
  (bool, String)? _testResult;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final c = ref.read(llmConfigProvider);
    _preset = c.presetId == null ? LlmPresets.all.first : c.preset;
    _baseUrl.text = c.baseUrl.isEmpty ? _preset.baseUrl : c.baseUrl;
    _model.text = c.model;
    _loadKey();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final k = await ref.read(llmConfigProvider.notifier).readKey(_preset.id);
    if (mounted) setState(() => _key.text = k ?? '');
  }

  void _pickPreset(LlmPreset p) {
    if (!p.available || p.id == _preset.id) return;
    final saved = ref.read(llmConfigProvider);
    setState(() {
      _preset = p;
      _baseUrl.text = saved.presetId == p.id && saved.baseUrl.isNotEmpty ? saved.baseUrl : p.baseUrl;
      _model.text = saved.presetId == p.id ? saved.model : (p.suggestedModels.firstOrNull ?? '');
      _models = [];
      _modelsError = null;
      _testResult = null;
    });
    _loadKey();
  }

  LlmClient _client({String? model}) => buildLlmClient(
    preset: _preset,
    baseUrl: _baseUrl.text.trim(),
    model: model ?? _model.text.trim(),
    apiKey: _key.text.trim(),
    httpClient: ref.read(httpClientProvider),
  );

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final list = await _client(model: 'x').listModels();
      if (!mounted) return;
      setState(() {
        _models = list;
        if (list.isEmpty) _modelsError = 'The provider returned no models — type one in.';
      });
    } on LlmException catch (e) {
      if (mounted) setState(() => _modelsError = e.userMessage);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _test() async {
    if (_model.text.trim().isEmpty) {
      setState(() => _testResult = (false, 'Pick a model first.'));
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final sw = Stopwatch()..start();
    try {
      final res = await _client().chat(messages: const [UserMessage('Reply with just: OK')], maxTokens: 64);
      final reply = res.text.trim();
      if (mounted) {
        setState(
          () => _testResult = (
            true,
            'Connected in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s'
                '${reply.isEmpty ? '' : ' — "${reply.length > 40 ? '${reply.substring(0, 40)}…' : reply}"'}',
          ),
        );
      }
    } on LlmException catch (e) {
      if (mounted) setState(() => _testResult = (false, e.userMessage));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final model = _model.text.trim();
    final key = _key.text.trim();
    if (model.isEmpty) {
      _snack('Choose a model');
      return;
    }
    if (_preset.keyRequired && key.isEmpty) {
      _snack('${_preset.label} needs an API key');
      return;
    }
    setState(() => _saving = true);
    final notifier = ref.read(llmConfigProvider.notifier);
    await notifier.save(
      ref.read(llmConfigProvider).copyWith(presetId: _preset.id, baseUrl: _baseUrl.text.trim(), model: model),
      apiKey: key,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _snack('Saved — ${_preset.label} · $model');
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool get _insecureRemote {
    final uri = Uri.tryParse(_baseUrl.text.trim());
    if (uri == null || uri.scheme != 'http') return false;
    final h = uri.host;
    final private =
        h == 'localhost' ||
        h.startsWith('10.') ||
        h.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h) ||
        h.startsWith('127.') ||
        h.endsWith('.local');
    return !private;
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(llmConfigProvider);
    final cfg = ref.read(llmConfigProvider.notifier);
    final connected = config.isConfigured;
    final options = {..._models, ..._preset.suggestedModels}.toList();
    final showBaseUrl = _preset.kind == LlmProviderKind.openAiCompatible;

    return Scaffold(
      appBar: AppBar(title: const Text('Connect your LLM')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (connected)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoPill(
                icon: PhosphorIconsBold.checkCircle,
                label: 'Using ${config.preset.label} · ${config.model}',
                color: Palette.mint,
              ),
            ),
          const SectionHeader('Provider'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in LlmPresets.all)
                ChoiceChip(
                  label: Text(p.label),
                  selected: p.id == _preset.id,
                  onSelected: p.available ? (_) => _pickPreset(p) : null,
                ),
            ],
          ),
          if (_preset.hint != null) ...[
            const SizedBox(height: 10),
            Text(_preset.hint!, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
          ],
          const SizedBox(height: 20),
          if (_preset.kind == LlmProviderKind.onDevice)
            const OnDeviceModelPanel()
          else ...[
            const SectionHeader('Connection'),
            if (showBaseUrl) ...[
              TextField(
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://…/v1'),
                onChanged: (_) => setState(() {}),
              ),
              if (_insecureRemote)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Plain http:// to a public address sends your key and data unencrypted.',
                    style: context.text.bodySmall?.copyWith(color: Palette.amber),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _preset.keyRequired ? 'API key' : 'API key (optional)',
                helperText: 'Stored in the Android keystore, never in backups or the database.',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? PhosphorIconsBold.eye : PhosphorIconsBold.eyeSlash, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) => DropdownMenu<String>(
                key: ValueKey('${_preset.id}-${options.length}'),
                controller: _model,
                width: box.maxWidth,
                menuHeight: 320,
                enableFilter: true,
                requestFocusOnTap: true,
                label: const Text('Model'),
                helperText: _models.isEmpty
                    ? 'Type a model id, or load the list from the provider'
                    : '${_models.length} models available — type to filter',
                errorText: _modelsError,
                dropdownMenuEntries: [for (final m in options) DropdownMenuEntry(value: m, label: m)],
                onSelected: (m) => setState(() => _testResult = null),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingModels ? null : _fetchModels,
                    icon: _loadingModels
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(PhosphorIconsBold.arrowsClockwise, size: 18),
                    label: const Text('Load models'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(PhosphorIconsBold.plugsConnected, size: 18),
                    label: const Text('Test'),
                  ),
                ),
              ],
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(
                      _testResult!.$1 ? PhosphorIconsBold.checkCircle : PhosphorIconsFill.warningCircle,
                      size: 18,
                      color: _testResult!.$1 ? Palette.mint : Palette.coral,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_testResult!.$2, style: context.text.bodySmall)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : _save,
              child: Text(connected ? 'Save changes' : 'Save & connect'),
            ),
          ],
          const SizedBox(height: 24),
          SectionHeader(
            config.presetId == 'ondevice' ? 'AI features — processed on this phone' : 'Privacy — what may be sent',
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                SwitchListTile(
                  value: config.aiCategorise,
                  onChanged: (v) => cfg.change((c) => c.copyWith(aiCategorise: v)),
                  secondary: const Icon(PhosphorIconsRegular.tag),
                  title: const Text('AI categorisation'),
                  subtitle: const Text(
                    'For transactions left as "Other": sends merchant, UPI handle, amount, date and payment mode. '
                    'Never message text or balances.',
                  ),
                ),
                SwitchListTile(
                  value: config.aiReadUnparsed,
                  onChanged: (v) => cfg.change((c) => c.copyWith(aiReadUnparsed: v)),
                  secondary: const Icon(PhosphorIconsRegular.chatText),
                  title: const Text('AI reading of unreadable messages'),
                  subtitle: const Text(
                    'Sends the full text of bank messages our rules couldn\'t read. These can include account '
                    'digits, balances and names. Off by default.',
                  ),
                ),
                SwitchListTile(
                  value: config.assistant,
                  onChanged: (v) => cfg.change((c) => c.copyWith(assistant: v)),
                  secondary: const Icon(PhosphorIconsRegular.sparkle),
                  title: const Text('Assistant chat'),
                  subtitle: const Text(
                    'Sends your questions and the results of queries run on this phone (totals, matching '
                    'transactions). Raw messages are never included.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Nothing is sent until a provider is saved and a switch is on. Requests go straight from this phone '
              'to the provider you chose — Pckt has no server.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          if (connected) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () async {
                await cfg.disconnect();
                _key.clear();
                if (mounted) _snack('Disconnected and key deleted');
              },
              style: TextButton.styleFrom(foregroundColor: Palette.coral),
              icon: const Icon(PhosphorIconsRegular.trash),
              label: const Text('Disconnect & delete key'),
            ),
          ],
        ],
      ),
    );
  }
}
