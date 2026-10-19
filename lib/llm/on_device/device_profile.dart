import 'dart:io';

import 'package:flutter/services.dart';

/// Hardware facts the model picker needs. Read once from the native
/// `pckt/device` channel (see MainActivity.kt).
class DeviceProfile {
  const DeviceProfile({
    required this.totalRamBytes,
    required this.availRamBytes,
    required this.freeStorageBytes,
    required this.sdkInt,
    required this.abis,
    this.lowRamDevice = false,
    this.manufacturer = '',
    this.model = '',
    this.hardware = '',
    this.board = '',
    this.socManufacturer,
    this.socModel,
    this.hasOpenCl = false,
  });

  final int totalRamBytes;
  final int availRamBytes;
  final int freeStorageBytes;
  final int sdkInt;
  final List<String> abis;
  final bool lowRamDevice;
  final String manufacturer;
  final String model;
  final String hardware;
  final String board;

  /// e.g. "QTI" / "Google"; Android 12+ only.
  final String? socManufacturer;

  /// e.g. "SM8750", "Tensor G5"; Android 12+ only.
  final String? socModel;

  /// A GPU compute driver is present (OpenCL / Mali), so LiteRT can use the GPU.
  final bool hasOpenCl;

  static const _gb = 1024 * 1024 * 1024;

  /// Android reports a little less than the marketing figure (a "6 GB" phone
  /// shows ~5.5), so tiers below are set against reported values.
  double get ramGb => totalRamBytes / _gb;
  double get freeStorageGb => freeStorageBytes / _gb;

  bool get isArm64 => abis.contains('arm64-v8a');

  /// LiteRT-LM needs Android 11 (API 30) on arm64.
  bool get canRunLiteRt => isArm64 && sdkInt >= 30;

  String get chipLabel {
    final soc = [socManufacturer, socModel].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return soc.isNotEmpty ? soc : (hardware.isNotEmpty ? hardware : board);
  }

  factory DeviceProfile.fromMap(Map<Object?, Object?> m) => DeviceProfile(
    totalRamBytes: (m['totalRamBytes'] as num?)?.toInt() ?? 0,
    availRamBytes: (m['availRamBytes'] as num?)?.toInt() ?? 0,
    freeStorageBytes: (m['freeStorageBytes'] as num?)?.toInt() ?? 0,
    sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
    abis: [for (final a in (m['abis'] as List?) ?? const []) a.toString()],
    lowRamDevice: m['lowRamDevice'] == true,
    manufacturer: m['manufacturer']?.toString() ?? '',
    model: m['model']?.toString() ?? '',
    hardware: m['hardware']?.toString() ?? '',
    board: m['board']?.toString() ?? '',
    socManufacturer: m['socManufacturer']?.toString(),
    socModel: m['socModel']?.toString(),
    hasOpenCl: m['hasOpenCl'] == true,
  );

  static const _channel = MethodChannel('pckt/device');

  /// True on mobile data or a metered hotspot. False off Android.
  static Future<bool> isMetered() async =>
      Platform.isAndroid && (await _channel.invokeMethod<bool>('isMetered') ?? true);

  /// Android 13+ asks once, so the download's progress notification shows.
  static Future<void> requestNotifications() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('requestNotifications');
  }

  /// Null off Android (iOS support would need its own probe).
  static Future<DeviceProfile?> read() async {
    if (!Platform.isAndroid) return null;
    final m = await _channel.invokeMapMethod<Object?, Object?>('profile');
    return m == null ? null : DeviceProfile.fromMap(m);
  }
}
