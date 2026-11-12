import '../../data/db/database.dart';
import '../stats.dart';

/// Stable codes of the standard payslip lines.
abstract final class PayslipCodes {
  static const bonus = 'bonus';
  static const food = 'food';
}

/// The lines a first payslip starts with. Empty ones are dropped on save.
const defaultPayslipLines = [
  PayslipLineDraft(kind: PayslipLineKind.earning, code: 'basic', label: 'Basic', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.earning, code: 'hra', label: 'HRA', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.earning, code: 'special', label: 'Special allowance', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.earning, code: PayslipCodes.bonus, label: 'Bonus', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.deduction, code: 'pf', label: 'PF (your share)', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.deduction, code: 'pt', label: 'Professional tax', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.deduction, code: 'tds', label: 'Income tax (TDS)', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.deduction, code: PayslipCodes.food, label: 'Company food', amountMinor: 0),
  PayslipLineDraft(kind: PayslipLineKind.employerContribution, code: 'pf_employer', label: 'PF (employer)', amountMinor: 0),
];

const _foodCategories = {'Food & Dining', 'Food Delivery', 'Tiffin & Mess', 'Coffee & Snacks'};

/// A month's pay against what was spent in that month.
class SalaryBreakdown {
  SalaryBreakdown(this.payslips, MonthStats stats)
    : spentMinor = stats.spent,
      personalFoodMinor = stats.categories
          .where((c) => _foodCategories.contains(c.category?.seedName ?? c.category?.name))
          .fold(0, (s, c) => s + c.amount);

  final List<PayslipView> payslips;
  final int spentMinor;
  final int personalFoodMinor;

  int _sum(int Function(PayslipView) of) => payslips.fold(0, (s, p) => s + of(p));

  int get grossMinor => _sum((p) => p.grossMinor);
  int get deductionsMinor => _sum((p) => p.deductionsMinor);
  int get netMinor => _sum((p) => p.netMinor);
  int get bonusMinor => _sum((p) => p.minorOf(PayslipCodes.bonus));

  /// Negative when the month's tracked spending exceeded net pay.
  int get leftMinor => netMinor - spentMinor;

  int get companyFoodMinor => _sum((p) => p.minorOf(PayslipCodes.food));
  int get totalFoodMinor => companyFoodMinor + personalFoodMinor;
}
