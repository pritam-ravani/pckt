import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/activity/activity_screen.dart';
import 'features/assistant/assistant_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/lock/app_lock_gate.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'data/db/tables.dart';
import 'features/settings/email_connect_screen.dart';
import 'features/settings/llm_settings_screen.dart';
import 'features/settings/messages_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'providers.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final onboarded = ref.read(onboardedProvider);
      if (!onboarded && state.matchedLocation != '/welcome') return '/welcome';
      if (onboarded && state.matchedLocation == '/welcome') return '/';
      return null;
    },
    refreshListenable: _ProviderListenable(ref, onboardedProvider),
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/messages',
        builder: (_, s) =>
            MessagesScreen(source: s.uri.queryParameters['source'] == 'email' ? SourceKind.email : SourceKind.sms),
      ),
      GoRoute(path: '/email/connect', builder: (_, _) => const EmailConnectScreen()),
      GoRoute(path: '/llm', builder: (_, _) => const LlmSettingsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, s) => ActivityScreen(initialFilter: s.uri.queryParameters['filter']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/ask', builder: (_, _) => const AssistantScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
    ],
  );
});

class _ProviderListenable extends ChangeNotifier {
  _ProviderListenable(Ref ref, ProviderListenable<Object?> provider) {
    ref.listen(provider, (_, _) => notifyListeners());
  }
}

class PcktApp extends ConsumerWidget {
  const PcktApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Pckt',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ref.watch(themeModeProvider),
    routerConfig: ref.watch(_routerProvider),
    // Optional app lock over every route (off by default).
    builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
  );
}
