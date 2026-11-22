import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/widgets/subscription/payment_screenshot_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget field) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: field))));

  testWidgets('empty: a clear upload area that opens the picker', (tester) async {
    var picks = 0;
    await pump(tester, PaymentScreenshotField(bytes: null, fileName: null, onPick: () => picks++, pickKey: const Key('pick')));

    expect(find.text('Upload payment screenshot'), findsOneWidget);
    expect(find.text('Screenshot attached'), findsNothing);

    await tester.tap(find.byKey(const Key('pick')));
    expect(picks, 1);
  });

  testWidgets('says it is required after a submit without one', (tester) async {
    await pump(tester, PaymentScreenshotField(bytes: null, fileName: null, onPick: () {}, hasError: true));
    expect(find.text('Required — attach it to submit'), findsOneWidget);
  });

  testWidgets('attached: shows it plainly with name, size, Change and Remove', (tester) async {
    var removed = false;
    await pump(
      tester,
      PaymentScreenshotField(
        bytes: Uint8List(2048),
        fileName: 'gpay-receipt.jpg',
        onPick: () {},
        onRemove: () => removed = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Screenshot attached'), findsOneWidget);
    expect(find.text('gpay-receipt.jpg'), findsOneWidget);
    expect(find.text('2 KB · ready to submit'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    expect(removed, isTrue);
  });
}
