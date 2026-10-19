import 'dart:io';

import 'package:flutter/services.dart';

import '../../data/db/tables.dart';
import '../parser/parsed_txn.dart';

/// Reads the device SMS inbox through the native `pckt/sms` channel
/// (see MainActivity.kt). Android only — iOS gives apps no access to SMS.
class SmsSource {
  static const _channel = MethodChannel('pckt/sms');

  bool get isSupported => Platform.isAndroid;

  Future<bool> hasPermission() async => isSupported && (await _channel.invokeMethod<bool>('hasPermission') ?? false);

  Future<bool> requestPermission() async =>
      isSupported && (await _channel.invokeMethod<bool>('requestPermission') ?? false);

  Future<List<RawInput>> readSince(DateTime since, {int limit = 20000}) async {
    if (!isSupported) return const [];
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('readInbox', {
      'sinceMillis': since.millisecondsSinceEpoch,
      'limit': limit,
    });
    return [
      for (final r in rows ?? const <Map<Object?, Object?>>[])
        RawInput(
          source: SourceKind.sms,
          externalId: r['id']! as String,
          sender: r['address']! as String,
          body: r['body']! as String,
          receivedAt: DateTime.fromMillisecondsSinceEpoch((r['date']! as num).toInt()),
        ),
    ];
  }
}
