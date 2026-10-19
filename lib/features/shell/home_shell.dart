import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/icons.dart';

import '../../llm/llm_providers.dart';
import '../../providers.dart';
import '../activity/add_transaction_sheet.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Pull new SMS whenever the app comes to the foreground.
    _lifecycle = AppLifecycleListener(onResume: _sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync() async {
    final report = await ref.read(smsSyncProvider.notifier).sync();
    if (!mounted || report == null || report.added + report.merged == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${report.added} new transaction${report.added == 1 ? '' : 's'}'
          '${report.merged > 0 ? ' · ${report.merged} duplicate${report.merged == 1 ? '' : 's'} merged' : ''}',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.shell.currentIndex;
    final review = ref.watch(reviewCountProvider).value ?? 0;
    // Keeps the AI jobs alive so they run after each sync.
    ref.listen(aiJobsProvider, (_, _) {});
    return Scaffold(
      body: widget.shell,
      floatingActionButton: index <= 1
          ? FloatingActionButton(
              onPressed: () => showAddTransactionSheet(context),
              tooltip: 'Add transaction',
              child: const Icon(PhosphorIconsBold.plus),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => widget.shell.goBranch(i, initialLocation: i == index),
        destinations: [
          const NavigationDestination(
            icon: Icon(PhosphorIconsRegular.house),
            selectedIcon: Icon(PhosphorIconsFill.house),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: review > 0,
              label: Text('$review'),
              child: const Icon(PhosphorIconsRegular.listBullets),
            ),
            selectedIcon: Badge(
              isLabelVisible: review > 0,
              label: Text('$review'),
              child: const Icon(PhosphorIconsFill.listBullets),
            ),
            label: 'Activity',
          ),
          const NavigationDestination(
            icon: Icon(PhosphorIconsRegular.chartPie),
            selectedIcon: Icon(PhosphorIconsFill.chartPie),
            label: 'Insights',
          ),
          const NavigationDestination(
            icon: Icon(PhosphorIconsRegular.sparkle),
            selectedIcon: Icon(PhosphorIconsFill.sparkle),
            label: 'Ask',
          ),
          const NavigationDestination(
            icon: Icon(PhosphorIconsRegular.gearSix),
            selectedIcon: Icon(PhosphorIconsFill.gearSix),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
