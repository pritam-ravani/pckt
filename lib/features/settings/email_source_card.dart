import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../ingestion/email/email_source.dart';
import '../../ingestion/email/email_sync.dart';
import '../../ui/widgets.dart';

/// Settings card for the email source: status, stats, sync and inspect.
class EmailSourceCard extends ConsumerWidget {
  const EmailSourceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(emailSyncProvider);
    final stats = ref.watch(emailStatsProvider).value ?? const {};
    final ctrl = ref.read(emailSyncProvider.notifier);
    final account = sync.account;

    final status = !sync.enabled
        ? (account == null ? 'Bank alerts & receipts from your inbox' : 'Paused · ${account.address}')
        : sync.running
        ? 'Syncing ${account?.address ?? ''}…'
        : sync.lastSync == null
        ? account?.address ?? 'Connected'
        : '${account?.address ?? ''} · synced ${relativeTime(sync.lastSync!)}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Palette.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(PhosphorIconsFill.envelopeSimple, color: Palette.amber),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account == null || !sync.enabled ? 'Email' : 'Email · ${_providerName(account.provider)}',
                      style: context.text.titleMedium,
                    ),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (sync.enabled) Switch(value: true, onChanged: (_) => _confirmDisconnect(context, ref)),
            ],
          ),
          if (sync.error != null) ...[
            const SizedBox(height: 10),
            Text(sync.error!, style: context.text.bodySmall?.copyWith(color: Palette.coral)),
          ],
          if (sync.running) ...[const SizedBox(height: 12), const LinearProgressIndicator(minHeight: 3)],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoPill(
                  icon: PhosphorIconsBold.checkCircle,
                  label: '${stats[ParseStatus.parsed] ?? 0} parsed',
                  color: Palette.mint,
                ),
                InfoPill(icon: PhosphorIconsBold.gitMerge, label: '${stats[ParseStatus.merged] ?? 0} merged'),
                InfoPill(icon: PhosphorIconsBold.eyeSlash, label: '${stats[ParseStatus.ignored] ?? 0} ignored'),
                if ((stats[ParseStatus.pendingLlm] ?? 0) > 0)
                  InfoPill(
                    icon: PhosphorIconsBold.question,
                    label: '${stats[ParseStatus.pendingLlm]} unreadable',
                    color: Palette.amber,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (!sync.enabled)
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: () => context.push('/email/connect'),
                    child: Text(account == null ? 'Connect' : 'Reconnect'),
                  ),
                )
              else ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: sync.running ? null : ctrl.sync,
                    icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 18),
                    label: const Text('Sync now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/messages?source=email'),
                    icon: const Icon(PhosphorIconsBold.listMagnifyingGlass, size: 18),
                    label: const Text('Inspect'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _providerName(EmailProvider p) => p == EmailProvider.gmailOAuth ? 'Gmail' : p.label;

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Disconnect email?'),
        content: const Text(
          'Pckt stops reading this mailbox and forgets the password. '
          'Transactions already imported stay.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok == true) await ref.read(emailSyncProvider.notifier).disconnect();
  }
}
