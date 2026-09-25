import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/models/category.dart';
import 'package:customer_app/widgets/category_grid.dart';

void main() {
  const viewportWidth = 390.0;

  List<ServiceCategory> categories({bool withCombo = false}) => [
        if (withCombo) ServiceCategory(id: '9', name: 'Combo'),
        ServiceCategory(id: '1', name: 'Haircut'),
        ServiceCategory(id: '2', name: 'Facial'),
        ServiceCategory(id: '3', name: 'Manicure'),
      ];

  Widget harness(
    List<ServiceCategory> cats, {
    void Function(ServiceCategory)? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: viewportWidth,
            child: CategoryGrid(
              categories: cats,
              onTap: onTap ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  /// How many categories the strip shows, after the synthesized 'Combo' is
  /// accounted for. Every test case here has three API categories.
  const distinctTiles = 4;

  /// Left edge of every tile in the first copy, relative to the strip, paired
  /// with the label that tile is showing.
  List<(String, double)> tiles(WidgetTester tester) {
    // The icon box is square and sits flush with the left of its tile, so it
    // measures the tile's position exactly.
    final boxes = tester
        .renderObjectList<RenderBox>(find.byType(AspectRatio))
        .toList();
    final origin = boxes.first.localToGlobal(Offset.zero).dx;
    final grid = find.descendant(
      of: find.byType(CategoryGrid),
      matching: find.byType(InkWell),
    );

    return [
      for (var i = 0; i < distinctTiles; i++)
        (
          tester
              .widget<Text>(find.descendant(
                of: grid.at(i),
                matching: find.byType(Text),
              ))
              .data!,
          boxes[i].localToGlobal(Offset.zero).dx - origin,
        ),
    ];
  }

  testWidgets('still shows four tiles across the screen', (tester) async {
    await tester.pumpWidget(harness(categories()));

    final laidOut = tiles(tester);
    expect(laidOut.map((t) => t.$1).toList(),
        ['Combo', 'Haircut', 'Facial', 'Manicure']);
    expect(laidOut.map((t) => t.$2).toList(), [0, 100.5, 201, 301.5]);
    // The fourth tile starts inside the screen and reaches its right edge.
    expect(laidOut.last.$2 + 88.5, closeTo(viewportWidth, 0.01));
  });

  testWidgets('puts Combo first even when the API did not send it', (tester) async {
    await tester.pumpWidget(harness(categories()));

    expect(tiles(tester).first.$1, 'Combo');
    expect(tiles(tester).first.$2, 0);
  });

  testWidgets('keeps Combo first when the API does send it', (tester) async {
    await tester.pumpWidget(harness(categories(withCombo: true)));

    final laidOut = tiles(tester);
    expect(laidOut.map((t) => t.$1).toList(),
        ['Combo', 'Haircut', 'Facial', 'Manicure']);
    // Two copies of four, not a fifth synthesized entry.
    expect(
      tester.renderObjectList<RenderBox>(find.byType(AspectRatio)).length,
      8,
    );
  });

  testWidgets('tapping a tile reports that category', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(harness(
      categories(),
      onTap: (c) => tapped.add('${c.id}:${c.name}'),
    ));

    await tester.tap(find.text('Facial').first);
    await tester.pump();

    expect(tapped, ['2:Facial']);
  });

  testWidgets('tapping still works while the row is moving', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(harness(
      categories(),
      onTap: (c) => tapped.add(c.name),
    ));

    // A third of the way through the loop the tiles have slid, so a tap has to
    // travel through the moving transform to land on the right one.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, isEmpty, reason: 'nothing is tapped yet');

    await tester.tapAt(tester.getCenter(find.text('Manicure').first));
    await tester.pump();

    expect(tapped, ['Manicure']);
  });

  testWidgets('shows a label-less fallback icon when a category has no image',
      (tester) async {
    await tester.pumpWidget(harness([
      ServiceCategory(id: '7', name: 'Bridal Makeup'),
    ]));

    expect(find.byIcon(Icons.brush_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing for an empty list instead of throwing',
      (tester) async {
    await tester.pumpWidget(harness([]));

    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryGrid), findsOneWidget);
  });
}
