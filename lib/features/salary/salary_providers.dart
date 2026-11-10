import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../stats.dart';

final payslipsProvider = StreamProvider<List<PayslipView>>((ref) => ref.watch(databaseProvider).watchPayslips());

final monthStatsProvider = StreamProvider.family<MonthStats, DateTime>((ref, month) {
  return ref
      .watch(databaseProvider)
      .watchTxns(from: monthStart(month), to: nextMonth(month))
      .map((txns) => MonthStats(txns, month));
});
