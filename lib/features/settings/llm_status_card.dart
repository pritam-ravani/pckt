import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../llm/llm_providers.dart';
import '../../llm/on_device/model_catalog.dart';
import '../../ui/widgets.dart';

/// Settings card for the bring-your-own LLM connection and its jobs.
class LlmStatusCard extends ConsumerWidget {
  const LlmStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(llmConfigProvider);
    final jobs = ref.watch(aiJobsProvider);
    final pending = ref.watch(pendingLlmCountProvider).value ?? 0;
    final ctrl = ref.read(aiJobsProvider.notifier);
    final connected = config.isConfigured;
    final busy = jobs.running != null;

    return AppCard(
      onTap: () => context.push('/llm'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Palette.violet.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(PhosphorIconsFill.sparkle, color: Palette.violet),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect your LLM', style: context.text.titleMedium),
                    Text(
                      connected
                          ? '${config.preset.label} · ${ModelCatalog.byId(config.model)?.name ?? config.model}'
                          : 'Gemma on this phone, or OpenAI-compatible, Claude, Gemini',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(PhosphorIconsBold.caretRight, size: 18, color: context.colors.onSurfaceVariant),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Flag('Categorise', config.aiCategorise),
                _Flag('Read messages', config.aiReadUnparsed),
                _Flag('Assistant', config.assistant),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 14),
              Text(
                '${jobs.running}${jobs.progress == null ? '…' : ' ${jobs.progress!.$1}/${jobs.progress!.$2}'}',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: jobs.progress == null ? null : jobs.progress!.$1 / jobs.progress!.$2,
                borderRadius: BorderRadius.circular(4),
              ),
            ] else if (jobs.error != null || jobs.lastResult != null) ...[
              const SizedBox(height: 10),
              Text(
                jobs.error ?? jobs.lastResult!,
                style: context.text.bodySmall?.copyWith(
                  color: jobs.error != null ? Palette.coral : context.colors.onSurfaceVariant,
                ),
              ),
            ],
            if (config.aiCategorise || (config.aiReadUnparsed && pending > 0)) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (config.aiReadUnparsed && pending > 0) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : ctrl.readUnparsed,
                        icon: const Icon(PhosphorIconsBold.chatText, size: 18),
                        label: Text('Read $pending'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (config.aiCategorise)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => ctrl.categorise(all: true),
                        icon: const Icon(PhosphorIconsBold.tag, size: 18),
                        label: const Text('Categorise'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag(this.label, this.on);
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) => InfoPill(
    icon: on ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.minusCircle,
    label: label,
    color: on ? Palette.mint : null,
  );
}
