import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/screens/main_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  testWidgets('MainScreen Scaffold has extendBody false and constrains body above bottom navbar',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 34);
    addTearDown(tester.view.reset);

    // Build the shell with a dummy page
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        extendBody: false,
        body: Container(key: const Key('dummyBody')),
        bottomNavigationBar: SafeArea(
          child: Container(
            key: const Key('dummyNav'),
            margin: const EdgeInsets.only(
              left: MainScreen.navPillMargin,
              right: MainScreen.navPillMargin,
              bottom: MainScreen.navPillMargin,
            ),
            height: MainScreen.navPillHeight,
          ),
        ),
      ),
    ));

    final bodyRect = tester.getRect(find.byKey(const Key('dummyBody')));
    final navRect = tester.getRect(find.byKey(const Key('dummyNav')));

    // Body ends strictly above the navbar container
    expect(bodyRect.bottom, equals(navRect.top));
    expect(bodyRect.bottom, lessThan(915.0));
  });

  testWidgets('Scrollable content in body stops strictly above bottomNavigationBar with extendBody false',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        extendBody: false,
        body: SingleChildScrollView(
          child: Column(
            children: List.generate(
              20,
              (i) => Container(
                key: ValueKey('item_$i'),
                height: 100,
                color: i.isEven ? Colors.red : Colors.blue,
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            key: const Key('navBar'),
            margin: const EdgeInsets.only(
              left: MainScreen.navPillMargin,
              right: MainScreen.navPillMargin,
              bottom: MainScreen.navPillMargin,
            ),
            height: MainScreen.navPillHeight,
          ),
        ),
      ),
    ));

    final navRect = tester.getRect(find.byKey(const Key('navBar')));
    final scrollable = tester.getRect(find.byType(SingleChildScrollView));

    // The scrollable area stops right at or above the navbar
    expect(scrollable.bottom, equals(navRect.top));

    // Drag / scroll up
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();

    // After scroll, the scrollable viewport still ends at navRect.top
    final scrollableAfterDrag = tester.getRect(find.byType(SingleChildScrollView));
    expect(scrollableAfterDrag.bottom, equals(navRect.top));
  });
}
