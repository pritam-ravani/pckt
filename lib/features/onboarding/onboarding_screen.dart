import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';

import '../../core/theme/palette.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  var _months = 6;
  var _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    final ok = await ref.read(smsSyncProvider.notifier).connect(months: _months);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.read(onboardedProvider.notifier).complete();
    } else {
      final err = ref.read(smsSyncProvider).error;
      if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.read(smsSourceProvider).isSupported;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const _Hero(),
              const SizedBox(height: 36),
              Text('Your money,\ntracked for you.', style: context.text.displaySmall?.copyWith(height: 1.05)),
              const SizedBox(height: 14),
              Text(
                'Pckt reads bank & UPI alerts, sorts every rupee into categories, '
                'and never counts the same payment twice.',
                style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 24),
              const _Point(
                icon: PhosphorIconsFill.shieldCheck,
                text: 'Parsed on-device — messages never leave your phone',
              ),
              const _Point(icon: PhosphorIconsFill.gitMerge, text: 'Smart dedup across SMS and email'),
              const _Point(icon: PhosphorIconsFill.sparkle, text: 'Bring your own AI for insights (coming soon)'),
              const Spacer(),
              if (supported) ...[
                Text(
                  'Import history',
                  style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const [1, 3, 6, 12])
                      ChoiceChip(
                        label: Text(m == 12 ? '1 year' : '$m mo'),
                        selected: _months == m,
                        onSelected: (_) => setState(() => _months = m),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(PhosphorIconsBold.chatText),
                  label: Text(_busy ? 'Reading your messages…' : 'Connect SMS'),
                ),
              ],
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => ref.read(onboardedProvider.notifier).complete(),
                  child: Text(supported ? 'Skip for now' : 'Get started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: Palette.mint, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    ),
  );
}

/// Layered category badges floating over a gradient orb.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, Color color, double angle) => Transform.rotate(
      angle: angle,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.outlineVariant),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Icon(icon, color: color, size: 30),
      ),
    );

    return SizedBox(
      height: 150,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 40,
            top: 0,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Palette.violet.withValues(alpha: 0.45), Colors.transparent]),
              ),
            ),
          ),
          Positioned(left: 0, top: 50, child: tile(PhosphorIconsFill.forkKnife, Palette.categories[1], -0.12)),
          Positioned(left: 78, top: 10, child: tile(PhosphorIconsFill.lightning, Palette.categories[0], 0.08)),
          Positioned(left: 156, top: 58, child: tile(PhosphorIconsFill.shoppingBag, Palette.categories[4], 0.14)),
          Positioned(left: 232, top: 14, child: tile(PhosphorIconsFill.trendUp, Palette.mint, -0.06)),
        ],
      ),
    );
  }
}
