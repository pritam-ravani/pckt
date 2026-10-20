import 'dart:io';

import 'package:flutter/services.dart';

import '../../data/db/tables.dart';
import '../parser/parsed_txn.dart';

/// Reads the device SMS inbox through the native `pckt/sms` channel
/// (see MainActivity.kt). Android only — iOS gives apps no access to SMS.
class SmsSource {
  static const _channel = MethodChannel('pckt/sms');
  static const _device = MethodChannel('pckt/device');

  bool get isSupported => Platform.isAndroid;

  Future<bool> hasPermission() async => isSupported && (await _channel.invokeMethod<bool>('hasPermission') ?? false);

  /// Requests READ_SMS together with RECEIVE_SMS (live alerts). Returns
  /// whether inbox access was granted.
  Future<bool> requestPermission() async =>
      isSupported && (await _channel.invokeMethod<bool>('requestPermission') ?? false);

  /// RECEIVE_SMS, needed for real-time transaction alerts.
  Future<bool> hasReceivePermission() async =>
      isSupported && (await _channel.invokeMethod<bool>('hasReceivePermission') ?? false);

  /// Android 13+ runtime notification permission (no-op when already granted).
  Future<void> requestNotifications() async {
    if (isSupported) await _device.invokeMethod<void>('requestNotifications');
  }

  Future<bool> notificationsAllowed() async =>
      isSupported && (await _device.invokeMethod<bool>('notificationsAllowed') ?? false);

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
