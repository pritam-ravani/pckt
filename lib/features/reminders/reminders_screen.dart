import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'reminders.dart';

/// Settings → Money → Reminders: alerts at chosen times to check the app.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  late final AppLifecycleListener _lifecycle;
  var _exact = true;

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshExact);
    _refreshExact();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refreshExact() async {
    final exact = await ref.read(reminderChannelProvider).canScheduleExact();
    if (mounted) setState(() => _exact = exact);
    if (exact) await ref.read(reminderChannelProvider).reschedule();
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _add() async {
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 21, minute: 0));
    if (time == null) return;
    await ref.read(smsSourceProvider).requestNotifications();
    final added = await ref.read(remindersProvider.notifier).add(time.hour, time.minute);
    if (!added && mounted) {
      _say('That time is already set, or you have reached ${RemindersController.maxReminders} reminders.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remindersProvider);
    final controller = ref.read(remindersProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add reminder',
        onPressed: _add,
        child: const Icon(PhosphorIconsBold.plus),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (!_exact) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: ListTile(
                leading: const Icon(PhosphorIconsRegular.warningCircle),
                title: const Text('Alerts may come a little late'),
                subtitle: const Text('Tap to allow alarms at the exact time'),
                trailing: const Icon(PhosphorIconsBold.caretRight, size: 16),
                onTap: ref.read(reminderChannelProvider).openExactSettings,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (state.reminders.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: PhosphorIconsFill.target,
                title: 'No reminders yet',
                message: 'Add the times you want a nudge to review payments or add a missed one.',
              ),
            ),
          for (final r in state.reminders) ...[
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          TimeOfDay(hour: r.hour, minute: r.minute).format(context),
                          style: context.text.titleLarge,
                        ),
                      ),
                      Switch(value: r.enabled, onChanged: (v) => controller.setEnabled(r.id, v)),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(PhosphorIconsRegular.trash),
                        onPressed: () => controller.remove(r.id),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final (i, letter) in _dayLetters.indexed)
                        ChoiceChip(
                          label: Text(letter),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          selected: r.days.contains(i + 1),
                          onSelected: (_) => controller.toggleDay(r.id, i + 1),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (state.reminders.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(PhosphorIconsRegular.bellRinging),
                    title: const Text('Only when something needs review'),
                    subtitle: const Text('Otherwise you also get a nudge to add missed payments'),
                    value: state.onlyWhenPending,
                    onChanged: controller.setOnlyWhenPending,
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.lightning),
                    title: const Text('Send a test alert'),
                    onTap: () async {
                      await ref.read(smsSourceProvider).requestNotifications();
                      await ref.read(reminderChannelProvider).sendTest();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
