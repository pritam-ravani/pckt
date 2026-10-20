import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/app_lock.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/db_encryption.dart';
import '../../ui/widgets.dart';

/// Settings → Security: app lock, hide in recents, database encryption.
class SecurityCard extends ConsumerWidget {
  const SecurityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final ctrl = ref.read(appLockProvider.notifier);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          SwitchListTile(
            value: lock.enabled,
            onChanged: lock.authenticating
                ? null
                : (v) async {
                    final error = await ctrl.setEnabled(v);
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
            secondary: const Icon(PhosphorIconsRegular.fingerprint),
            title: const Text('App lock'),
            subtitle: const Text(
              'Ask for your fingerprint, face or screen lock when Pckt opens, or returns after 2 minutes away.',
            ),
          ),
          SwitchListTile(
            value: lock.hideInRecents,
            onChanged: ctrl.setHideInRecents,
            secondary: const Icon(PhosphorIconsRegular.eyeSlash),
            title: const Text('Hide in recent apps'),
            subtitle: const Text('Blanks Pckt in the app switcher and blocks screenshots.'),
          ),
          ValueListenableBuilder(
            valueListenable: DbEncryption.status,
            builder: (context, status, _) => ListTile(
              leading: Icon(
                status.encrypted ? PhosphorIconsRegular.lockSimple : PhosphorIconsRegular.warningCircle,
                color: status.encrypted ? Palette.mint : Palette.amber,
              ),
              title: Text(status.encrypted ? 'Database encrypted' : 'Database not encrypted'),
              subtitle: Text(
                status.encrypted
                    ? 'AES-256 (SQLCipher${status.cipherVersion == null ? '' : ' ${status.cipherVersion!.split(' ').first}'}). '
                          'The key never leaves this phone\'s keystore.'
                    : status.detail,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
