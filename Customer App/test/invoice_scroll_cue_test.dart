import 'package:customer_app/widgets/invoice_scroll_cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness(InvoiceScrollState state, {VoidCallback? onTap, Size size = const Size(360, 740)}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: MaterialApp(
      home: Scaffold(
        body: InvoiceScrollCue(state: state, onScrollForMe: onTap ?? () {}),
      ),
    ),
  );
}

void main() {
  group('reading the page report', () {
    test('top of a long invoice', () {
      final s = InvoiceScrollState.parse('0,600')!;
      expect(s.scrollable, isTrue);
      expect(s.progress, 0);
      expect(s.moved, isFalse);
    });

    test('a page that fits the screen is not scrollable', () {
      final s = InvoiceScrollState.parse('0,10')!;
      expect(s.scrollable, isFalse);
      expect(s.atBottom, isTrue);
    });

    test('once moved, stays moved even back at the top', () {
      final s = InvoiceScrollState.parse('0,600', alreadyMoved: true)!;
      expect(s.moved, isTrue);
    });

    test('rejects junk', () {
      expect(InvoiceScrollState.parse('hello'), isNull);
      expect(InvoiceScrollState.parse('1,2,3'), isNull);
    });
  });

  for (final size in const [Size(320, 568), Size(360, 740), Size(430, 932)]) {
    testWidgets('at ${size.width.toInt()}px a long invoice says it scrolls', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var taps = 0;
      await tester.pumpWidget(harness(InvoiceScrollState.parse('0,600')!, onTap: () => taps++, size: size));
      await tester.pump();

      expect(find.byKey(const ValueKey('invoice-scroll-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('invoice-scroll-fade')), findsOneWidget);
      expect(find.text('Scroll for services & total'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow at this size');

      await tester.tap(find.byKey(const ValueKey('invoice-scroll-hint')));
      expect(taps, 1);
    });
  }

  testWidgets('the pill goes once they scroll, the bar stays', (tester) async {
    await tester.pumpWidget(harness(InvoiceScrollState.parse('120,600')!));
    await tester.pumpAndSettle();

    final pill = tester.widget<AnimatedOpacity>(find.ancestor(
      of: find.byKey(const ValueKey('invoice-scroll-hint')),
      matching: find.byType(AnimatedOpacity),
    ));
    expect(pill.opacity, 0);
    expect(find.byKey(const ValueKey('invoice-scroll-progress')), findsOneWidget);
  });

  testWidgets('nothing at all for an invoice that fits', (tester) async {
    await tester.pumpWidget(harness(InvoiceScrollState.parse('0,0')!));
    expect(find.byKey(const ValueKey('invoice-scroll-progress')), findsNothing);
    expect(find.text('Scroll for services & total'), findsNothing);
  });
}
