import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/widgets/logo_marquee.dart';

void main() {
  const itemExtent = 80.0;
  const gap = 12.0;
  const itemCount = 3;
  const pixelsPerSecond = 30.0;
  const viewportWidth = 390.0;
  const height = 100.0;

  final passWidth = itemCount * (itemExtent + gap);
  final period = Duration(
    milliseconds: (passWidth / pixelsPerSecond * 1000).round(),
  );

  Widget harness({MediaQueryData? mediaQuery}) {
    const marquee = InfiniteLogoMarquee(
      itemCount: itemCount,
      itemExtent: itemExtent,
      height: height,
      gap: gap,
      pixelsPerSecond: pixelsPerSecond,
      itemBuilder: _item,
    );

    Widget home = const Scaffold(
      body: Center(
        child: SizedBox(width: viewportWidth, child: marquee),
      ),
    );

    if (mediaQuery != null) {
      home = MediaQuery(data: mediaQuery, child: home);
    }
    return MaterialApp(home: home);
  }

  /// Left edge of every rendered item, in the order the row was built.
  List<double> itemLefts(WidgetTester tester) => tester
      .renderObjectList<RenderBox>(find.byKey(const ValueKey('item')))
      .map((box) => box.localToGlobal(Offset.zero).dx)
      .toList();

  /// Pumps the frame the ticker needs before time starts counting.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
  }

  testWidgets('repeats the list enough times to cover the viewport', (tester) async {
    await settle(tester);

    final expectedCopies = (viewportWidth / passWidth).ceil() + 1;
    expect(expectedCopies, 3, reason: 'guard on the arithmetic under test');
    expect(itemLefts(tester).length, expectedCopies * itemCount);
  });

  testWidgets('slides right to left at a constant speed', (tester) async {
    await settle(tester);
    final start = itemLefts(tester);

    await tester.pump(period ~/ 4);
    final quarter = itemLefts(tester);

    for (var i = 0; i < start.length; i++) {
      expect(
        quarter[i],
        closeTo(start[i] - passWidth / 4, 0.5),
        reason: 'item $i should have drifted a quarter pass to the left',
      );
    }
  });

  testWidgets('lines the next copy up with the one it replaced', (tester) async {
    await settle(tester);
    final start = itemLefts(tester);

    // A hair short of the period, so the animation has not wrapped yet. Copy
    // N+1 has to be sitting exactly where copy N started, otherwise the loop
    // point shows up as a jump.
    await tester.pump(period - const Duration(milliseconds: 1));
    final justBeforeLoop = itemLefts(tester);

    for (var i = 0; i < start.length; i++) {
      expect(
        justBeforeLoop[i],
        closeTo(start[i] - passWidth, 0.5),
        reason: 'item $i should sit one full pass to the left of where it began',
      );
    }

    // And once the period elapses the row is back to its opening frame.
    await tester.pump(const Duration(milliseconds: 1));
    final afterLoop = itemLefts(tester);

    for (var i = 0; i < start.length; i++) {
      expect(
        afterLoop[i],
        closeTo(start[i], 0.01),
        reason: 'item $i should return to its starting position',
      );
    }
  });

  testWidgets('stays full width right up to the loop point', (tester) async {
    await settle(tester);
    final start = itemLefts(tester);

    // Every copy is the same width, so the rightmost item of the last copy is
    // the rightmost thing on screen. If it had fallen short the strip would
    // visibly empty out before it looped.
    final rowWidth = start.last + itemExtent;

    for (var step = 1; step <= 8; step++) {
      await tester.pump(period ~/ 8);
      final lefts = itemLefts(tester);
      final visibleRight = lefts.reduce((a, b) => a > b ? a : b) + itemExtent;
      expect(visibleRight, greaterThanOrEqualTo(viewportWidth - 0.01),
          reason: 'gap in the strip after ${step * 12.5}% of a pass');
    }

    expect(rowWidth, greaterThanOrEqualTo(viewportWidth * 2));
  });

  testWidgets('never overflows the strip it is given', (tester) async {
    await settle(tester);

    for (var i = 0; i < 20; i++) {
      await tester.pump(period ~/ 7);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('survives an unbounded width instead of throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: InfiniteLogoMarquee(
              itemCount: 3,
              itemExtent: itemExtent,
              height: height,
              gap: gap,
              itemBuilder: _item,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to a swipeable strip when motion is reduced',
      (tester) async {
    await tester.pumpWidget(
      harness(mediaQuery: const MediaQueryData(disableAnimations: true)),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(InfiniteLogoMarquee),
        matching: find.byType(ListView),
      ),
      findsOneWidget,
    );

    // A strip that will not stop moving is the thing reduced motion is meant to
    // avoid, so time passing must leave it where it was.
    final start = itemLefts(tester);
    await tester.pump(period * 3);
    for (var i = 0; i < start.length; i++) {
      expect(itemLefts(tester)[i], closeTo(start[i], 0.01));
    }
  });
}

Widget _item(BuildContext context, int index) {
  return const Placeholder(key: ValueKey('item'));
}
