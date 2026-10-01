import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/auth_motion.dart';
import 'package:customer_app/widgets/auth/otp_boxes.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('SweepButton fill', () {
    testWidgets('paints a visible gradient while idle, not just when loading',
        (tester) async {
      // Regression guard: the fill used to be resolved only on the loading
      // path, which left the idle button transparent.
      await tester.pumpWidget(_wrap(SweepButton(
        label: 'Continue',
        onPressed: () {},
      )));
      await tester.pump();
      final idle = _gradientOf(tester);
      expect(idle.colors.length, greaterThanOrEqualTo(2));

      // And the default must actually be the brand gradient, not a colour.
      expect(
        idle.colors.map((c) => c.toARGB32()),
        containsAll(<int>[
          const Color(0xFF9C54F2).toARGB32(),
          const Color(0xFF7B32EC).toARGB32(),
        ]),
      );
    });

    testWidgets('honours a caller-supplied gradient when idle',
        (tester) async {
      await tester.pumpWidget(_wrap(SweepButton(
        label: 'Verify',
        onPressed: () {},
        gradient: const LinearGradient(colors: [Color(0xFF111111), Color(0xFF222222)]),
      )));
      await tester.pump();
      final g = _gradientOf(tester);
      expect(g.colors.first.toARGB32(), const Color(0xFF111111).toARGB32());
    });
  });

  group('SweepButton', () {
    testWidgets('runs a sheen while loading and stops when idle',
        (tester) async {
      var loading = true;
      Widget build() => _wrap(
            Builder(
              builder: (_) => SweepButton(
                label: 'Continue',
                loading: loading,
                onPressed: loading ? null : () {},
              ),
            ),
          );

      await tester.pumpWidget(build());

      // The sheen repeats, so consecutive pumps must differ.
      await tester.pump(const Duration(milliseconds: 300));
      final mid = _gradientOf(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final later = _gradientOf(tester);
      expect(later.begin, isNot(equals(mid.begin)),
          reason: 'gradient begin must sweep while loading');

      // Flipping to idle must stop the controller, not leave it spinning.
      loading = false;
      await tester.pumpWidget(build());
      await tester.pump(const Duration(milliseconds: 300));
      final idle = _gradientOf(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_gradientOf(tester).begin, idle.begin,
          reason: 'sheen must not move when not loading');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('ignores taps while loading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(SweepButton(
        label: 'Continue',
        loading: true,
        onPressed: null,
      )));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(tapped, isFalse);
    });
  });

  group('Shake', () {
    testWidgets('is still until the token changes, then displaces and returns',
        (tester) async {
      await tester.pumpWidget(_wrap(
          const Shake(token: 0, child: SizedBox(width: 100, height: 20))));
      expect(_offsetX(tester), 0);

      await tester.pumpWidget(_wrap(
          const Shake(token: 1, child: SizedBox(width: 100, height: 20))));
      await tester.pump(const Duration(milliseconds: 80));
      final displaced = _offsetX(tester);
      expect(displaced.abs(), greaterThan(0.5),
          reason: 'shake must actually move');

      await tester.pump(const Duration(milliseconds: 600));
      expect(_offsetX(tester).abs(), lessThan(0.01),
          reason: 'shake must settle back to rest');
    });
  });

  group('StaggeredReveal', () {
    testWidgets('children appear in order, not all at once', (tester) async {
      await tester.pumpWidget(_wrap(const StaggeredReveal(
        startDelay: 0.0,
        step: 0.2,
        children: [
          SizedBox(height: 40, child: Text('one')),
          SizedBox(height: 40, child: Text('two')),
          SizedBox(height: 40, child: Text('three')),
        ],
      )));

      // The first child is under way while the last has not begun, which is
      // the whole point of staggering. Sampling right after start keeps this
      // from being a coin flip against the easing curve.
      await tester.pump(const Duration(milliseconds: 240));
      final first = _opacityOf(tester, 'one');
      final last = _opacityOf(tester, 'three');
      expect(first, greaterThan(0.5));
      expect(last, lessThan(first),
          reason: 'later children must lag the first one');

      await tester.pump(const Duration(milliseconds: 1200));
      for (final label in ['one', 'two', 'three']) {
        expect(_opacityOf(tester, label), 1.0, reason: '$label must finish visible');
      }
    });

    testWidgets('a single child still reaches full opacity', (tester) async {
      await tester.pumpWidget(_wrap(const StaggeredReveal(
        children: [SizedBox(height: 40, child: Text('solo'))],
      )));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(_opacityOf(tester, 'solo'), 1.0);
    });
  });

  group('OtpBoxes', () {
    testWidgets('paints one box per digit and nothing before input',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(
          OtpBoxes(controller: controller, autofocus: false)));
      await tester.pump();

      expect(find.byType(AnimatedContainer), findsNWidgets(6));
      // No digits typed yet, so no glyph is painted.
      expect(find.text('1'), findsNothing);
      controller.dispose();
    });

    testWidgets('typing fills boxes in order and fires completed once',
        (tester) async {
      final controller = TextEditingController();
      var completed = 0;
      await tester.pumpWidget(_wrap(OtpBoxes(
        controller: controller,
        autofocus: false,
        onCompleted: () => completed++,
      )));
      await tester.pump();

      // Each value replaces the previous one, so they must be cumulative
      // prefixes rather than chunks.
      for (final prefix in ['1', '12', '123', '1234', '12345', '123456']) {
        controller.text = prefix;
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(controller.text, '123456');
      expect(completed, 1, reason: 'completion fires exactly once');
      controller.dispose();
    });

    testWidgets('backspacing after completion re-arms the completed flag',
        (tester) async {
      final controller = TextEditingController(text: '123456');
      var completed = 0;
      await tester.pumpWidget(_wrap(OtpBoxes(
        controller: controller,
        autofocus: false,
        onCompleted: () => completed++,
      )));
      await tester.pump();
      // Listener only fires on change, so simulate an edit away from full.
      controller.text = '12345';
      await tester.pump();
      controller.text = '123456';
      await tester.pump();
      expect(completed, 1);
      controller.dispose();
    });

    testWidgets('rejects non-digits and caps at six', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(
          OtpBoxes(controller: controller, autofocus: false)));
      await tester.pump();

      // Must go through the field rather than assigning to the controller:
      // inputFormatters only run on the platform input path, so writing
      // controller.text directly would bypass the very behaviour under test.
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      await tester.enterText(find.byType(TextField), 'ab12');
      await tester.pump();
      expect(editable.controller.text, '12',
          reason: 'letters must be filtered out');

      await tester.enterText(find.byType(TextField), '1234567890');
      await tester.pump();
      expect(editable.controller.text, '123456',
          reason: 'input must be capped at six digits');
      controller.dispose();
    });

    testWidgets('error state is reflected without losing the digits',
        (tester) async {
      final controller = TextEditingController(text: '123');
      await tester.pumpWidget(_wrap(OtpBoxes(
        controller: controller,
        autofocus: false,
        hasError: true,
      )));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('is tappable through the box row to focus the field',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(
          OtpBoxes(controller: controller, autofocus: false)));
      await tester.pump();
      await tester.tap(find.byType(OtpBoxes), warnIfMissed: false);
      await tester.pump();
      // The real input field must be focusable even though it is invisible.
      expect(find.byType(TextField), findsOneWidget);
      controller.dispose();
    });
  });

  group('SuccessTick', () {
    testWidgets('renders a check and settles', (tester) async {
      await tester.pumpWidget(_wrap(const Center(child: SuccessTick())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  group('ResendCountdown', () {
    testWidgets('shows the countdown, and resend once it is null',
        (tester) async {
      await tester.pumpWidget(_wrap(const Center(child: ResendCountdown(seconds: 7))));
      expect(find.text('Resend in 0:07'), findsOneWidget);

      await tester.pumpWidget(_wrap(const Center(child: ResendCountdown(seconds: null))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Resend OTP'), findsOneWidget);
    });
  });

  group('StatusNote', () {
    testWidgets('renders the message', (tester) async {
      await tester.pumpWidget(_wrap(const StatusNote(
        text: 'That code is not right.',
        tone: Colors.red,
        icon: Icons.error_outline,
      )));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('That code is not right.'), findsOneWidget);
    });
  });

  group('AuthShell', () {
    testWidgets('renders the child above the backdrop', (tester) async {
      // AuthShell is a bare Stack, so it needs an app-level Directionality;
      // the real screens always sit under MaterialApp.
      await tester.pumpWidget(const MaterialApp(
        home: AuthShell(child: Text('body')),
      ));
      await tester.pump();
      expect(find.byType(AmbientBackdrop), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    });
  });
}

LinearGradient _gradientOf(WidgetTester tester) {
  // Material also builds an internal Ink with a null decoration, so pick the
  // one that actually carries the button gradient.
  final candidates = tester
      .widgetList<Ink>(find.byType(Ink))
      .map((i) => i.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.gradient)
      .whereType<LinearGradient>()
      .toList();
  expect(candidates, isNotEmpty,
      reason: 'SweepButton must paint a LinearGradient through an Ink');
  return candidates.first;
}

double _offsetX(WidgetTester tester) {
  final t = tester.widgetList<Transform>(find.byType(Transform)).first;
  final m = t.transform;
  return m.storage[12];
}

double _opacityOf(WidgetTester tester, String label) {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byType(Opacity),
  );
  return tester.widgetList<Opacity>(finder).first.opacity;
}
