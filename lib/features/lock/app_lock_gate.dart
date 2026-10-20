import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/app_lock.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/db_encryption.dart';
import '../../ui/brand_mark.dart';

/// Wraps the whole app: tracks background time for the app lock and covers
/// everything with [LockScreen] while locked.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final ctrl = ref.read(appLockProvider.notifier);
    _lifecycle = AppLifecycleListener(onHide: ctrl.backgrounded, onShow: ctrl.resumed);
    // Re-apply "Hide in recent apps" (MainActivity also does on create).
    if (ref.read(appLockProvider).hideInRecents) SecureWindow.set(true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    ref.listen(appLockProvider.select((s) => s.message), (_, m) {
      if (m != null && !ref.read(appLockProvider).locked) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));
      }
    });
    return Stack(
      children: [
        // Keep the app mounted (state, scroll positions) but out of reach.
        ExcludeSemantics(excluding: locked, child: IgnorePointer(ignoring: locked, child: widget.child)),
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Ask right away; the button is there if the prompt was dismissed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockProvider.notifier).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appLockProvider);
    final text = Theme.of(context).textTheme;
    return Material(
      color: Palette.ink,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.2, -0.45),
            radius: 1.1,
            colors: [Color(0xFF1E1A3E), Palette.ink],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: Palette.inkRaised,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Palette.inkLine),
                    boxShadow: [
                      BoxShadow(color: Palette.violet.withValues(alpha: 0.25), blurRadius: 40, spreadRadius: 2),
                    ],
                  ),
                  child: const BrandMark(size: 112),
                ),
                const SizedBox(height: 28),
                Text('Pckt is locked', style: text.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  'Unlock with your fingerprint, face or screen lock.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: Colors.white70),
                ),
                if (s.message != null) ...[
                  const SizedBox(height: 14),
                  Text(s.message!, style: text.bodySmall?.copyWith(color: Palette.coral)),
                ],
                const Spacer(flex: 4),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.violet,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: s.authenticating ? null : ref.read(appLockProvider.notifier).unlock,
                  icon: s.authenticating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(PhosphorIconsBold.fingerprint),
                  label: const Text('Unlock'),
                ),
                const SizedBox(height: 12),
                if (DbEncryption.status.value.encrypted)
                  Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(PhosphorIconsBold.lockSimple, size: 14, color: Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      'Your data is encrypted on this phone',
                      style: text.bodySmall?.copyWith(color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
