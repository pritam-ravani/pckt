import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/core/security/app_lock.dart';
import 'package:pckt/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth implements Authenticator {
  bool hasLock = true;
  final outcomes = <AuthOutcome>[];
  var prompts = 0;

  @override
  Future<bool> available() async => hasLock;

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    prompts++;
    return outcomes.isEmpty ? AuthOutcome.success : outcomes.removeAt(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAuth auth;
  late DateTime now;

  Future<ProviderContainer> make({bool enabled = false}) async {
    SharedPreferences.setMockInitialValues({SecurityPrefKeys.appLock: enabled});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        authenticatorProvider.overrideWithValue(auth),
        appLockProvider.overrideWith(() => AppLockController(now: () => now)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    auth = FakeAuth();
    now = DateTime(2026, 10, 20, 9);
  });

  test('off by default; never locks', () async {
    final c = await make();
    expect(c.read(appLockProvider).locked, isFalse);
    c.read(appLockProvider.notifier).backgrounded();
    now = now.add(const Duration(hours: 1));
    c.read(appLockProvider.notifier).resumed();
    expect(c.read(appLockProvider).locked, isFalse);
  });

  test('locked on cold start; unlocks after authentication', () async {
    final c = await make(enabled: true);
    expect(c.read(appLockProvider).locked, isTrue);
    auth.outcomes.add(AuthOutcome.canceled);
    await c.read(appLockProvider.notifier).unlock();
    expect(c.read(appLockProvider).locked, isTrue);
    await c.read(appLockProvider.notifier).unlock();
    expect(c.read(appLockProvider).locked, isFalse);
  });

  test('relocks only after more than 2 minutes in the background', () async {
    final c = await make(enabled: true);
    await c.read(appLockProvider.notifier).unlock();
    final ctrl = c.read(appLockProvider.notifier);

    ctrl.backgrounded();
    now = now.add(const Duration(seconds: 90));
    ctrl.resumed();
    expect(c.read(appLockProvider).locked, isFalse);

    ctrl.backgrounded();
    now = now.add(const Duration(minutes: 3));
    ctrl.resumed();
    expect(c.read(appLockProvider).locked, isTrue);
  });

  test('screen lock removed from the phone: the app lock turns itself off', () async {
    final c = await make(enabled: true);
    auth.outcomes.add(AuthOutcome.unavailable);
    await c.read(appLockProvider.notifier).unlock();
    final s = c.read(appLockProvider);
    expect(s.locked, isFalse);
    expect(s.enabled, isFalse);
    expect(s.message, isNotNull);
    expect(c.read(prefsProvider).getBool(SecurityPrefKeys.appLock), isFalse);
  });

  test('turning on needs a screen lock and one successful unlock', () async {
    final c = await make();
    final ctrl = c.read(appLockProvider.notifier);
    auth.hasLock = false;
    expect(await ctrl.setEnabled(true), isNotNull);
    expect(c.read(appLockProvider).enabled, isFalse);

    auth.hasLock = true;
    auth.outcomes.add(AuthOutcome.canceled);
    expect(await ctrl.setEnabled(true), isNull);
    expect(c.read(appLockProvider).enabled, isFalse);

    expect(await ctrl.setEnabled(true), isNull);
    expect(c.read(appLockProvider).enabled, isTrue);
    expect(c.read(appLockProvider).locked, isFalse);
  });
}
