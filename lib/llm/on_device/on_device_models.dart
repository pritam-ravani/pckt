import 'dart:async';

import 'package:background_downloader/background_downloader.dart' show FileDownloader;
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../llm_config.dart';
import '../llm_providers.dart';
import 'device_profile.dart';
import 'model_catalog.dart';
import 'on_device_client.dart';

class OnDeviceState {
  const OnDeviceState({
    this.loading = true,
    this.profile,
    this.recommendation,
    this.installed = const {},
    this.hasHfToken = false,
    this.downloadingId,
    this.progress = 0,
    this.error,
  });

  final bool loading;
  final DeviceProfile? profile;
  final Recommendation? recommendation;

  /// File names of installed `.litertlm` models.
  final Set<String> installed;
  final bool hasHfToken;
  final String? downloadingId;

  /// 0–100 for [downloadingId].
  final int progress;
  final String? error;

  bool isInstalled(OnDeviceModel m) => installed.contains(m.file);

  OnDeviceState copyWith({
    bool? loading,
    DeviceProfile? profile,
    Recommendation? recommendation,
    Set<String>? installed,
    bool? hasHfToken,
    String? downloadingId,
    bool clearDownload = false,
    int? progress,
    String? error,
  }) => OnDeviceState(
    loading: loading ?? this.loading,
    profile: profile ?? this.profile,
    recommendation: recommendation ?? this.recommendation,
    installed: installed ?? this.installed,
    hasHfToken: hasHfToken ?? this.hasHfToken,
    downloadingId: clearDownload ? null : downloadingId ?? this.downloadingId,
    progress: progress ?? this.progress,
    error: error,
  );
}

/// Owns on-device model files: which fit this phone, which are on disk,
/// downloading, deleting, and making one the active LLM.
class OnDeviceModels extends Notifier<OnDeviceState> {
  CancelToken? _cancel;

  static String get tokenKey => LlmConfig.keyName('ondevice');

  Timer? _networkWatch;

  @override
  OnDeviceState build() {
    ref.onDispose(() => _networkWatch?.cancel());
    Future.microtask(() async {
      // A download from an earlier session (app killed mid-way) would keep
      // going in WorkManager with nobody tracking it. Model downloads only
      // ever start from this screen, so anything left over is an orphan.
      await _cancelStrayDownloads();
      await refresh();
    });
    return const OnDeviceState();
  }

  static Future<void> _cancelStrayDownloads() async {
    try {
      await FileDownloader().cancelAll(group: _downloadGroup);
    } catch (e) {
      debugPrint('cancel stray downloads: $e');
    }
  }

  /// flutter_edge_ai's background_downloader group (SmartDownloader.downloadGroup).
  static const _downloadGroup = 'smart_downloads';

  Future<void> refresh() async {
    try {
      final profile = await DeviceProfile.read();
      final token = await ref.read(secretStoreProvider).read(tokenKey);
      final hasToken = token != null && token.isNotEmpty;
      final installed = await _installedFiles();
      state = state.copyWith(
        loading: false,
        profile: profile,
        recommendation: profile == null ? null : recommendModel(profile, hasHfToken: hasToken),
        installed: installed,
        hasHfToken: hasToken,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Could not read this phone\'s details: $e');
    }
  }

  Future<Set<String>> _installedFiles() async {
    try {
      return (await FlutterEdgeAi.listInstalledModels()).toSet();
    } catch (e) {
      debugPrint('listInstalledModels failed: $e');
      return {};
    }
  }

  Future<void> saveHfToken(String token) async {
    await ref.read(secretStoreProvider).write(tokenKey, token.trim());
    await refresh();
  }

  Future<bool> isOnMobileData() => DeviceProfile.isMetered();

  /// Downloads [m], then makes it the active LLM.
  ///
  /// Runs as an Android foreground service with a progress notification:
  /// without one WorkManager kills the job at 9 minutes, and Hugging Face
  /// files can't resume (weak ETags), so a 2.4 GB model would never finish.
  /// Unless [allowMobileData], the download stops if the phone leaves Wi-Fi.
  Future<bool> download(OnDeviceModel m, {bool allowMobileData = false}) async {
    if (state.downloadingId != null) return false;
    final token = m.gated ? await ref.read(secretStoreProvider).read(tokenKey) : null;
    if (m.gated && (token == null || token.isEmpty)) {
      state = state.copyWith(error: '${m.name} needs a Hugging Face token (free) after accepting the Gemma licence.');
      return false;
    }
    if (!allowMobileData && await DeviceProfile.isMetered()) {
      state = state.copyWith(error: 'Connect to Wi-Fi to download ${m.name}.');
      return false;
    }
    await DeviceProfile.requestNotifications();
    final cancel = _cancel = CancelToken();
    var stopReason = 'Cancelled';
    if (!allowMobileData) {
      _networkWatch = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!cancel.isCancelled && await DeviceProfile.isMetered()) {
          stopReason =
              'Wi-Fi was lost, so the download stopped to save mobile data. Tap Download on Wi-Fi to start again.';
          cancel.cancel(stopReason);
        }
      });
    }
    state = state.copyWith(downloadingId: m.id, progress: 0);
    try {
      await FlutterEdgeAi.installModel(modelType: m.modelType, fileType: ModelFileType.litertlm)
          .fromNetwork(m.url, token: token, foreground: true)
          .withProgress((p) => state = state.copyWith(progress: p))
          .withCancelToken(cancel)
          .install();
      state = state.copyWith(clearDownload: true, installed: await _installedFiles());
      await use(m);
      return true;
    } on DownloadCancelledException {
      state = state.copyWith(clearDownload: true, error: stopReason == 'Cancelled' ? null : stopReason);
      return false;
    } catch (e) {
      final msg = '$e';
      state = state.copyWith(
        clearDownload: true,
        error: msg.contains('401') || msg.contains('403')
            ? 'Hugging Face refused the download. Accept the licence on huggingface.co/${m.repo} and check the token.'
            : 'Download failed: $msg',
      );
      return false;
    } finally {
      _networkWatch?.cancel();
      _networkWatch = null;
      // The plugin's own retry loop can outlive install() after a failure;
      // make sure nothing keeps downloading once we've given up.
      if (state.downloadingId == null && !state.isInstalled(m)) await _cancelStrayDownloads();
    }
  }

  void cancelDownload() => _cancel?.cancel('Cancelled');

  /// Makes an installed model the app's LLM (provider "On this phone").
  Future<void> use(OnDeviceModel m) async {
    final cfg = ref.read(llmConfigProvider);
    await ref
        .read(llmConfigProvider.notifier)
        .save(
          cfg.copyWith(
            presetId: 'ondevice',
            model: m.id,
            baseUrl: '',
            // Background AI is slow on a phone (a minute or more per batch)
            // and competes with Ask for the model, so both jobs start off
            // when switching to on-device; the user can turn them on.
            aiReadUnparsed: cfg.presetId == 'ondevice' ? cfg.aiReadUnparsed : false,
            aiCategorise: cfg.presetId == 'ondevice' ? cfg.aiCategorise : false,
          ),
        );
  }

  Future<void> delete(OnDeviceModel m) async {
    // Free the loaded model first. (getActiveModel() here would *load* it
    // with default parameters just to close it.)
    await OnDeviceClient.runtime.unload('model deleted', force: true);
    await FlutterEdgeAi.uninstallModel(m.file);
    if (m.file.startsWith(FlutterEdgeAi.activeModelSpec?.name ?? '\u0000')) {
      await FlutterEdgeAi.clearActiveInferenceIdentity();
    }
    final cfg = ref.read(llmConfigProvider);
    if (cfg.presetId == 'ondevice' && cfg.model == m.id) {
      await ref.read(llmConfigProvider.notifier).save(cfg.copyWith(model: ''));
    }
    state = state.copyWith(installed: await _installedFiles());
  }
}

final onDeviceModelsProvider = NotifierProvider<OnDeviceModels, OnDeviceState>(OnDeviceModels.new);
