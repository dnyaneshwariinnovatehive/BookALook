import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/screens/main_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/bottom_clearance.dart';
import 'package:customer_app/widgets/review_prompt_sheet.dart';

/// The shell's floating pill with the same footprint and the same extendBody
/// behaviour as MainScreen, around a page pushed inside a tab.
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

/// An Android phone with 3-button navigation: the strip at the bottom a sheet has
/// to stay clear of. Taller than a gesture bar, and it eats taps, not just paint.
double _useThreeButtonNavBar(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(bottom: 144);
  tester.view.viewPadding = const FakeViewPadding(bottom: 144);
  addTearDown(tester.view.reset);

  return 144 / tester.view.devicePixelRatio;
}

/// A page inside a tab that opens a sheet the way the salon page does after a
/// service is added: a run of copy, then a way out.
class _OffersPage extends StatelessWidget {
  const _OffersPage({this.rootNavigator = true});

  final bool rootNavigator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useRootNavigator: rootNavigator,
              backgroundColor: Colors.transparent,
              builder: (sheetContext) => Container(
                key: const Key('sheet'),
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  20 + sheetBottomInset(sheetContext),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 300, child: Placeholder()),
                    const Text('Haircut added'),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('No thanks', key: Key('no-thanks')),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Add'),
          ),
        ),
      ),
    );
  }
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
}

/// The last thing in a sheet has to sit clear of the system navigation bar, and
/// has to be pressable — a sheet whose "No thanks" is under the pill is a sheet
/// the customer cannot get out of.
void _expectClearOfSystemBar(
  WidgetTester tester,
  Finder lastThing,
  double systemInset,
) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

  expect(
    tester.getRect(lastThing).bottom,
    lessThan(screen.height - systemInset),
    reason: 'the sheet ends on the system navigation bar',
  );
}

void main() {
  testWidgets('the pill still owns the space it floats in', (tester) async {
    final systemInset = _useThreeButtonNavBar(tester);

    // Inside the shell the body gets the pill's whole footprint back as bottom
    // padding, on top of the system bar. Pages there can lean on bottomClearance.
    late double insideTab;
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) {
            insideTab = MediaQuery.paddingOf(context).bottom;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      insideTab,
      systemInset + MainScreen.navPillHeight + MainScreen.navPillMargin,
    );

    // Outside the shell there is no pill, only the system bar — which is why a
    // sheet opened off the root navigator has to add the inset itself.
    late double outsideTab;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            outsideTab = MediaQuery.paddingOf(context).bottom;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(outsideTab, systemInset);
  });

  testWidgets('a sheet off the root navigator clears the button bar', (
    tester,
  ) async {
    final inset = _useThreeButtonNavBar(tester);
    await tester.pumpWidget(_shell(const _OffersPage()));
    await _openSheet(tester);

    _expectClearOfSystemBar(tester, find.byKey(const Key('no-thanks')), inset);

    await tester.tap(find.byKey(const Key('no-thanks')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sheet')),
      findsNothing,
      reason: 'the tap went nowhere',
    );
    expect(
      find.byKey(const Key('pill')),
      findsOneWidget,
      reason: 'the pill survives the sheet',
    );
  });

  testWidgets('a sheet off the tab navigator also clears the pill', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(const _OffersPage(rootNavigator: false)));
    await _openSheet(tester);

    // The shell hands the pill's footprint back as padding, so the sheet's way
    // out lands above the pill even though the pill paints over the sheet.
    expect(
      tester.getRect(find.byKey(const Key('no-thanks'))).bottom,
      lessThan(tester.getRect(find.byKey(const Key('pill'))).top),
    );
  });

  testWidgets('the review prompt sheet clears the button bar too', (
    tester,
  ) async {
    final inset = _useThreeButtonNavBar(tester);
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ReviewPromptSheet.show(context, const {
                  'appointment_id': 1,
                  'salon_name': 'Glow & Go',
                  'provider_name': 'Riya',
                }),
                child: const Text('Rate'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Rate'));
    await tester.pumpAndSettle();

    _expectClearOfSystemBar(tester, find.text('Maybe later'), inset);
  });

  testWidgets('the sheet inset counts the keyboard and the bar, never both', (
    tester,
  ) async {
    Future<double> insetFor(MediaQueryData data) async {
      late double inset;
      await tester.pumpWidget(
        MediaQuery(
          data: data,
          child: Builder(
            builder: (context) {
              inset = sheetBottomInset(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return inset;
    }

    // Keyboard up: the keyboard is the whole inset, and padding is already zero.
    expect(
      await insetFor(
        const MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: 300),
          viewPadding: EdgeInsets.only(bottom: 28),
        ),
      ),
      300,
    );

    // Keyboard down: the system bar is.
    expect(
      await insetFor(
        const MediaQueryData(
          padding: EdgeInsets.only(bottom: 28),
          viewPadding: EdgeInsets.only(bottom: 28),
        ),
      ),
      28,
    );
  });
}
