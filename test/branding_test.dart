import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pckt/core/app_info.dart';
import 'package:pckt/core/theme/app_theme.dart';
import 'package:pckt/data/backup/data_export.dart';
import 'package:pckt/features/settings/about_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('every font the theme asks for is bundled', () async {
    final families = <String?>{
      for (final theme in [AppTheme.light(), AppTheme.dark()]) ...[
        for (final style in [
          theme.textTheme.displayLarge,
          theme.textTheme.displayMedium,
          theme.textTheme.displaySmall,
          theme.textTheme.headlineLarge,
          theme.textTheme.headlineMedium,
          theme.textTheme.headlineSmall,
          theme.textTheme.titleLarge,
          theme.textTheme.titleMedium,
          theme.textTheme.titleSmall,
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.bodySmall,
          theme.textTheme.labelLarge,
          theme.textTheme.labelMedium,
          theme.textTheme.labelSmall,
        ])
          style?.fontFamily,
      ],
    };
    expect(families.difference({'Inter_regular', 'Inter_500', 'Manrope_regular', 'Manrope_500'}), isEmpty);
    await GoogleFonts.pendingFonts();
  });

  test('About version matches pubspec', () {
    final match = RegExp(r'^version: ([0-9.]+)\+', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(AppInfo.version, match!.group(1));
  });

  test('old backups stay restorable', () {
    expect(DataExport.format, 'pckt-backup');
  });

  test('the GPL text ships with the app', () async {
    expect(await rootBundle.loadString('LICENSE'), contains('GNU GENERAL PUBLIC LICENSE'));
  });

  testWidgets('About shows attribution, warranty notice and source link', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const AboutScreen()));
    await tester.pump();
    expect(find.textContaining('Based on Pckt'), findsOneWidget);
    expect(find.textContaining('NO WARRANTY'), findsOneWidget);
    expect(find.text(AppInfo.sourceUrl), findsOneWidget);
    expect(find.text('Open-source licences'), findsOneWidget);
  });
}
