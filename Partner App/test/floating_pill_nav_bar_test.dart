import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/floating_pill_nav_bar.dart';

void main() {
  const items = [
    PillNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    PillNavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_month_rounded, label: 'Schedule'),
    PillNavItem(icon: Icons.person_add_alt_1_outlined, activeIcon: Icons.person_add_alt_1_rounded, label: 'Add Walk-in'),
    PillNavItem(icon: Icons.person_outline, activeIcon: Icons.person_rounded, label: 'Profile'),
  ];

  Future<void> pump(WidgetTester tester, {required ValueChanged<int> onTap, int index = 0}) async {
    // A small phone, where the longest label is most likely to overflow.
    await tester.binding.setSurfaceSize(const Size(360, 700));
    var current = index;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          bottomNavigationBar: FloatingPillNavBar(
            items: items,
            currentIndex: current,
            onTap: (i) {
              onTap(i);
              setState(() => current = i);
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('keeps the provider tab names and fits on a small phone', (tester) async {
    await pump(tester, onTap: (_) {});

    for (final label in ['Home', 'Schedule', 'Add Walk-in', 'Profile']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a tab selects it and fills its icon', (tester) async {
    final taps = <int>[];
    await pump(tester, onTap: taps.add);

    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();

    expect(taps, [1]);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });
}
