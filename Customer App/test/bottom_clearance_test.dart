import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/screens/main_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/bottom_clearance.dart';

/// The shell's floating pill with the same footprint and the same
/// extendBody behaviour as MainScreen, around a page pushed inside a tab.
Widget _shell(Widget page) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        extendBody: true,
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => page),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            key: const Key('pill'),
            margin: const EdgeInsets.only(
              left: MainScreen.navPillMargin,
              right: MainScreen.navPillMargin,
              bottom: MainScreen.navPillMargin,
            ),
            height: MainScreen.navPillHeight,
            color: Colors.purple,
          ),
        ),
      ),
    );

/// A long list whose items are keyed, padded the way the screens pad theirs.
class _Page extends StatelessWidget {
  const _Page({this.safeArea = false});

  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    Widget list(BuildContext context) => ListView.builder(
          padding: EdgeInsets.only(bottom: bottomClearance(context)),
          itemCount: 30,
          itemBuilder: (_, i) => SizedBox(key: ValueKey('item-$i'), height: 80),
        );

    return Scaffold(
      body: safeArea ? SafeArea(child: Builder(builder: list)) : Builder(builder: list),
    );
  }
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
  }
  await tester.pump(const Duration(seconds: 1));
}

void _expectLastItemClear(WidgetTester tester) {
  final last = tester.getRect(find.byKey(const ValueKey('item-29')));
  final pill = tester.getRect(find.byKey(const Key('pill')));
  expect(last.bottom, lessThanOrEqualTo(pill.top),
      reason: 'the last row ends at ${last.bottom}, under the pill starting at ${pill.top}');
}

void main() {
  testWidgets('the last item scrolls clear of the pill', (tester) async {
    await tester.pumpWidget(_shell(const _Page()));
    await _scrollToEnd(tester);
    _expectLastItemClear(tester);
  });

  testWidgets('a page inside a SafeArea is cleared too, without double padding',
      (tester) async {
    await tester.pumpWidget(_shell(const _Page(safeArea: true)));
    await _scrollToEnd(tester);
    _expectLastItemClear(tester);
  });

  testWidgets('landscape, with a gesture-bar inset, still clears the pill', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 63);
    tester.view.viewPadding = const FakeViewPadding(bottom: 63);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(const _Page()));
    await _scrollToEnd(tester);
    _expectLastItemClear(tester);
  });

  testWidgets('outside the shell it is only the safe area and the gap', (tester) async {
    late double clearance;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        clearance = bottomClearance(context);
        return const SizedBox();
      }),
    ));
    expect(clearance, 24);
  });
}
