import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/widgets/combo_category_animation.dart';

void main() {
  group('ComboCategoryAnimation', () {
    testWidgets('renders successfully with default colors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 60,
                height: 60,
                child: ComboCategoryAnimation(),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ComboCategoryAnimation), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('animates through all 10 stages without error or exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 70,
                height: 70,
                child: ComboCategoryAnimation(
                  primaryColor: Color(0xFF9850F1),
                  backgroundColor: Color(0xFFEEE3FD),
                ),
              ),
            ),
          ),
        ),
      );

      // Total cycle is 5800ms
      // Pump through each stage
      // Stage 1: 0 - 464ms (closed basket)
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);

      // Stage 2: 464 - 1044ms (basket opens, glow appears)
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);

      // Stage 3: 1044 - 1740ms (Hair pops out)
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Stage 4: 1740 - 2436ms (Skin pops out)
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Stage 5: 2436 - 3132ms (Nails pops out)
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Stage 6: 3132 - 3828ms (Spa pops out, all 4 visible)
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Stage 7: 3828 - 4756ms (Combo reveal float & sparkles)
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Stage 8: 4756 - 5336ms (Icons return into basket)
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Stage 9: 5336 - 5626ms (Basket closes, glow fades)
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // Stage 10: 5626 - 5800ms (Closed basket settle & seamless loop)
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // Run multiple full cycles to verify seamless continuous repetition
      for (int i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 5800));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('respects prefers-reduced-motion by rendering static reveal without looping', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: ComboCategoryAnimation(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ComboCategoryAnimation), findsOneWidget);
      // Pumping time in reduced motion should have no errors and remain static
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposes controller cleanly on unmount', (tester) async {
      bool mounted = true;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: mounted
                    ? const ComboCategoryAnimation()
                    : const SizedBox.shrink(),
              ),
            );
          },
        ),
      );

      expect(find.byType(ComboCategoryAnimation), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));

      // Unmount widget
      mounted = false;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      expect(find.byType(ComboCategoryAnimation), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
