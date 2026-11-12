import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// A daily check-in alert. [days] are ISO weekdays: 1 is Monday, 7 is Sunday.
class Reminder {
  const Reminder({required this.id, required this.hour, required this.minute, this.enabled = true, required this.days});

  factory Reminder.fromJson(Map<String, Object?> j) => Reminder(
    id: j['id']! as int,
    hour: j['h']! as int,
    minute: j['m']! as int,
    enabled: (j['on'] as bool?) ?? true,
    days: {for (final d in j['days']! as List) d as int},
  );

  final int id, hour, minute;
  final bool enabled;
  final Set<int> days;

  Map<String, Object?> toJson() => {'id': id, 'h': hour, 'm': minute, 'on': enabled, 'days': days.toList()..sort()};

  Reminder copyWith({bool? enabled, Set<int>? days}) =>
      Reminder(id: id, hour: hour, minute: minute, enabled: enabled ?? this.enabled, days: days ?? this.days);
}

class RemindersState {
  const RemindersState(this.reminders, {this.onlyWhenPending = false});
  final List<Reminder> reminders;

  /// Stay quiet unless something is waiting for review.
  final bool onlyWhenPending;
}

/// Native side, see Reminders.kt.
class ReminderChannel {
  static const _channel = MethodChannel('pckt/reminders');

  bool get isSupported => Platform.isAndroid;

  Future<void> reschedule() async {
    if (isSupported) await _channel.invokeMethod('reschedule');
  }

  Future<void> sendTest() async {
    if (isSupported) await _channel.invokeMethod('test');
  }

  Future<bool> canScheduleExact() async =>
      !isSupported || (await _channel.invokeMethod<bool>('canScheduleExact') ?? true);

  Future<void> openExactSettings() => _channel.invokeMethod('openExactSettings');
}

final reminderChannelProvider = Provider((ref) => ReminderChannel());

class RemindersController extends Notifier<RemindersState> {
  static const maxReminders = 12;
  static const everyDay = {1, 2, 3, 4, 5, 6, 7};

  @override
  RemindersState build() {
    final prefs = ref.read(prefsProvider);
    var list = <Reminder>[];
    try {
      list = [
        for (final j in jsonDecode(prefs.getString(PrefKeys.reminders) ?? '[]') as List)
          Reminder.fromJson((j as Map).cast()),
      ];
    } on Object {
      // Unreadable settings: start again rather than fail.
    }
    return RemindersState(_sorted(list), onlyWhenPending: prefs.getBool(PrefKeys.remindersOnlyPending) ?? false);
  }

  static List<Reminder> _sorted(List<Reminder> list) =>
      list..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

  Future<void> _store(List<Reminder> list, {bool? onlyWhenPending}) async {
    final prefs = ref.read(prefsProvider);
    await prefs.setString(PrefKeys.reminders, jsonEncode([for (final r in list) r.toJson()]));
    final only = onlyWhenPending ?? state.onlyWhenPending;
    await prefs.setBool(PrefKeys.remindersOnlyPending, only);
    state = RemindersState(_sorted(list), onlyWhenPending: only);
    await ref.read(reminderChannelProvider).reschedule();
  }

  /// False if that time already exists or the limit is reached.
  Future<bool> add(int hour, int minute) async {
    final list = state.reminders;
    if (list.length >= maxReminders || list.any((r) => r.hour == hour && r.minute == minute)) return false;
    final id = list.fold(0, (m, r) => r.id > m ? r.id : m) + 1;
    await _store([...list, Reminder(id: id, hour: hour, minute: minute, days: everyDay)]);
    return true;
  }

  Future<void> remove(int id) => _store(state.reminders.where((r) => r.id != id).toList());

  Future<void> setEnabled(int id, bool enabled) =>
      _store([for (final r in state.reminders) r.id == id ? r.copyWith(enabled: enabled) : r]);

  /// Turns one weekday on or off, always leaving at least one.
  Future<void> toggleDay(int id, int day) async {
    final r = state.reminders.firstWhere((r) => r.id == id);
    final days = {...r.days};
    if (!days.remove(day)) days.add(day);
    if (days.isEmpty) return;
    await _store([for (final x in state.reminders) x.id == id ? x.copyWith(days: days) : x]);
  }

  Future<void> setOnlyWhenPending(bool value) => _store(state.reminders, onlyWhenPending: value);
}

final remindersProvider = NotifierProvider<RemindersController, RemindersState>(RemindersController.new);
