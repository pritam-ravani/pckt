import 'dart:io';

import 'package:background_downloader/background_downloader.dart' show FileDownloader;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  await _initOnDeviceAi();
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const PcktApp()));
}

/// Registers the LiteRT-LM engine for on-device Gemma. A failure only
/// disables on-device AI; it must never stop the app from starting.
Future<void> _initOnDeviceAi() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    await FlutterEdgeAi.initialize(inferenceEngines: [const LiteRtLmEngine()]);
    // Model downloads start only from Settings, so a download WorkManager
    // revived after the app was killed is an orphan: stop it before it
    // quietly continues (possibly on mobile data).
    await FileDownloader().cancelAll(group: 'smart_downloads');
  } catch (e) {
    debugPrint('On-device AI unavailable: $e');
  }
}
