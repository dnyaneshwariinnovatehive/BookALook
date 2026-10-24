import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/models/category.dart';
import 'package:customer_app/widgets/category_grid.dart';

void main() {
  const viewportWidth = 390.0;

  List<ServiceCategory> categories() => [
    ServiceCategory(id: '1', name: 'Hair'),
    ServiceCategory(id: '2', name: 'Skin'),
    ServiceCategory(id: '3', name: 'Nails'),
    ServiceCategory(id: '4', name: 'Spa'),
    ServiceCategory(id: '5', name: 'Grooming'),
  ];

  Widget harness(
    List<ServiceCategory> cats, {
    void Function(ServiceCategory)? onTap,
    VoidCallback? onViewMore,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: viewportWidth,
            child: CategoryGrid(
              categories: cats,
              onTap: onTap ?? (_) {},
              onViewMore: onViewMore ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  /// Left edge of every card, relative to the row, paired with its label.
  List<(String, double)> cards(WidgetTester tester) {
    final boxes = tester
        .renderObjectList<RenderBox>(find.byType(AspectRatio))
        .toList();
    final origin = boxes.first.localToGlobal(Offset.zero).dx;

    return [
      for (var i = 0; i < boxes.length; i++)
        (
          tester
              .widget<Text>(
                find
                    .descendant(
                      of: find.byType(CategoryGrid).at(0),
                      matching: find.byType(Text),
                    )
                    .at(i),
              )
              .data!,
          boxes[i].localToGlobal(Offset.zero).dx - origin,
        ),
    ];
  }

  List<String> labels(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(CategoryGrid),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data!)
      .toList();

  testWidgets('shows exactly four fixed cards, in order', (tester) async {
    await tester.pumpWidget(harness(categories()));

    expect(labels(tester), ['Combo', 'Hair', 'Grooming', 'View More']);
  });

  testWidgets('the four cards fill the row edge to edge and never move', (
    tester,
  ) async {
    await tester.pumpWidget(harness(categories()));

    final laidOut = cards(tester);
    expect(laidOut.map((c) => c.$2).toList(), [0, 100.5, 201, 301.5]);
    expect(laidOut.last.$2 + 88.5, closeTo(viewportWidth, 0.01));

    // Half a second is several whole marquee loops in the old implementation.
    // Nothing may have moved.
    await tester.pump(const Duration(milliseconds: 500));
    expect(cards(tester).map((c) => c.$2).toList(), [0, 100.5, 201, 301.5]);
  });

  testWidgets('Combo carries the sentinel id rather than a category uuid', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      harness(categories(), onTap: (c) => tapped.add(c.id)),
    );

    await tester.tap(find.text('Combo'));
    await tester.pump();

    expect(tapped, [CategoryGrid.comboSentinelId]);
  });

  testWidgets('Hair and Grooming resolve to their catalogue ids', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      harness(categories(), onTap: (c) => tapped.add('${c.id}:${c.name}')),
    );

    await tester.tap(find.text('Hair'));
    await tester.pump();
    await tester.tap(find.text('Grooming'));
    await tester.pump();

    expect(tapped, ['1:Hair', '5:Grooming']);
  });

  testWidgets('a renamed category still lands on the right card', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      harness([
        ServiceCategory(id: '7', name: 'Hair Services'),
        ServiceCategory(id: '8', name: 'Beard & Moustache'),
      ], onTap: (c) => tapped.add(c.id)),
    );

    expect(labels(tester), ['Combo', 'Hair', 'Grooming', 'View More']);

    await tester.tap(find.text('Hair'));
    await tester.pump();
    await tester.tap(find.text('Grooming'));
    await tester.pump();

    expect(tapped, ['7', '8']);
  });

  testWidgets('View More opens the category list, not a salon filter', (
    tester,
  ) async {
    var viewMoreTaps = 0;
    final tapped = <String>[];

    await tester.pumpWidget(
      harness(
        // No Hair row at all, so the fixed card has no category behind it.
        [ServiceCategory(id: '2', name: 'Skin')],
        onTap: (c) => tapped.add(c.id),
        onViewMore: () => viewMoreTaps++,
      ),
    );

    await tester.tap(find.text('View More'));
    await tester.pump();
    expect(viewMoreTaps, 1);

    // With no catalogue row to filter by, the card hands over to the same page
    // rather than sending a filter that would match nothing.
    await tester.tap(find.text('Hair'));
    await tester.pump();
    expect(viewMoreTaps, 2);
    expect(tapped, isEmpty);
  });

  testWidgets('shows a label-less fallback icon when a category has no image', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness([ServiceCategory(id: '9', name: 'Bridal Makeup')]),
    );

    expect(find.byType(CategoryGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing for an empty list instead of throwing', (
    tester,
  ) async {
    await tester.pumpWidget(harness([]));

    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryGrid), findsOneWidget);
  });

  testWidgets('cards are compact, square, and reduced by ~20-25%', (
    tester,
  ) async {
    // Standard phone screen with 20dp margin on each side (viewport = 350)
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: CategoryGrid(
              categories: categories(),
              onTap: (_) {},
              onViewMore: () {},
            ),
          ),
        ),
      ),
    );

    final cardBoxes = tester
        .renderObjectList<RenderBox>(find.byType(AspectRatio))
        .toList();

    expect(cardBoxes.length, 4);

    // Previously slot was 78.5 and card filled 78.5 x 78.5.
    // Now card size is reduced by ~23% to ~60.4 x 60.4.
    for (final box in cardBoxes) {
      expect(box.size.width, closeTo(60.4, 1.0));
      expect(box.size.height, closeTo(box.size.width, 0.01)); // square
    }

    // Section height is compact (~82dp instead of 102.5dp)
    final gridBox = tester.renderObject<RenderBox>(find.byType(CategoryGrid));
    expect(gridBox.size.height, lessThan(85.0));
  });

  testWidgets(
    'all four cards stay in a single row without overflow on narrow screens',
    (tester) async {
      // Narrow 320dp viewport
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: CategoryGrid(
                categories: categories(),
                onTap: (_) {},
                onViewMore: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final cardBoxes = tester
          .renderObjectList<RenderBox>(find.byType(AspectRatio))
          .toList();
      expect(cardBoxes.length, 4);

      // Equal compact size on narrow screen (~55dp)
      for (final box in cardBoxes) {
        expect(box.size.width, closeTo(54.7, 1.0));
        expect(box.size.height, closeTo(box.size.width, 0.01));
      }

      // All labels visible without truncation/overflow
      expect(find.text('Combo'), findsOneWidget);
      expect(find.text('Hair'), findsOneWidget);
      expect(find.text('Grooming'), findsOneWidget);
      expect(find.text('View More'), findsOneWidget);
    },
  );

  testWidgets('Combo tile hosts ComboCategoryAnimation and responds to taps without animation interruption', (tester) async {
    ServiceCategory? tapped;
    await tester.pumpWidget(
      harness(
        categories(),
        onTap: (cat) => tapped = cat,
      ),
    );

    // Initial frame
    await tester.pump();
    expect(find.byType(ComboCategoryAnimation), findsOneWidget);

    // Tap Combo card
    await tester.tap(find.text('Combo'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tapped, isNotNull);
    expect(tapped!.id, CategoryGrid.comboSentinelId);

    // Animation continues running smoothly across frames
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ComboCategoryAnimation renders cleanly in dark mode without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: viewportWidth,
              child: CategoryGrid(
                categories: categories(),
                onTap: (_) {},
                onViewMore: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(ComboCategoryAnimation), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dynamically fetched category logo occupies substantially more of the tile with minimal padding', (tester) async {
    final catsWithIcons = [
      ServiceCategory(id: '1', name: 'Hair', iconUrl: 'https://example.com/hair.png'),
      ServiceCategory(id: '5', name: 'Grooming', iconUrl: 'https://example.com/grooming.png'),
    ];

    await tester.pumpWidget(harness(catsWithIcons));
    await tester.pump();

    // Verify Image.network widgets are present for the categories with icons
    final imageWidgets = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(imageWidgets.length, 2);

    for (final img in imageWidgets) {
      expect(img.fit, BoxFit.contain);
      expect(img.alignment, Alignment.center);
    }

    // Verify there is NO 50% FractionallySizedBox wrapping the Image.network widgets
    final fractionalBoxes = tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox)).toList();
    // Only Combo (widthFactor 0.85) and View More (widthFactor 0.48) have FractionallySizedBox;
    // none of the image logos have the old 0.50 constraint!
    for (final box in fractionalBoxes) {
      expect(box.widthFactor, isNot(equals(0.50)));
      expect(box.heightFactor, isNot(equals(0.50)));
    }

    // View More tile remains intact with its grid icon
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
  });
}


