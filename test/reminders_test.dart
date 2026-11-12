import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/features/reminders/reminders.dart';
import 'package:pckt/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeChannel extends ReminderChannel {
  var reschedules = 0;

  @override
  Future<void> reschedule() async => reschedules++;
}

void main() {
  late ProviderContainer container;
  late SharedPreferences prefs;
  late _FakeChannel channel;

  Future<void> start([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    channel = _FakeChannel();
    container = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs), reminderChannelProvider.overrideWithValue(channel)],
    );
    addTearDown(container.dispose);
  }

  RemindersController controller() => container.read(remindersProvider.notifier);
  RemindersState state() => container.read(remindersProvider);

  test('reminders are kept in time order, every day by default, and scheduled', () async {
    await start();
    await controller().add(21, 0);
    await controller().add(9, 30);
    expect(state().reminders.map((r) => r.hour), [9, 21]);
    expect(state().reminders.first.days, {1, 2, 3, 4, 5, 6, 7});
    expect(channel.reschedules, 2);
  });

  test('saves in the format the native scheduler reads', () async {
    await start();
    await controller().add(9, 30);
    expect(jsonDecode(prefs.getString('reminders.v1')!), [
      {'id': 1, 'h': 9, 'm': 30, 'on': true, 'days': [1, 2, 3, 4, 5, 6, 7]},
    ]);
  });

  test('settings survive a restart', () async {
    await start();
    await controller().add(9, 30);
    await controller().setOnlyWhenPending(true);
    final restarted = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs), reminderChannelProvider.overrideWithValue(channel)],
    );
    addTearDown(restarted.dispose);
    final s = restarted.read(remindersProvider);
    expect(s.reminders.single.minute, 30);
    expect(s.onlyWhenPending, isTrue);
  });

  test('the same time cannot be added twice', () async {
    await start();
    expect(await controller().add(9, 0), isTrue);
    expect(await controller().add(9, 0), isFalse);
    expect(state().reminders, hasLength(1));
  });

  test('any number of times up to the limit', () async {
    await start();
    for (var h = 0; h < RemindersController.maxReminders; h++) {
      expect(await controller().add(h, 0), isTrue);
    }
    expect(await controller().add(23, 0), isFalse);
  });

  test('turning off, deleting and changing days', () async {
    await start();
    await controller().add(9, 0);
    final id = state().reminders.single.id;
    await controller().setEnabled(id, false);
    expect(state().reminders.single.enabled, isFalse);
    await controller().toggleDay(id, 7);
    expect(state().reminders.single.days, {1, 2, 3, 4, 5, 6});
    await controller().remove(id);
    expect(state().reminders, isEmpty);
  });

  test('the last remaining day cannot be removed', () async {
    await start({
      'reminders.v1': jsonEncode([
        {'id': 1, 'h': 9, 'm': 0, 'on': true, 'days': [3]},
      ]),
    });
    await controller().toggleDay(1, 3);
    expect(state().reminders.single.days, {3});
  });

  test('damaged settings start empty instead of failing', () async {
    await start({'reminders.v1': 'not json'});
    expect(state().reminders, isEmpty);
  });
}
