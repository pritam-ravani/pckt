import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/llm/on_device/device_profile.dart';
import 'package:pckt/llm/on_device/model_catalog.dart';

const _gb = 1024 * 1024 * 1024;

DeviceProfile phone({
  required double ramGb,
  double freeGb = 40,
  String? soc,
  bool openCl = true,
  int sdk = 34,
  List<String> abis = const ['arm64-v8a', 'armeabi-v7a'],
  bool lowRam = false,
}) => DeviceProfile(
  totalRamBytes: (ramGb * _gb).round(),
  availRamBytes: (ramGb * 0.4 * _gb).round(),
  freeStorageBytes: (freeGb * _gb).round(),
  sdkInt: sdk,
  abis: abis,
  socModel: soc,
  hasOpenCl: openCl,
  lowRamDevice: lowRam,
);

ModelFit fitOf(Recommendation r, OnDeviceModel m) => r.options.firstWhere((o) => o.model == m).fit;

void main() {
  test('Galaxy F23 (6 GB, Snapdragon 750G) gets Gemma 4 E2B on the GPU, flagged tight', () {
    final r = recommendModel(phone(ramGb: 5.5, soc: 'SM7225'));
    expect(r.recommended, ModelCatalog.gemma4E2b);
    expect(r.backend, PreferredBackend.gpu);
    expect(r.notes.join(' '), contains('tight'));
    expect(fitOf(r, ModelCatalog.gemma4E4b), ModelFit.tooLarge);
    expect(fitOf(r, ModelCatalog.gemma4E2bSm8750), ModelFit.wrongChip);
  });

  test('12 GB flagship gets Gemma 4 E4B', () {
    final r = recommendModel(phone(ramGb: 11.2, soc: 'SM8750'));
    expect(r.recommended, ModelCatalog.gemma4E4b);
    expect(fitOf(r, ModelCatalog.gemma4E2bSm8750), ModelFit.needsNpuBuild);
  });

  test('8 GB Snapdragon 8 Elite with the NPU opt-in runs the NPU bundle', () {
    final r = recommendModel(phone(ramGb: 7.4, soc: 'SM8750'), qualcommNpu: true);
    expect(r.recommended, ModelCatalog.gemma4E2bSm8750);
    expect(r.backend, PreferredBackend.npu);
  });

  test('4 GB phone: Qwen without a token, Gemma 3 1B with one', () {
    final d = phone(ramGb: 3.6);
    expect(recommendModel(d).recommended, ModelCatalog.qwen3_06b);
    final withToken = recommendModel(d, hasHfToken: true);
    expect(withToken.recommended, ModelCatalog.gemma3_1b);
    expect(withToken.notes.join(' '), contains('Ask tab stays off'));
  });

  test('low free storage steps down to a smaller model', () {
    final r = recommendModel(phone(ramGb: 7.5, freeGb: 2.0));
    expect(fitOf(r, ModelCatalog.gemma4E2b), ModelFit.noStorage);
    expect(r.recommended, ModelCatalog.qwen3_06b);
  });

  test('Android low-RAM flag drops a tier', () {
    expect(recommendModel(phone(ramGb: 5.8, lowRam: true)).recommended, ModelCatalog.qwen3_06b);
  });

  test('no GPU compute driver falls back to CPU', () {
    expect(recommendModel(phone(ramGb: 7.5, openCl: false)).backend, PreferredBackend.cpu);
  });

  test('32-bit or pre-Android-11 phones are unsupported', () {
    for (final d in [
      phone(ramGb: 8, abis: ['armeabi-v7a']),
      phone(ramGb: 8, sdk: 29),
    ]) {
      final r = recommendModel(d);
      expect(r.recommended, isNull);
      expect(r.options.every((o) => o.fit == ModelFit.unsupported), isTrue);
    }
  });

  test('nothing fits a 2 GB phone', () {
    final r = recommendModel(phone(ramGb: 1.8));
    expect(r.recommended, isNull);
    expect(r.notes.single, contains('No model fits'));
  });

  test('catalog URLs point at the exact Hugging Face files', () {
    expect(
      ModelCatalog.gemma4E2b.url,
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    );
    expect(ModelCatalog.all.map((m) => m.id).toSet(), hasLength(ModelCatalog.all.length));
  });
}
