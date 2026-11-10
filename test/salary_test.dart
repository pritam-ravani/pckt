import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/backup/backup_crypto.dart';
import 'package:pckt/data/backup/data_export.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/features/salary/salary_math.dart';
import 'package:pckt/features/stats.dart';

const _earn = PayslipLineKind.earning;
const _ded = PayslipLineKind.deduction;

const _lines = [
  PayslipLineDraft(kind: _earn, code: 'basic', label: 'Basic', amountMinor: 5000000),
  PayslipLineDraft(kind: _earn, code: PayslipCodes.bonus, label: 'Bonus', amountMinor: 1000000),
  PayslipLineDraft(kind: _ded, code: 'pf', label: 'PF', amountMinor: 600000),
  PayslipLineDraft(kind: _ded, code: PayslipCodes.food, label: 'Company food', amountMinor: 200000),
  PayslipLineDraft(kind: PayslipLineKind.employerContribution, code: 'pf_employer', label: 'PF', amountMinor: 600000),
];
const _net = 5200000;

void main() {
  late AppDatabase db;
  final october = DateTime(2026, 10);

  AppDatabase memory() => AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));

  setUp(() => db = memory());
  tearDown(() => db.close());

  Future<int> credit(int minor, DateTime at, {String merchant = 'Employer'}) =>
      db.addManual(amountMinor: minor, currency: 'INR', direction: TxnDirection.credit, at: at, merchant: merchant).then(
        (id) async {
          await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
            const TransactionsCompanion(categoryLocked: Value(false)),
          );
          return id;
        },
      );

  Future<PayslipView> only() async => (await db.allPayslips()).single;

  group('payslips', () {
    test('net is earnings minus deductions; employer share is in neither', () async {
      await db.savePayslip(month: october, lines: _lines);
      final v = await only();
      expect(v.grossMinor, 6000000);
      expect(v.deductionsMinor, 800000);
      expect(v.netMinor, _net);
      expect(v.employerMinor, 600000);
    });

    test('deductions never become transactions', () async {
      await db.savePayslip(month: october, lines: _lines);
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('the same month and employer cannot be added twice', () async {
      await db.savePayslip(month: october, employer: 'Acme', lines: _lines);
      await expectLater(db.savePayslip(month: october, employer: 'Acme', lines: _lines), throwsA(isA<DuplicatePayslipException>()));
      await db.savePayslip(month: october, employer: 'Second job', lines: _lines);
      expect(await db.allPayslips(), hasLength(2));
    });

    test('editing replaces the lines', () async {
      final id = await db.savePayslip(month: october, lines: _lines);
      await db.savePayslip(id: id, month: october, lines: _lines.take(1).toList());
      expect((await only()).lines, hasLength(1));
    });

    test('deleting removes its lines', () async {
      final id = await db.savePayslip(month: october, lines: _lines);
      await db.deletePayslip(id);
      expect(await db.select(db.payslipLines).get(), isEmpty);
    });
  });

  group('matching to a bank credit', () {
    test('finds the exact net pay and files it under Salary', () async {
      final txn = await credit(_net, DateTime(2026, 10, 31, 10));
      await db.savePayslip(month: october, lines: _lines);
      expect(await db.autoLinkPayslips(), 1);
      expect((await only()).salaryTxn?.id, txn);
      final row = await (db.select(db.transactions)..where((t) => t.id.equals(txn))).getSingle();
      final salary = (await db.allCategories()).firstWhere((c) => c.name == 'Salary');
      expect(row.categoryId, salary.id);
    });

    test('accepts pay credited early the next month, but not much later', () async {
      await credit(_net, DateTime(2026, 11, 20));
      await db.savePayslip(month: october, lines: _lines);
      expect(await db.autoLinkPayslips(), 0);
      final txn = await credit(_net, DateTime(2026, 11, 5));
      expect(await db.autoLinkPayslips(), 1);
      expect((await only()).salaryTxn?.id, txn);
    });

    test('ignores other amounts and transfers', () async {
      await credit(_net + 100, DateTime(2026, 10, 31));
      final transfer = await credit(_net, DateTime(2026, 10, 30));
      await db.setTransfer(transfer, true);
      await db.savePayslip(month: october, lines: _lines);
      expect(await db.autoLinkPayslips(), 0);
    });

    test('one credit is never used by two payslips', () async {
      await credit(_net, DateTime(2026, 10, 31));
      await db.savePayslip(month: october, employer: 'A', lines: _lines);
      await db.savePayslip(month: october, employer: 'B', lines: _lines);
      expect(await db.autoLinkPayslips(), 1);
    });

    test('a rejected match is not made again', () async {
      await credit(_net, DateTime(2026, 10, 31));
      final id = await db.savePayslip(month: october, lines: _lines);
      await db.autoLinkPayslips();
      await db.unlinkSalary(id);
      expect(await db.autoLinkPayslips(), 0);
      expect((await only()).salaryTxn, isNull);
    });

    test('changing the net pay drops the link; other edits keep it', () async {
      final txn = await credit(_net, DateTime(2026, 10, 31));
      final id = await db.savePayslip(month: october, lines: _lines);
      await db.linkSalary(id, txn);
      await db.savePayslip(id: id, month: october, employer: 'Acme', lines: _lines);
      expect((await only()).salaryTxn?.id, txn);
      await db.savePayslip(id: id, month: october, lines: _lines.skip(1).toList());
      expect((await only()).salaryTxn, isNull);
    });

    test('deleting the bank credit leaves the payslip unmatched', () async {
      final txn = await credit(_net, DateTime(2026, 10, 31));
      final id = await db.savePayslip(month: october, lines: _lines);
      await db.linkSalary(id, txn);
      await db.deleteTxn(txn);
      expect((await only()).salaryTxn, isNull);
    });

    test('merging the credit carries the link over', () async {
      final a = await credit(_net, DateTime(2026, 10, 31));
      final b = await credit(_net, DateTime(2026, 10, 31, 1));
      final id = await db.savePayslip(month: october, lines: _lines);
      await db.linkSalary(id, a);
      await db.mergeInto(a, b);
      expect((await only()).salaryTxn?.id, b);
    });
  });

  group('breakdown', () {
    test('compares net pay with spending and adds company food to personal food', () async {
      final cats = await db.allCategories();
      final food = cats.firstWhere((c) => c.name == 'Food & Dining');
      final shop = cats.firstWhere((c) => c.name == 'Shopping');
      await db.addManual(amountMinor: 300000, currency: 'INR', direction: TxnDirection.debit, at: DateTime(2026, 10, 5), categoryId: food.id);
      await db.addManual(amountMinor: 1000000, currency: 'INR', direction: TxnDirection.debit, at: DateTime(2026, 10, 6), categoryId: shop.id);
      await db.savePayslip(month: october, lines: _lines);

      final txns = await db.watchTxns(from: october, to: DateTime(2026, 11)).first;
      final b = SalaryBreakdown(await db.allPayslips(), MonthStats(txns, october));
      expect(b.netMinor, _net);
      expect(b.spentMinor, 1300000);
      expect(b.leftMinor, _net - 1300000);
      expect(b.bonusMinor, 1000000);
      expect(b.companyFoodMinor, 200000);
      expect(b.personalFoodMinor, 300000);
      expect(b.totalFoodMinor, 500000);
    });

    test('left over goes negative when spending passes net pay', () async {
      await db.addManual(amountMinor: _net + 1, currency: 'INR', direction: TxnDirection.debit, at: DateTime(2026, 10, 5));
      await db.savePayslip(month: october, lines: _lines);
      final txns = await db.watchTxns(from: october, to: DateTime(2026, 11)).first;
      expect(SalaryBreakdown(await db.allPayslips(), MonthStats(txns, october)).leftMinor, -1);
    });
  });

  group('backup', () {
    const fast = 2000;

    test('payslips round-trip through an encrypted backup', () async {
      await db.savePayslip(month: october, employer: 'Acme', lines: _lines);
      final plain = await DataExport(db).backupJson();
      final locked = await BackupCrypto.encrypt(plain, 'correct horse', iterations: fast);
      expect(locked, isNot(contains('Acme')));
      expect(BackupCrypto.isEncrypted(locked), isTrue);
      expect(BackupCrypto.isEncrypted(plain), isFalse);

      final fresh = memory();
      addTearDown(fresh.close);
      await DataExport(fresh).restore(await BackupCrypto.decrypt(locked, 'correct horse'));
      final v = (await fresh.allPayslips()).single;
      expect(v.payslip.employer, 'Acme');
      expect(v.netMinor, _net);
    });

    test('a wrong password is refused', () async {
      final locked = await BackupCrypto.encrypt('{"a":1}', 'correct horse', iterations: fast);
      await expectLater(BackupCrypto.decrypt(locked, 'wrong horse'), throwsA(isA<BackupFormatException>()));
    });

    test('tampering is detected', () async {
      final locked = await BackupCrypto.encrypt('{"a":1}', 'correct horse', iterations: fast);
      final changed = locked.replaceFirst('"iterations":$fast', '"iterations":${fast + 1}');
      await expectLater(BackupCrypto.decrypt(changed, 'correct horse'), throwsA(isA<BackupFormatException>()));
    });

    test('two backups of the same data differ', () async {
      expect(
        await BackupCrypto.encrypt('{"a":1}', 'correct horse', iterations: fast),
        isNot(await BackupCrypto.encrypt('{"a":1}', 'correct horse', iterations: fast)),
      );
    });

    test('a backup from before payslips existed still restores', () async {
      final json = await DataExport(db).backupJson();
      final old = json.replaceFirst('"schemaVersion": ${db.schemaVersion}', '"schemaVersion": 4');
      final fresh = memory();
      addTearDown(fresh.close);
      await DataExport(fresh).restore(old);
      expect(await fresh.allPayslips(), isEmpty);
    });
  });
}
