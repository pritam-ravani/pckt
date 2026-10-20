import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';
import '../../providers.dart';

/// Toggle for the native "₹250 debited · HDFC" SMS notifications.
class SmsAlertsTile extends ConsumerWidget {
  const SmsAlertsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(smsAlertsProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(PhosphorIconsRegular.bellRinging),
        title: const Text('Instant alerts'),
        subtitle: const Text('Notify me when a bank SMS shows money moving'),
        value: on,
        onChanged: (v) => ref.read(smsAlertsProvider.notifier).set(v),
      ),
    );
  }
}
