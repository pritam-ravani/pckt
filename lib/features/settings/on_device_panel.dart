import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../llm/llm_client.dart';
import '../../llm/llm_providers.dart';
import '../../llm/on_device/device_profile.dart';
import '../../llm/on_device/model_catalog.dart';
import '../../llm/on_device/on_device_client.dart';
import '../../llm/on_device/on_device_models.dart';
import '../../ui/widgets.dart';

String _size(int bytes) =>
    bytes >= 1 << 30 ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB' : '${(bytes / (1 << 20)).round()} MB';

/// "On this phone" provider: shows what the phone can run, recommends a
/// Gemma model, and downloads / switches / deletes model files.
class OnDeviceModelPanel extends ConsumerWidget {
  const OnDeviceModelPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(onDeviceModelsProvider);
    final ctrl = ref.read(onDeviceModelsProvider.notifier);
    if (s.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final profile = s.profile;
    final rec = s.recommendation;
    if (profile == null || rec == null) {
      return AppCard(child: Text(s.error ?? 'On-device models need an Android phone.'));
    }
    final active = ref.watch(llmConfigProvider);
    final activeId = active.presetId == 'ondevice' ? active.model : null;
    final visible = rec.options.where((o) => o.fit != ModelFit.wrongChip).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('This phone'),
        _DeviceCard(profile: profile),
        const SizedBox(height: 10),
        for (final n in rec.notes)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(PhosphorIconsFill.sparkle, size: 14, color: Palette.violet),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(n, style: context.text.bodySmall)),
              ],
            ),
          ),
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.error!, style: context.text.bodySmall?.copyWith(color: Palette.coral)),
          ),
        const SizedBox(height: 12),
        const SectionHeader('Models'),
        for (final o in visible) ...[
          _ModelCard(
            option: o,
            installed: s.isInstalled(o.model),
            active: activeId == o.model.id,
            downloading: s.downloadingId == o.model.id,
            progress: s.progress,
            busy: s.downloadingId != null,
            needsToken: o.model.gated && !s.hasHfToken,
            onDownload: () => _confirmDownload(context, ctrl, o.model),
            onCancel: ctrl.cancelDownload,
            onUse: () => ctrl.use(o.model),
            onDelete: () => _confirmDelete(context, ctrl, o.model),
            onToken: () => _askToken(context, ctrl, o.model),
          ),
          const SizedBox(height: 10),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: Text(
            'Models download once from Hugging Face over Wi-Fi (it keeps going in the background, with a '
            'notification), then everything runs offline.',
            style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDownload(BuildContext context, OnDeviceModels ctrl, OnDeviceModel m) async {
    final metered = await ctrl.isOnMobileData();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(metered ? 'You\'re on mobile data' : 'Download ${m.name}?'),
        content: Text(
          metered
              ? '${m.name} is ${_size(m.sizeBytes)}. Downloading it on mobile data may use your data pack. '
                    'Connect to Wi-Fi, or download anyway.'
              : '${_size(m.sizeBytes)} from huggingface.co/${m.repo}. Progress shows in a notification; '
                    'if Wi-Fi drops, the download stops instead of using mobile data. '
                    'After this, ${m.name} runs entirely on your phone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(metered ? 'Use mobile data' : 'Download')),
        ],
      ),
    );
    if (ok == true) await ctrl.download(m, allowMobileData: metered);
  }

  Future<void> _confirmDelete(BuildContext context, OnDeviceModels ctrl, OnDeviceModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${m.name}?'),
        content: Text('Frees ${_size(m.sizeBytes)}. You can download it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ctrl.delete(m);
  }

  Future<void> _askToken(BuildContext context, OnDeviceModels ctrl, OnDeviceModel m) async {
    final field = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hugging Face token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.name} is licensed by Google. On huggingface.co/${m.repo} sign in and accept the licence, then '
              'create a read token at huggingface.co/settings/tokens and paste it here.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'hf_…'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('Save')),
        ],
      ),
    );
    if (token != null && token.trim().isNotEmpty) await ctrl.saveHfToken(token);
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.profile});
  final DeviceProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    Widget fact(IconData icon, String label, String value) => Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: context.text.titleSmall, overflow: TextOverflow.ellipsis),
                Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.manufacturer} ${p.model}'.trim(), style: context.text.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              fact(PhosphorIconsRegular.cpu, 'chip', p.chipLabel.isEmpty ? 'Unknown' : p.chipLabel),
              fact(PhosphorIconsRegular.memory, 'RAM', '${p.ramGb.toStringAsFixed(1)} GB'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              fact(PhosphorIconsRegular.hardDrives, 'free storage', '${p.freeStorageGb.toStringAsFixed(1)} GB'),
              fact(PhosphorIconsRegular.lightning, 'GPU compute', p.hasOpenCl ? 'Available' : 'Not found'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends ConsumerStatefulWidget {
  const _ModelCard({
    required this.option,
    required this.installed,
    required this.active,
    required this.downloading,
    required this.progress,
    required this.busy,
    required this.needsToken,
    required this.onDownload,
    required this.onCancel,
    required this.onUse,
    required this.onDelete,
    required this.onToken,
  });

  final ModelOption option;
  final bool installed;
  final bool active;
  final bool downloading;
  final int progress;
  final bool busy;
  final bool needsToken;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onUse;
  final VoidCallback onDelete;
  final VoidCallback onToken;

  @override
  ConsumerState<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends ConsumerState<_ModelCard> {
  var _testing = false;
  String? _testResult;

  /// A tiny real generation: proves the file loads and shows the speed.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final watch = Stopwatch()..start();
    try {
      final res = await OnDeviceClient(model: widget.option.model).chat(
        system: 'You are a concise assistant.',
        messages: [
          UserMessage('A payment of ${money(25000)} went to Swiggy. Which spending category is that? One word.'),
        ],
        maxTokens: 64,
      );
      _testResult = '“${res.text}” · ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
    } on LlmException catch (e) {
      _testResult = e.userMessage;
    } catch (e) {
      _testResult = 'Failed: $e';
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.option;
    final m = o.model;
    final (badge, color) = switch (o.fit) {
      ModelFit.recommended => ('Recommended', Palette.mint),
      ModelFit.fits => ('Fits', Palette.violet),
      ModelFit.tight => ('Tight fit', Palette.amber),
      ModelFit.tooLarge => ('Too large', Palette.coral),
      ModelFit.noStorage => ('Not enough space', Palette.coral),
      ModelFit.needsNpuBuild => ('NPU build only', Palette.neutral),
      ModelFit.wrongChip || ModelFit.unsupported => ('Unsupported', Palette.neutral),
    };
    return AppCard(
      padding: const EdgeInsets.all(16),
      color: widget.active ? Palette.mint.withValues(alpha: context.isDark ? 0.10 : 0.08) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(m.name, style: context.text.titleMedium)),
              if (widget.active)
                const InfoPill(icon: PhosphorIconsBold.checkCircle, label: 'In use', color: Palette.mint)
              else
                InfoPill(icon: PhosphorIconsBold.cpu, label: badge, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(m.summary, style: context.text.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              InfoPill(icon: PhosphorIconsBold.cloudArrowDown, label: _size(m.sizeBytes)),
              InfoPill(icon: PhosphorIconsBold.memory, label: '${m.minRamGb.toStringAsFixed(1)}+ GB RAM'),
              if (m.supportsTools) const InfoPill(icon: PhosphorIconsBold.wrench, label: 'Ask tab'),
              if (m.gated) const InfoPill(icon: PhosphorIconsBold.key, label: 'Licence + token'),
            ],
          ),
          if (!o.selectable && !widget.installed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(o.reason, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ),
          if (widget.downloading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: widget.progress / 100, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text('Downloading… ${widget.progress}%', style: context.text.bodySmall)),
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            _actions(context, o),
          ],
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_testResult!, style: context.text.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, ModelOption o) {
    if (widget.installed) {
      return Row(
        children: [
          if (!widget.active)
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                onPressed: widget.onUse,
                child: const Text('Use this model'),
              ),
            ),
          if (!widget.active) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(PhosphorIconsBold.play, size: 16),
              label: Text(_testing ? 'Thinking…' : 'Test'),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: widget.busy ? null : widget.onDelete,
            icon: const Icon(PhosphorIconsRegular.trash, color: Palette.coral),
          ),
        ],
      );
    }
    if (!o.selectable) return const SizedBox.shrink();
    if (widget.needsToken) {
      return OutlinedButton.icon(
        onPressed: widget.onToken,
        icon: const Icon(PhosphorIconsBold.key, size: 16),
        label: const Text('Add Hugging Face token'),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
      onPressed: widget.busy ? null : widget.onDownload,
      icon: const Icon(PhosphorIconsBold.downloadSimple, size: 18),
      label: Text('Download ${_size(o.model.sizeBytes)}'),
    );
  }
}
