import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'device_profile.dart';

/// A downloadable on-device model (one `.litertlm` file on Hugging Face).
/// Sizes come from the Hugging Face API; RAM figures are what the model needs
/// *on top of* the OS and other apps, measured as reported total RAM.
class OnDeviceModel {
  const OnDeviceModel({
    required this.id,
    required this.name,
    required this.family,
    required this.repo,
    required this.file,
    required this.sizeBytes,
    required this.modelType,
    required this.minRamGb,
    required this.contextTokens,
    required this.supportsTools,
    required this.summary,
    this.gated = false,
    this.npuSoc,
    this.f32OnGpu = false,
    this.rank = 0,
  });

  final String id;
  final String name;
  final String family;
  final String repo;
  final String file;
  final int sizeBytes;
  final ModelType modelType;

  /// Minimum *reported* total RAM to run without the OS killing the app.
  final double minRamGb;

  /// Context window we load with (prompt + history + reply).
  final int contextTokens;

  /// Native or reliable tool calling — required for the Ask tab.
  final bool supportsTools;
  final String summary;

  /// Needs a Hugging Face token after accepting the Gemma licence.
  final bool gated;

  /// Set for bundles compiled for one NPU (e.g. `SM8750`); runs only there.
  final String? npuSoc;

  /// Load with float32 activations on the GPU. Gemma 4 copies digits wrongly
  /// from long prompts at half precision — unacceptable for amounts.
  final bool f32OnGpu;

  /// Higher is more capable; the recommender walks from the top.
  final int rank;

  String get url => 'https://huggingface.co/$repo/resolve/main/$file';
  double get sizeGb => sizeBytes / (1024 * 1024 * 1024);

  /// Room to download plus headroom for the OS and the database.
  int get storageNeededBytes => (sizeBytes * 1.1).round() + 400 * 1024 * 1024;
}

abstract final class ModelCatalog {
  static const gemma4E4b = OnDeviceModel(
    id: 'gemma-4-e4b',
    name: 'Gemma 4 E4B',
    family: 'Gemma 4',
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    file: 'gemma-4-E4B-it.litertlm',
    sizeBytes: 3660000000,
    modelType: ModelType.gemma4,
    minRamGb: 10.5,
    contextTokens: 4096,
    supportsTools: true,
    f32OnGpu: true,
    rank: 40,
    summary: 'Most capable. Best answers in Ask; needs a flagship phone.',
  );

  static const gemma4E2b = OnDeviceModel(
    id: 'gemma-4-e2b',
    name: 'Gemma 4 E2B',
    family: 'Gemma 4',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    file: 'gemma-4-E2B-it.litertlm',
    sizeBytes: 2588000000,
    modelType: ModelType.gemma4,
    minRamGb: 5.2,
    contextTokens: 4096,
    supportsTools: true,
    f32OnGpu: true,
    rank: 30,
    summary: 'Balanced. Reads messages, categorises and answers questions with tools.',
  );

  /// Snapdragon 8 Elite NPU build. Only offered when the app is built with
  /// the Qualcomm NPU opt-in (see [qualcommNpuEnabled]).
  static const gemma4E2bSm8750 = OnDeviceModel(
    id: 'gemma-4-e2b-sm8750',
    name: 'Gemma 4 E2B (Snapdragon NPU)',
    family: 'Gemma 4',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    file: 'gemma-4-E2B-it_qualcomm_sm8750.litertlm',
    sizeBytes: 3016000000,
    modelType: ModelType.gemma4,
    minRamGb: 7.0,
    contextTokens: 4096,
    supportsTools: true,
    npuSoc: 'SM8750',
    rank: 35,
    summary: 'Gemma 4 E2B compiled for this chip\'s NPU: fastest and coolest-running.',
  );

  static const gemma3_1b = OnDeviceModel(
    id: 'gemma-3-1b',
    name: 'Gemma 3 1B',
    family: 'Gemma 3',
    repo: 'litert-community/Gemma3-1B-IT',
    file: 'gemma3-1b-it-int4.litertlm',
    sizeBytes: 584000000,
    modelType: ModelType.gemmaIt,
    minRamGb: 2.8,
    contextTokens: 2048,
    supportsTools: false,
    gated: true,
    rank: 20,
    summary: 'Small Gemma for older phones. Reads messages and categorises; no Ask tab.',
  );

  static const qwen3_06b = OnDeviceModel(
    id: 'qwen3-0.6b',
    name: 'Qwen3 0.6B',
    family: 'Qwen3',
    repo: 'litert-community/Qwen3-0.6B',
    // The plain Qwen3-0.6B.litertlm fails to load on LiteRT-LM ≥ 0.17 (#3865).
    file: 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
    sizeBytes: 345000000,
    modelType: ModelType.qwen3,
    minRamGb: 2.8,
    contextTokens: 2048,
    supportsTools: true,
    rank: 10,
    summary: 'Tiny, no sign-up. Fallback for low-memory phones; basic quality.',
  );

  /// Flip together with `qualcomm_npu: true` under `hooks.user_defines` in
  /// pubspec.yaml (bundles Qualcomm's QNN runtime; their licence applies).
  static const qualcommNpuEnabled = false;

  static const all = [gemma4E4b, gemma4E2bSm8750, gemma4E2b, gemma3_1b, qwen3_06b];

  static OnDeviceModel? byId(String? id) => all.where((m) => m.id == id).firstOrNull;

  static OnDeviceModel? byFile(String file) => all.where((m) => m.file == file).firstOrNull;
}

enum ModelFit { recommended, fits, tight, tooLarge, noStorage, wrongChip, needsNpuBuild, unsupported }

class ModelOption {
  const ModelOption(this.model, this.fit, this.reason);
  final OnDeviceModel model;
  final ModelFit fit;
  final String reason;

  bool get selectable => fit == ModelFit.recommended || fit == ModelFit.fits || fit == ModelFit.tight;
}

class Recommendation {
  const Recommendation({required this.options, required this.recommended, required this.backend, required this.notes});

  /// Every catalog model with its fit, most capable first.
  final List<ModelOption> options;
  final OnDeviceModel? recommended;
  final PreferredBackend backend;

  /// Plain-language explanation of the choice for the UI.
  final List<String> notes;
}

/// Picks the most capable model that fits this phone's RAM, storage and chip.
///
/// Rules, in order: LiteRT needs arm64 + Android 11; NPU bundles only on the
/// exact SoC they were compiled for (and only with the opt-in); RAM below the
/// model's floor rules it out, within 15% of it is "tight"; a model must also
/// fit in free storage. Android's low-RAM flag drops one tier.
Recommendation recommendModel(
  DeviceProfile d, {
  bool qualcommNpu = ModelCatalog.qualcommNpuEnabled,
  bool hasHfToken = false,
}) {
  final notes = <String>[];
  if (!d.canRunLiteRt) {
    final why = !d.isArm64 ? 'needs a 64-bit ARM phone' : 'needs Android 11 or newer';
    return Recommendation(
      options: [for (final m in ModelCatalog.all) ModelOption(m, ModelFit.unsupported, why)],
      recommended: null,
      backend: PreferredBackend.cpu,
      notes: ['On-device AI $why.'],
    );
  }

  final soc = (d.socModel ?? '').toUpperCase();
  final options = <ModelOption>[];
  for (final m in [...ModelCatalog.all]..sort((a, b) => b.rank.compareTo(a.rank))) {
    if (m.npuSoc != null) {
      if (!soc.contains(m.npuSoc!)) {
        options.add(ModelOption(m, ModelFit.wrongChip, 'Built for ${m.npuSoc} chips only'));
        continue;
      }
      if (!qualcommNpu) {
        options.add(ModelOption(m, ModelFit.needsNpuBuild, 'Needs the NPU-enabled build of Pckt'));
        continue;
      }
    }
    final ramFloor = m.minRamGb + (d.lowRamDevice ? 1.5 : 0);
    if (d.ramGb < ramFloor) {
      options.add(
        ModelOption(
          m,
          ModelFit.tooLarge,
          'Needs ~${ramFloor.toStringAsFixed(1)} GB RAM, phone has ${d.ramGb.toStringAsFixed(1)} GB',
        ),
      );
      continue;
    }
    if (d.freeStorageBytes < m.storageNeededBytes) {
      options.add(
        ModelOption(
          m,
          ModelFit.noStorage,
          'Needs ${(m.storageNeededBytes / (1 << 30)).toStringAsFixed(1)} GB free, ${d.freeStorageGb.toStringAsFixed(1)} GB available',
        ),
      );
      continue;
    }
    final tight = d.ramGb < ramFloor * 1.15;
    options.add(
      ModelOption(
        m,
        tight ? ModelFit.tight : ModelFit.fits,
        tight ? 'Will run, but close other apps' : 'Fits comfortably',
      ),
    );
  }

  // Most capable selectable model. Gated ones need a Hugging Face token, so
  // without one they're only picked when nothing ungated fits.
  final selectable = options.where((o) => o.selectable).toList();
  final pick = selectable.where((o) => hasHfToken || !o.model.gated).firstOrNull ?? selectable.firstOrNull;

  final backend = pick?.model.npuSoc != null
      ? PreferredBackend.npu
      : d.hasOpenCl
      ? PreferredBackend.gpu
      : PreferredBackend.cpu;

  if (pick == null) {
    notes.add(
      'No model fits this phone (${d.ramGb.toStringAsFixed(1)} GB RAM, ${d.freeStorageGb.toStringAsFixed(1)} GB free).',
    );
  } else {
    notes.add('${d.ramGb.toStringAsFixed(1)} GB RAM${d.lowRamDevice ? ' (low-RAM device)' : ''} → ${pick.model.name}.');
    notes.add(switch (backend) {
      PreferredBackend.npu => 'Runs on the ${pick.model.npuSoc} NPU.',
      PreferredBackend.gpu =>
        'Runs on the GPU${pick.model.f32OnGpu ? ' at full precision (accurate amounts)' : ''}, falls back to CPU.',
      _ => 'Runs on the CPU (no GPU compute driver found).',
    });
    if (!pick.model.supportsTools) notes.add('This model cannot use tools, so the Ask tab stays off.');
    if (pick.fit == ModelFit.tight) notes.add('Memory is tight: Android may close the model when other apps are open.');
  }
  return Recommendation(
    options: [
      for (final o in options) o.model == pick?.model ? ModelOption(o.model, ModelFit.recommended, o.reason) : o,
    ],
    recommended: pick?.model,
    backend: backend,
    notes: notes,
  );
}
