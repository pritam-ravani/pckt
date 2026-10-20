import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over flutter_local_notifications. Android only for now;
/// every call is a safe no-op elsewhere (and in tests).
class LocalNotifications {
  LocalNotifications();

  FlutterLocalNotificationsPlugin? _plugin;
  Future<bool>? _ready;

  static const _budgetChannel = AndroidNotificationDetails(
    'budget_alerts',
    'Budget alerts',
    channelDescription: 'When a monthly budget reaches 80% or is exceeded',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> _init() => _ready ??= () async {
    if (!isSupported) return false;
    try {
      final plugin = _plugin ??= FlutterLocalNotificationsPlugin();
      final ok = await plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      return ok ?? false;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      return false;
    }
  }();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin?.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Asks for POST_NOTIFICATIONS on Android 13+. True if granted.
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  Future<bool> areEnabled() async {
    if (!await _init()) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showBudgetAlert({required int id, required String title, required String body}) async {
    if (!await _init()) return;
    try {
      await _plugin!.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _budgetChannel),
        payload: 'budgets',
      );
    } catch (e) {
      debugPrint('Showing notification failed: $e');
    }
  }
}
