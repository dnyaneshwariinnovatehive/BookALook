import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/screens/phone_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/auth/otp_boxes.dart';
import 'package:customer_app/widgets/logo_marquee.dart';

/// Screen-reader and motion behaviour of the custom controls.
void main() {
  testWidgets('the OTP field is announced once, as a labelled field', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: OtpBoxes(controller: TextEditingController(text: '12'))),
    ));
    await tester.pump();

    // The real field used to sit under a zero Opacity, which drops it from
    // the semantics tree entirely: nothing to focus, nothing to type into.
    expect(find.bySemanticsLabel(RegExp('One-time code, 6 digits')), findsOneWidget);
    // And the six painted boxes are not read out as stray digits.
    expect(find.bySemanticsLabel('1'), findsNothing);
    handle.dispose();
  });

  testWidgets('the Login / Sign Up switch reports which mode is selected', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const PhoneScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    Finder tab(String label) => find.descendant(
          of: find.byKey(PhoneScreen.modeRailKey),
          matching: find.text(label),
        );

    expect(tester.getSemantics(tab('Login')),
        containsSemantics(label: 'Login', isButton: true, isSelected: true));
    expect(tester.getSemantics(tab('Sign Up')),
        containsSemantics(label: 'Sign Up', isButton: true, isSelected: false));

    await tester.tap(tab('Sign Up'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSemantics(tab('Sign Up')), containsSemantics(isSelected: true));
    handle.dispose();
  });

  testWidgets('the marquee holds still for a screen reader', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              child: InfiniteLogoMarquee(
                itemCount: 3,
                itemExtent: 80,
                height: 100,
                gap: 12,
                pixelsPerSecond: 30,
                itemBuilder: (_, i) => Text('logo $i'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // The static, swipeable strip: each logo once, not the looping copies.
    expect(
      find.descendant(of: find.byType(InfiniteLogoMarquee), matching: find.byType(ListView)),
      findsOneWidget,
    );
    expect(find.text('logo 0'), findsOneWidget);

    final before = tester.getTopLeft(find.text('logo 0'));
    await tester.pump(const Duration(seconds: 10));
    expect(tester.getTopLeft(find.text('logo 0')), before);
  });
}
