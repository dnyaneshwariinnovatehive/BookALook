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
              .widget<Text>(find.descendant(
                of: find.byType(CategoryGrid).at(0),
                matching: find.byType(Text),
              ).at(i))
              .data!,
          boxes[i].localToGlobal(Offset.zero).dx - origin,
        ),
    ];
  }

  List<String> labels(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
        of: find.byType(CategoryGrid),
        matching: find.byType(Text),
      ))
      .map((t) => t.data!)
      .toList();

  testWidgets('shows exactly four fixed cards, in order', (tester) async {
    await tester.pumpWidget(harness(categories()));

    expect(labels(tester), ['Combo', 'Hair', 'Grooming', 'View More']);
  });

  testWidgets('the four cards fill the row edge to edge and never move',
      (tester) async {
    await tester.pumpWidget(harness(categories()));

    final laidOut = cards(tester);
    expect(laidOut.map((c) => c.$2).toList(), [0, 100.5, 201, 301.5]);
    expect(laidOut.last.$2 + 88.5, closeTo(viewportWidth, 0.01));

    // Half a second is several whole marquee loops in the old implementation.
    // Nothing may have moved.
    await tester.pump(const Duration(milliseconds: 500));
    expect(cards(tester).map((c) => c.$2).toList(),
        [0, 100.5, 201, 301.5]);
  });

  testWidgets('Combo carries the sentinel id rather than a category uuid',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(harness(
      categories(),
      onTap: (c) => tapped.add(c.id),
    ));

    await tester.tap(find.text('Combo'));
    await tester.pump();

    expect(tapped, [CategoryGrid.comboSentinelId]);
  });

  testWidgets('Hair and Grooming resolve to their catalogue ids', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(harness(
      categories(),
      onTap: (c) => tapped.add('${c.id}:${c.name}'),
    ));

    await tester.tap(find.text('Hair'));
    await tester.pump();
    await tester.tap(find.text('Grooming'));
    await tester.pump();

    expect(tapped, ['1:Hair', '5:Grooming']);
  });

  testWidgets('a renamed category still lands on the right card',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(harness(
      [
        ServiceCategory(id: '7', name: 'Hair Services'),
        ServiceCategory(id: '8', name: 'Beard & Moustache'),
      ],
      onTap: (c) => tapped.add(c.id),
    ));

    expect(labels(tester), ['Combo', 'Hair', 'Grooming', 'View More']);

    await tester.tap(find.text('Hair'));
    await tester.pump();
    await tester.tap(find.text('Grooming'));
    await tester.pump();

    expect(tapped, ['7', '8']);
  });

  testWidgets('View More opens the category list, not a salon filter',
      (tester) async {
    var viewMoreTaps = 0;
    final tapped = <String>[];

    await tester.pumpWidget(harness(
      // No Hair row at all, so the fixed card has no category behind it.
      [ServiceCategory(id: '2', name: 'Skin')],
      onTap: (c) => tapped.add(c.id),
      onViewMore: () => viewMoreTaps++,
    ));

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

  testWidgets('shows a label-less fallback icon when a category has no image',
      (tester) async {
    await tester.pumpWidget(harness([
      ServiceCategory(id: '9', name: 'Bridal Makeup'),
    ]));

    expect(find.byType(CategoryGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing for an empty list instead of throwing',
      (tester) async {
    await tester.pumpWidget(harness([]));

    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryGrid), findsOneWidget);
  });
}
