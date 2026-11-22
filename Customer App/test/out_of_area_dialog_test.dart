import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/out_of_area_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> open(WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showOutOfAreaDialog(context, cityName: 'Pune'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('says it plainly and names the city shown instead', (tester) async {
    await open(tester);
    expect(find.text("We're not in your area yet"), findsOneWidget);
    expect(find.textContaining('Pune', findRichText: true), findsWidgets);
    expect(find.text('Explore Pune'), findsOneWidget);
  });

  testWidgets('Explore closes it without asking to change city', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showOutOfAreaDialog(context, cityName: 'Pune'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('out_of_area_explore')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text("We're not in your area yet"), findsNothing);
  });

  testWidgets('Choose another city asks for the picker', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showOutOfAreaDialog(context, cityName: 'Pune'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('out_of_area_change')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
