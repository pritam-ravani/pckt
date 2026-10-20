import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../providers.dart';

abstract final class SecurityPrefKeys {
  static const appLock = 'security.appLock';

  /// Read natively in MainActivity.onCreate too — keep the names in sync.
  static const hideInRecents = 'security.hideInRecents';
}

/// FLAG_SECURE on the Android window: blank Recents thumbnail, no
/// screenshots or screen recording.
abstract final class SecureWindow {
  static const _channel = MethodChannel('pckt/security');

  static Future<void> set(bool secure) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } catch (e) {
      debugPrint('setSecure failed: $e');
    }
  }
}

/// The device authentication used by the lock. Abstracted for tests.
abstract interface class Authenticator {
  /// Whether the phone has any screen lock (biometric or PIN/pattern/password).
  Future<bool> available();

  /// Biometric, falling back to the device PIN/pattern/password.
  Future<AuthOutcome> authenticate(String reason);
}

enum AuthOutcome { success, failed, canceled, unavailable }

class LocalAuthenticator implements Authenticator {
  LocalAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    try {
      // biometricOnly false: no fingerprint enrolled → the PIN works.
      final ok = await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
      return ok ? AuthOutcome.success : AuthOutcome.failed;
    } on LocalAuthException catch (e) {
      debugPrint('local_auth: ${e.code} ${e.description}');
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.uiUnavailable => AuthOutcome.unavailable,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout => AuthOutcome.canceled,
        _ => AuthOutcome.failed,
      };
    } catch (e) {
      debugPrint('local_auth: $e');
      return AuthOutcome.failed;
    }
  }
}

final authenticatorProvider = Provider<Authenticator>((ref) => LocalAuthenticator());

class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.authenticating = false,
    this.hideInRecents = false,
    this.message,
  });

  final bool enabled;
  final bool locked;
  final bool authenticating;
  final bool hideInRecents;
  final String? message;

  AppLockState copyWith({bool? enabled, bool? locked, bool? authenticating, bool? hideInRecents, String? message}) =>
      AppLockState(
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        authenticating: authenticating ?? this.authenticating,
        hideInRecents: hideInRecents ?? this.hideInRecents,
        message: message,
      );
}

/// Optional app lock: shown on a cold start and when the app returns after
/// more than [relockAfter] in the background.
class AppLockController extends Notifier<AppLockState> {
  AppLockController({this.relockAfter = const Duration(minutes: 2), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration relockAfter;
  final DateTime Function() _now;
  DateTime? _backgroundedAt;

  Authenticator get _auth => ref.read(authenticatorProvider);

  @override
  AppLockState build() {
    final prefs = ref.read(prefsProvider);
    final enabled = prefs.getBool(SecurityPrefKeys.appLock) ?? false;
    return AppLockState(
      enabled: enabled,
      locked: enabled,
      hideInRecents: prefs.getBool(SecurityPrefKeys.hideInRecents) ?? false,
    );
  }

  /// The app went to the background (paused / hidden).
  void backgrounded() {
    // The biometric prompt itself pauses the activity on some phones.
    if (state.authenticating) return;
    _backgroundedAt ??= _now();
  }

  /// The app is in front again.
  void resumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!state.enabled || state.locked || since == null) return;
    if (_now().difference(since) > relockAfter) state = state.copyWith(locked: true);
  }

  Future<void> unlock() async {
    if (!state.locked || state.authenticating) return;
    state = state.copyWith(authenticating: true);
    final outcome = await _auth.authenticate('Unlock Pckt');
    switch (outcome) {
      case AuthOutcome.success:
        state = state.copyWith(locked: false, authenticating: false);
      case AuthOutcome.unavailable:
        // The phone's screen lock was removed: a lock we can't open would
        // only lock the user out of their own data.
        await ref.read(prefsProvider).setBool(SecurityPrefKeys.appLock, false);
        state = state.copyWith(
          enabled: false,
          locked: false,
          authenticating: false,
          message: 'This phone has no screen lock any more, so Pckt\'s app lock was turned off.',
        );
      case AuthOutcome.canceled:
        state = state.copyWith(authenticating: false);
      case AuthOutcome.failed:
        state = state.copyWith(authenticating: false, message: 'Not recognised. Try again.');
    }
  }

  /// Turning the lock on needs a screen lock and one successful unlock, so
  /// the user knows it works before relying on it. Returns an error message.
  Future<String?> setEnabled(bool on) async {
    if (on) {
      if (!await _auth.available()) {
        return 'Set a fingerprint, face, PIN, pattern or password in Android settings first.';
      }
      state = state.copyWith(authenticating: true);
      final outcome = await _auth.authenticate('Confirm to turn on app lock');
      state = state.copyWith(authenticating: false);
      if (outcome != AuthOutcome.success) {
        return outcome == AuthOutcome.unavailable
            ? 'Set a fingerprint, face, PIN, pattern or password in Android settings first.'
            : null;
      }
    }
    await ref.read(prefsProvider).setBool(SecurityPrefKeys.appLock, on);
    state = state.copyWith(enabled: on, locked: false);
    return null;
  }

  Future<void> setHideInRecents(bool on) async {
    await ref.read(prefsProvider).setBool(SecurityPrefKeys.hideInRecents, on);
    await SecureWindow.set(on);
    state = state.copyWith(hideInRecents: on);
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
