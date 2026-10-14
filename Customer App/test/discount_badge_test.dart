import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/widgets/discount_badge.dart';
import 'package:customer_app/theme/app_theme.dart';

void main() {
  Widget wrapWidget(
    Widget child, {
    bool disableAnimations = false,
    double width = 400,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            disableAnimations: disableAnimations,
          ),
          child: SizedBox(
            width: width,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  group('DiscountBadge Unit & Animation Tests', () {
    test('1. A valid discount displays the correct percentage', () {
      expect(DiscountBadge.calculateDiscountPercent(1000, 700), 30);
      expect(DiscountBadge.calculateDiscountPercent(899, 499), 44);
      expect(DiscountBadge.calculateDiscountPercent(200, 100), 50);
      expect(DiscountBadge.calculateDiscountPercent(100, 99), 1);
    });

    testWidgets('2. Original price greater than discounted price displays a badge', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const DiscountBadge(
          originalPrice: 1000,
          price: 750,
          style: DiscountBadgeStyle.compact,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('25% OFF'), findsOneWidget);
    });

    testWidgets('3. Equal prices do not display a discount', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const DiscountBadge(
          originalPrice: 500,
          price: 500,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('OFF'), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('4. Original price below discounted price does not display a discount', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const DiscountBadge(
          originalPrice: 400,
          price: 500,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('OFF'), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('5. Null or invalid prices do not crash', (tester) async {
      // All combinations of invalid inputs
      await tester.pumpWidget(wrapWidget(
        const Column(
          children: [
            DiscountBadge(originalPrice: null, price: 100),
            DiscountBadge(originalPrice: 100, price: null),
            DiscountBadge(originalPrice: 0, price: 0),
            DiscountBadge(originalPrice: -100, price: 50),
            DiscountBadge(originalPrice: 100, price: -50),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('OFF'), findsNothing);
    });

    testWidgets('6. The animation reaches its final state within approximately 500 ms', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const DiscountBadge(
          originalPrice: 1000,
          price: 600,
        ),
      ));

      // Initially at 0ms, opacity is 0.0
      final badgeFinder = find.byType(DiscountBadge);
      final opacityFinder = find.descendant(of: badgeFinder, matching: find.byType(Opacity));
      expect(opacityFinder, findsOneWidget);
      Opacity opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 0.0);

      // Advance by 500ms
      await tester.pump(const Duration(milliseconds: 500));

      opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 1.0);

      final transformFinder = find.descendant(of: badgeFinder, matching: find.byType(Transform));
      expect(transformFinder, findsOneWidget);
      final transformWidget = tester.widget<Transform>(transformFinder);
      expect(transformWidget.transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));

      expect(find.text('40% OFF'), findsOneWidget);
    });

    testWidgets('7. Reduced-motion mode shows the final state immediately', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const DiscountBadge(
          originalPrice: 1000,
          price: 800,
        ),
        disableAnimations: true,
      ));

      // Frame 1 without waiting 400ms: should be fully rendered at resting state
      await tester.pump();

      final badgeFinder = find.byType(DiscountBadge);
      final opacityWidget = tester.widget<Opacity>(
        find.descendant(of: badgeFinder, matching: find.byType(Opacity)),
      );
      expect(opacityWidget.opacity, 1.0);

      final transformWidget = tester.widget<Transform>(
        find.descendant(of: badgeFinder, matching: find.byType(Transform)),
      );
      expect(transformWidget.transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));

      expect(find.text('20% OFF'), findsOneWidget);
    });

    testWidgets('8. Parent rebuilds do not restart the animation', (tester) async {
      int parentBuildCount = 0;
      late StateSetter parentSetState;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              parentSetState = setState;
              parentBuildCount++;
              return Column(
                children: [
                  Text('Parent build: $parentBuildCount'),
                  const DiscountBadge(
                    originalPrice: 1000,
                    price: 500,
                  ),
                ],
              );
            },
          ),
        ),
      ));

      final badgeFinder = find.byType(DiscountBadge);
      final opacityFinder = find.descendant(of: badgeFinder, matching: find.byType(Opacity));

      // Let animation complete
      await tester.pumpAndSettle();
      expect(parentBuildCount, 1);
      expect(tester.widget<Opacity>(opacityFinder).opacity, 1.0);

      // Trigger parent setState()
      parentSetState(() {});
      await tester.pump();

      expect(parentBuildCount, 2);
      // Opacity must remain at 1.0, not restart from 0.0
      expect(tester.widget<Opacity>(opacityFinder).opacity, 1.0);
    });

    testWidgets('9. Compact and prominent presentations render without overflow', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DiscountBadge(
              originalPrice: 1000,
              price: 800,
              style: DiscountBadgeStyle.compact,
            ),
            SizedBox(height: 12),
            DiscountBadge(
              originalPrice: 1000,
              price: 800,
              style: DiscountBadgeStyle.prominent,
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('20% OFF'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('10. Long text and narrow layouts remain stable', (tester) async {
      await tester.pumpWidget(wrapWidget(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('₹14,999'),
            const SizedBox(width: 6),
            const AnimatedOriginalPrice(originalPrice: 29999, price: 14999),
            const SizedBox(width: 6),
            const Flexible(
              child: DiscountBadge(
                originalPrice: 29999,
                price: 14999,
                style: DiscountBadgeStyle.compact,
              ),
            ),
          ],
        ),
        width: 250, // Narrow container
      ));
      await tester.pumpAndSettle();

      expect(find.text('50% OFF'), findsOneWidget);
      expect(find.text('₹29999'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AnimatedOriginalPrice suppresses display when no discount exists', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const Column(
          children: [
            AnimatedOriginalPrice(originalPrice: 500, price: 500),
            AnimatedOriginalPrice(originalPrice: 400, price: 500),
            AnimatedOriginalPrice(originalPrice: null, price: 500),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
    });
  });
}
