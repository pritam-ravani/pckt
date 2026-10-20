import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../ingestion/email/email_sync.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'data_section.dart';
import 'email_source_card.dart';
import 'llm_status_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text('Settings', style: context.text.headlineSmall),
            ),
            const SectionHeader('Sources'),
            const _SmsCard(),
            const SizedBox(height: 10),
            const EmailSourceCard(),
            const SizedBox(height: 10),
            const LlmStatusCard(),
            if (accounts.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader('Detected accounts'),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Column(
                  children: [
                    for (final a in accounts)
                      ListTile(
                        leading: Icon(
                          a.kind == AccountKind.creditCard ? PhosphorIconsFill.creditCard : PhosphorIconsFill.bank,
                          color: Color(a.color),
                        ),
                        title: Text(a.name),
                        trailing: Text('••${a.last4 ?? ''}', style: context.text.labelLarge),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            const SectionHeader('Appearance'),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(PhosphorIconsRegular.deviceMobile),
                ),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(PhosphorIconsRegular.moon)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(PhosphorIconsRegular.sun)),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
            const SizedBox(height: 20),
            const SectionHeader('Data'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.shieldCheck),
                    title: const Text('Stored only on this phone'),
                    subtitle: const Text('Messages are parsed on-device. Nothing is uploaded.'),
                  ),
                  const DataExportTiles(),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.trash, color: Palette.coral),
                    title: const Text('Reset imported data'),
                    subtitle: const Text('Clears transactions & messages; keeps categories and rules'),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Reset imported data?'),
                          content: const Text(
                            'All transactions and parsed messages will be deleted. '
                            'You can re-import SMS afterwards.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref.read(databaseProvider).resetImported();
                        await ref.read(prefsProvider).remove(PrefKeys.smsLastSync);
                        await ref.read(prefsProvider).remove(EmailPrefKeys.lastSync);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmsCard extends ConsumerWidget {
  const _SmsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(smsSyncProvider);
    final stats = ref.watch(smsStatsProvider).value ?? const {};
    final ctrl = ref.read(smsSyncProvider.notifier);
    final supported = ref.read(smsSourceProvider).isSupported;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Palette.mint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(PhosphorIconsFill.chatText, color: Palette.mint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SMS', style: context.text.titleMedium),
                    Text(
                      !supported
                          ? 'Not available on iOS'
                          : !sync.enabled
                          ? 'Not connected'
                          : sync.running
                          ? 'Syncing…'
                          : sync.lastSync == null
                          ? 'Connected'
                          : 'Synced ${relativeTime(sync.lastSync!)}',
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (sync.enabled) Switch(value: true, onChanged: (_) => ctrl.disconnect()),
            ],
          ),
          if (sync.error != null) ...[
            const SizedBox(height: 10),
            Text(sync.error!, style: context.text.bodySmall?.copyWith(color: Palette.coral)),
          ],
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
          if (supported)
            Row(
              children: [
                if (!sync.enabled)
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      onPressed: () => _pickRangeAndConnect(context, ref),
                      child: const Text('Connect'),
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
                      onPressed: () => context.push('/messages'),
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
}

Future<void> _pickRangeAndConnect(BuildContext context, WidgetRef ref) async {
  final months = await showModalBottomSheet<int>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Import history from', style: c.text.titleMedium),
          const SizedBox(height: 8),
          for (final m in const [1, 3, 6, 12])
            ListTile(
              leading: const Icon(PhosphorIconsRegular.clockCounterClockwise),
              title: Text(m == 1 ? 'Last month' : 'Last $m months'),
              onTap: () => Navigator.pop(c, m),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (months != null) await ref.read(smsSyncProvider.notifier).connect(months: months);
}
