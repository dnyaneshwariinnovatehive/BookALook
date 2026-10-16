import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/widgets/flipping_savings_badge.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  Widget wrapWidget(
    Widget child, {
    bool disableAnimations = false,
    bool accessibleNavigation = false,
    double width = 300,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 600),
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  group('FlippingSavingsBadge Animated Ticket Tests', () {
    testWidgets('1. Displays "Price Drop" initially on the front face', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(const FlippingSavingsBadge(savings: 100)),
      );
      await tester.pump();

      expect(find.text('Price Drop'), findsOneWidget);
      expect(find.text('₹100 OFF'), findsNothing);
    });

    testWidgets(
      '2. Displays "₹X OFF" under reduced motion (accessible state)',
      (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            const FlippingSavingsBadge(savings: 100),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('₹100 OFF'), findsOneWidget);
        // Under reduced motion, no Transform widget is used
        expect(
          find.descendant(
            of: find.byType(FlippingSavingsBadge),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      '3. Formats different savings amounts correctly on the back face',
      (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            const Column(
              children: [
                FlippingSavingsBadge(savings: 50),
                FlippingSavingsBadge(savings: 250),
                FlippingSavingsBadge(savings: 1200),
              ],
            ),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('₹50 OFF'), findsOneWidget);
        expect(find.text('₹250 OFF'), findsOneWidget);
        expect(find.text('₹1200 OFF'), findsOneWidget);
      },
    );

    testWidgets('4. Custom frontLabel and backLabel override defaults', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(
          const FlippingSavingsBadge(
            savings: 100,
            frontLabel: 'SPECIAL',
            backLabel: 'SAVE BIG',
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SAVE BIG'), findsOneWidget);
    });

    testWidgets('5. Zero or negative savings renders SizedBox.shrink', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(
          const Column(
            children: [
              FlippingSavingsBadge(savings: 0),
              FlippingSavingsBadge(savings: -50),
            ],
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('OFF'), findsNothing);
      expect(find.textContaining('Price Drop'), findsNothing);
    });

    testWidgets(
      '6. Continuous 2-face flip cycle transitions between Price Drop and ₹X OFF smoothly',
      (tester) async {
        // Cycle:
        // [0 .. 1200ms]: Front Face ('Price Drop')
        // [1200ms .. 1800ms]: Flip from Front to Back
        // [1800ms .. 3000ms]: Back Face ('₹200 OFF')
        // [3000ms .. 3600ms]: Flip from Back to Front
        await tester.pumpWidget(
          wrapWidget(
            const FlippingSavingsBadge(
              savings: 200,
              flipDuration: Duration(milliseconds: 600),
              pauseDuration: Duration(milliseconds: 1200),
            ),
          ),
        );

        // Phase 1: Initial resting front face
        await tester.pump();
        expect(find.text('Price Drop'), findsOneWidget);
        expect(find.text('₹200 OFF'), findsNothing);

        final initialRect = tester.getRect(find.byType(FlippingSavingsBadge));

        // Advance within Phase 1 pause (at 600ms)
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Price Drop'), findsOneWidget);
        expect(find.text('₹200 OFF'), findsNothing);

        // Advance to start of Phase 2 flip (at 1300ms, mid-flip)
        await tester.pump(const Duration(milliseconds: 700));
        expect(
          find.descendant(
            of: find.byType(FlippingSavingsBadge),
            matching: find.byType(Transform),
          ),
          findsOneWidget,
        );

        // Advance into Phase 3 (at 2100ms, resting back face)
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('₹200 OFF'), findsOneWidget);
        expect(find.text('Price Drop'), findsNothing);

        final backFaceRect = tester.getRect(find.byType(FlippingSavingsBadge));
        expect(backFaceRect.center, equals(initialRect.center));

        // Advance to Phase 4 and into next cycle (at 3800ms, back to resting front face)
        await tester.pump(const Duration(milliseconds: 1700));
        expect(find.text('Price Drop'), findsOneWidget);
        expect(find.text('₹200 OFF'), findsNothing);

        final loopedRect = tester.getRect(find.byType(FlippingSavingsBadge));
        expect(loopedRect.center, equals(initialRect.center));
      },
    );

    testWidgets(
      '7. Removing widget cleanly disposes animation controller without errors',
      (tester) async {
        await tester.pumpWidget(
          wrapWidget(const FlippingSavingsBadge(savings: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Remove the widget by replacing body with Container
        await tester.pumpWidget(wrapWidget(const SizedBox()));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(FlippingSavingsBadge), findsNothing);
      },
    );
  });
}
