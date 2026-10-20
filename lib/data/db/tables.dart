import 'package:drift/drift.dart';

/// Where a piece of evidence came from.
enum SourceKind { sms, email, manual, shortcut }

enum TxnDirection { debit, credit }

/// Payment rail detected from the message.
enum PaymentMode { upi, card, netbanking, neft, imps, rtgs, atm, wallet, cash, other }

/// How confident we are that a transaction is real and correctly read.
enum TxnStatus { confirmed, needsReview }

/// Lifecycle of a raw message as it moves through ingestion.
enum ParseStatus { parsed, merged, ignored, failed, pendingLlm }

enum AccountKind { bank, creditCard, wallet, cash }

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get kind => intEnum<AccountKind>()();
  TextColumn get institution => text().nullable()();

  /// Last 3–4 digits of account / card number, used to match messages.
  TextColumn get last4 => text().nullable()();
  IntColumn get color => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Key into [CategoryIcons]; stored as text so icon sets can change.
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Name of the seed category this row was created from (null for
  /// user-made ones). Keeps keyword rules working after a rename.
  TextColumn get seedName => text().nullable()();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stored in paise to avoid floating point drift.
  IntColumn get amountMinor => integer()();
  IntColumn get direction => intEnum<TxnDirection>()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get merchant => text().nullable()();

  /// VPA / raw counterparty string as it appeared in the message.
  TextColumn get counterparty => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get accountId => integer().nullable().references(Accounts, #id)();
  TextColumn get accountHint => text().nullable()();
  IntColumn get mode => intEnum<PaymentMode>()();

  /// UPI ref / RRN / bank reference. The strongest dedup signal.
  TextColumn get reference => text().nullable()();
  IntColumn get status => intEnum<TxnStatus>()();

  /// Self-transfers between own accounts are excluded from spend.
  BoolColumn get isTransfer => boolean().withDefault(const Constant(false))();
  BoolColumn get categoryLocked => boolean().withDefault(const Constant(false))();

  /// Set when dedup found a borderline match the user should confirm.
  IntColumn get duplicateOfId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Every SMS / email we have looked at, parsed or not. Keeping the raw
/// evidence lets us re-parse after parser upgrades and explain merges.
class RawMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get source => intEnum<SourceKind>()();

  /// Provider-side id (SMS _id, Gmail message id) — unique per source.
  TextColumn get externalId => text()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  IntColumn get parseStatus => intEnum<ParseStatus>()();
  TextColumn get ignoreReason => text().nullable()();
  IntColumn get transactionId => integer().nullable().references(Transactions, #id, onDelete: KeyAction.setNull)();

  /// Dedup score that linked this message to an existing transaction.
  RealColumn get mergeScore => real().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {source, externalId},
  ];
}

/// Monthly spending limits. A row with a null [categoryId] is the overall
/// monthly budget (at most one); others cap a single category. Budgets
/// repeat every month until removed or paused.
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id, onDelete: KeyAction.cascade)();

  /// Limit per month, in paise.
  IntColumn get amountMinor => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Learned "merchant → category" mappings, created when the user
/// recategorises a transaction.
class MerchantRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get pattern => text().unique()();
  IntColumn get categoryId => integer().references(Categories, #id, onDelete: KeyAction.cascade)();
}
