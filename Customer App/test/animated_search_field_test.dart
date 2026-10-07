import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/widgets/animated_search_field.dart';

void main() {
  testWidgets('AnimatedSearchField starts typing suggestions automatically', (tester) async {
    final controller = TextEditingController();
    const suggestions = ['haircut', 'facial'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedSearchField(
            controller: controller,
            suggestions: suggestions,
          ),
        ),
      ),
    );

    // Initial state: quotes and search prefix exist
    expect(find.text('Search "'), findsOneWidget);
    expect(find.text('"'), findsOneWidget);

    // Pump 100ms - first letter 'h' should be typed
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('h'), findsOneWidget);

    // Pump next letters step-by-step
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('ha'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('hai'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('hair'), findsOneWidget);
  });

  testWidgets('AnimatedSearchField stops showing animated hint when user types', (tester) async {
    final controller = TextEditingController();
    const suggestions = ['haircut'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedSearchField(
            controller: controller,
            suggestions: suggestions,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('h'), findsOneWidget);

    // User types something
    controller.text = 'sal';
    await tester.pump();

    // Animated hint layer should be hidden
    expect(find.text('Search "'), findsNothing);
  });
}
