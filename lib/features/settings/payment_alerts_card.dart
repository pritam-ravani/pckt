import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import '../capture/payment_capture.dart';

/// Settings → Sources: saves Google Pay, Paytm and PhonePe payments from
/// their notifications. Off until the user turns it on.
class PaymentAlertsCard extends ConsumerStatefulWidget {
  const PaymentAlertsCard({super.key});

  @override
  ConsumerState<PaymentAlertsCard> createState() => _PaymentAlertsCardState();
}

class _PaymentAlertsCardState extends ConsumerState<PaymentAlertsCard> {
  late final AppLifecycleListener _lifecycle;
  var _access = false;

  bool get _on => ref.read(prefsProvider).getBool(PrefKeys.notifCapture) ?? false;

  @override
  void initState() {
    super.initState();
    // The user grants access in system settings and comes back.
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  Future<void> _refresh() async {
    final access = await ref.read(paymentCaptureChannelProvider).hasAccess();
    if (mounted) setState(() => _access = access);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _set(bool on) async {
    await ref.read(prefsProvider).setBool(PrefKeys.notifCapture, on);
    setState(() {});
    if (!on) return;
    await ref.read(smsSourceProvider).requestNotifications();
    await ref.read(paymentCaptureProvider).refreshHints();
    await _refresh();
    if (!_access && mounted) await _showSetup();
  }

  Future<void> _showSetup() {
    final channel = ref.read(paymentCaptureChannelProvider);
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Two quick settings'),
        content: const Text(
          '1. Open App info. Tap ⋮ at the top right and choose Allow restricted settings. '
          'While you are there, set Battery to allow background activity.\n\n'
          '2. Open Notification access and switch on PennyWise.\n\n'
          'Android shows a broad warning, but PennyWise only keeps notifications from '
          'Google Pay, Paytm and PhonePe. Nothing is sent anywhere.',
        ),
        actions: [
          TextButton(onPressed: channel.openAppDetails, child: const Text('App info')),
          TextButton(onPressed: channel.openAccessSettings, child: const Text('Notification access')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsSetup = _on && !_access;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(PhosphorIconsRegular.bellRinging),
            title: const Text('Payment app alerts'),
            subtitle: const Text('Save Google Pay, Paytm and PhonePe payments and ask for a category'),
            value: _on,
            onChanged: _set,
          ),
          if (needsSetup)
            ListTile(
              leading: const Icon(PhosphorIconsRegular.warningCircle),
              title: const Text('Finish setup'),
              subtitle: const Text('PennyWise needs notification access'),
              trailing: const Icon(PhosphorIconsBold.caretRight, size: 16),
              onTap: _showSetup,
            ),
        ],
      ),
    );
  }
}
