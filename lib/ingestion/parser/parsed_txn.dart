import '../../data/db/tables.dart';

/// A message as it arrives from any source, before parsing.
class RawInput {
  const RawInput({
    required this.source,
    required this.externalId,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  final SourceKind source;
  final String externalId;
  final String sender;
  final String body;
  final DateTime receivedAt;
}

/// Structured transaction extracted from a message.
class ParsedTxn {
  const ParsedTxn({
    required this.amountMinor,
    required this.direction,
    required this.occurredAt,
    required this.mode,
    required this.confidence,
    this.currency,
    this.convertedMinor,
    this.convertedCurrency,
    this.merchant,
    this.counterparty,
    this.accountHint,
    this.reference,
    this.institution,
    this.isPersonToPerson = false,
    this.transferHint = false,
  });

  /// In minor units of [currency].
  final int amountMinor;

  /// ISO 4217 code; null when the source didn't say (the home currency).
  final String? currency;

  /// The same amount in another currency when the message states it, e.g.
  /// the rupee equivalent of a card spend abroad.
  final int? convertedMinor;
  final String? convertedCurrency;

  final TxnDirection direction;
  final DateTime occurredAt;
  final PaymentMode mode;

  /// 0..1 — how sure the parser is this is a real, completed transaction.
  final double confidence;
  final String? merchant;
  final String? counterparty;
  final String? accountHint;
  final String? reference;
  final String? institution;
  final bool isPersonToPerson;

  /// Message itself suggests a movement between own accounts
  /// (credit-card bill payment, "to self", etc.).
  final bool transferHint;

  @override
  String toString() =>
      'ParsedTxn(${direction.name} $amountMinor${currency == null ? '' : ' $currency'}'
      '${convertedMinor == null ? '' : ' (= $convertedMinor $convertedCurrency)'}, merchant: $merchant, cp: $counterparty, '
      'acct: $accountHint, ref: $reference, mode: ${mode.name}, inst: $institution, conf: $confidence)';
}

/// Turns one raw message into a [ParseResult]. One implementation per source
/// format (SMS, email, …), registered in [IngestionService.parsers].
abstract interface class MessageParser {
  ParseResult parse(RawInput input);
}

sealed class ParseResult {
  const ParseResult();
}

final class Parsed extends ParseResult {
  const Parsed(this.txn);
  final ParsedTxn txn;
}

final class Ignored extends ParseResult {
  const Ignored(this.reason);
  final String reason;
}

/// Looked financial but we could not extract a transaction — a candidate
/// for the LLM fallback.
final class Unparsed extends ParseResult {
  const Unparsed(this.reason);
  final String reason;
}
