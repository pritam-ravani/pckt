import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'llm_client.dart';
import 'on_device/model_catalog.dart';
import 'on_device/on_device_client.dart';
import 'providers/anthropic_client.dart';
import 'providers/gemini_client.dart';
import 'providers/openai_client.dart';

/// Wire protocol families. [onDevice] runs a model inside the app.
enum LlmProviderKind { openAiCompatible, anthropic, gemini, onDevice }

class LlmPreset {
  const LlmPreset({
    required this.id,
    required this.label,
    required this.kind,
    this.baseUrl = '',
    this.keyRequired = true,
    this.editableBaseUrl = false,
    this.suggestedModels = const [],
    this.hint,
    this.available = true,
  });

  final String id;
  final String label;
  final LlmProviderKind kind;
  final String baseUrl;
  final bool keyRequired;
  final bool editableBaseUrl;

  /// Shown before the live model list loads (or if listing fails).
  final List<String> suggestedModels;
  final String? hint;
  final bool available;

  bool get isLocal => !keyRequired;
}

abstract final class LlmPresets {
  static const all = <LlmPreset>[
    LlmPreset(
      id: 'openai',
      label: 'OpenAI',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'https://api.openai.com/v1',
      suggestedModels: ['gpt-5-mini', 'gpt-5'],
    ),
    LlmPreset(
      id: 'anthropic',
      label: 'Anthropic Claude',
      kind: LlmProviderKind.anthropic,
      baseUrl: AnthropicClient.defaultBaseUrl,
      suggestedModels: ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-4-5'],
    ),
    LlmPreset(
      id: 'gemini',
      label: 'Google Gemini',
      kind: LlmProviderKind.gemini,
      baseUrl: GeminiClient.defaultBaseUrl,
      suggestedModels: ['gemini-3.8-flash', 'gemini-2.5-flash'],
    ),
    LlmPreset(
      id: 'openrouter',
      label: 'OpenRouter',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'https://openrouter.ai/api/v1',
      suggestedModels: ['openai/gpt-5-mini', 'anthropic/claude-sonnet-5.5', 'google/gemini-2.5-flash'],
    ),
    LlmPreset(
      id: 'groq',
      label: 'Groq',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'https://api.groq.com/openai/v1',
      suggestedModels: ['llama-3.3-70b-versatile', 'openai/gpt-oss-120b'],
    ),
    LlmPreset(
      id: 'deepseek',
      label: 'DeepSeek',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'https://api.deepseek.com/v1',
      suggestedModels: ['deepseek-chat'],
    ),
    LlmPreset(
      id: 'ollama',
      label: 'Ollama (your computer)',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'http://192.168.1.10:11434/v1',
      keyRequired: false,
      editableBaseUrl: true,
      suggestedModels: ['qwen3:8b', 'llama3.1:8b'],
      hint: 'Run `OLLAMA_HOST=0.0.0.0 ollama serve` and use your computer\'s LAN IP. Pick a model with tool support.',
    ),
    LlmPreset(
      id: 'lmstudio',
      label: 'LM Studio (your computer)',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'http://192.168.1.10:1234/v1',
      keyRequired: false,
      editableBaseUrl: true,
      hint: 'Enable "Serve on local network" in LM Studio\'s developer tab and use your computer\'s LAN IP.',
    ),
    LlmPreset(
      id: 'custom',
      label: 'Other OpenAI-compatible',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'https://',
      keyRequired: false,
      editableBaseUrl: true,
      hint: 'Any server implementing /chat/completions with tool calls. Key is optional.',
    ),
    LlmPreset(
      id: 'ondevice',
      label: 'On this phone (Gemma)',
      kind: LlmProviderKind.onDevice,
      keyRequired: false,
      hint: 'Runs a Gemma model inside Pckt. Nothing leaves the phone; works offline after one download.',
    ),
  ];

  static LlmPreset byId(String? id) => all.firstWhere((p) => p.id == id, orElse: () => all.first);
}

/// Everything about the LLM connection except the API key (which lives in
/// [SecretStore] under [LlmConfig.keyName]).
class LlmConfig {
  const LlmConfig({
    this.presetId,
    this.baseUrl = '',
    this.model = '',
    this.aiCategorise = true,
    this.aiReadUnparsed = false,
    this.assistant = true,
  });

  /// Null until the user saves a connection.
  final String? presetId;
  final String baseUrl;
  final String model;

  /// Sends merchant / amount / date / mode of uncategorised transactions.
  final bool aiCategorise;

  /// Sends the raw text of messages the rules could not read. Off by default.
  final bool aiReadUnparsed;

  /// Sends the user's questions and tool results computed on-device.
  final bool assistant;

  LlmPreset get preset => LlmPresets.byId(presetId);
  bool get isConfigured => presetId != null && model.isNotEmpty && preset.available;

  static String keyName(String presetId) => 'llm.apiKey.$presetId';

  static const _kPreset = 'llm.provider';
  static const _kBase = 'llm.baseUrl';
  static const _kModel = 'llm.model';
  static const _kCat = 'llm.aiCategorise';
  static const _kRead = 'llm.aiReadUnparsed';
  static const _kChat = 'llm.assistant';

  static LlmConfig load(SharedPreferences p) => LlmConfig(
    presetId: p.getString(_kPreset),
    baseUrl: p.getString(_kBase) ?? '',
    model: p.getString(_kModel) ?? '',
    aiCategorise: p.getBool(_kCat) ?? true,
    aiReadUnparsed: p.getBool(_kRead) ?? false,
    assistant: p.getBool(_kChat) ?? true,
  );

  Future<void> save(SharedPreferences p) async {
    if (presetId == null) {
      await p.remove(_kPreset);
    } else {
      await p.setString(_kPreset, presetId!);
    }
    await p.setString(_kBase, baseUrl);
    await p.setString(_kModel, model);
    await p.setBool(_kCat, aiCategorise);
    await p.setBool(_kRead, aiReadUnparsed);
    await p.setBool(_kChat, assistant);
  }

  LlmConfig copyWith({
    String? presetId,
    bool clearPreset = false,
    String? baseUrl,
    String? model,
    bool? aiCategorise,
    bool? aiReadUnparsed,
    bool? assistant,
  }) => LlmConfig(
    presetId: clearPreset ? null : presetId ?? this.presetId,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    aiCategorise: aiCategorise ?? this.aiCategorise,
    aiReadUnparsed: aiReadUnparsed ?? this.aiReadUnparsed,
    assistant: assistant ?? this.assistant,
  );
}

/// Builds the client for a preset. Throws [LlmException] for setups that
/// can't work (missing key, on-device not yet available).
LlmClient buildLlmClient({
  required LlmPreset preset,
  required String baseUrl,
  required String model,
  required String? apiKey,
  required http.Client httpClient,
}) {
  if (!preset.available) {
    throw const LlmException(LlmErrorKind.notConfigured, 'This provider is not available yet');
  }
  if (preset.keyRequired && (apiKey == null || apiKey.isEmpty)) {
    throw const LlmException(LlmErrorKind.notConfigured, 'API key missing');
  }
  final base = baseUrl.isEmpty ? preset.baseUrl : baseUrl;
  return switch (preset.kind) {
    LlmProviderKind.openAiCompatible => OpenAiCompatibleClient(
      httpClient: httpClient,
      baseUrl: base,
      model: model,
      apiKey: apiKey,
    ),
    LlmProviderKind.anthropic => AnthropicClient(httpClient: httpClient, apiKey: apiKey!, model: model, baseUrl: base),
    LlmProviderKind.gemini => GeminiClient(httpClient: httpClient, apiKey: apiKey!, model: model, baseUrl: base),
    // For on-device, the key slot holds the optional Hugging Face token that
    // gated Gemma downloads need.
    LlmProviderKind.onDevice => switch (ModelCatalog.byId(model)) {
      final m? => OnDeviceClient(model: m, hfToken: apiKey),
      null => throw const LlmException(LlmErrorKind.notConfigured, 'Pick an on-device model first'),
    },
  };
}
