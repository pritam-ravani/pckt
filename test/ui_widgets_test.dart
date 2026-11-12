import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pckt/core/theme/app_theme.dart';
import 'package:pckt/core/theme/icons.dart';
import 'package:pckt/ui/widgets.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: ListView(children: [child])),
    ),
  );

  testWidgets('a menu group shows its rows and taps through', (tester) async {
    var tapped = false;
    await pump(
      tester,
      MenuGroup(
        children: [
          MenuTile(icon: PhosphorIconsFill.clock, color: Colors.blue, title: 'Reminders', subtitle: 'Daily nudges', onTap: () => tapped = true),
          const MenuTile(icon: PhosphorIconsFill.coins, color: Colors.amber, title: 'Currency', value: 'INR'),
        ],
      ),
    );
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Daily nudges'), findsOneWidget);
    expect(find.text('INR'), findsOneWidget);
    await tester.tap(find.text('Reminders'));
    expect(tapped, isTrue);
  });

  testWidgets('a feature tile shows its title and live value', (tester) async {
    var tapped = false;
    await pump(
      tester,
      SizedBox(
        height: 120,
        child: FeatureTile(icon: PhosphorIconsFill.bank, color: Colors.blue, title: 'Accounts', value: '₹1.2L', onTap: () => tapped = true),
      ),
    );
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('₹1.2L'), findsOneWidget);
    await tester.tap(find.text('Accounts'));
    expect(tapped, isTrue);
  });

  testWidgets('a screen title shows its subtitle and actions', (tester) async {
    await pump(tester, const ScreenTitle('Money', subtitle: 'Your accounts, pay and plans', actions: [Text('Nov')]));
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Your accounts, pay and plans'), findsOneWidget);
    expect(find.text('Nov'), findsOneWidget);
  });
}
