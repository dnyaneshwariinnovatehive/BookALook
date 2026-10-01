import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:customer_app/screens/categories_screen.dart';
import 'package:customer_app/services/http_client.dart' as api;
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/feedback_states.dart';
import 'package:customer_app/widgets/skeleton.dart';

const _catalogue = '{"categories":[{"id":"c1","name":"Hair"},{"id":"c2","name":"Skin"}]}';

/// The categories screen end to end through the shared HTTP client: the
/// skeleton gives way to the grid, pulling down asks again, and an empty
/// catalogue says so with a retry.
void main() {
  late int requests;
  late Completer<void> gate;
  late String body;

  setUp(() {
    requests = 0;
    gate = Completer<void>()..complete();
    body = _catalogue;
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api');
    api.debugSetClient(MockClient((_) async {
      requests++;
      await gate.future;
      return http.Response(body, 200);
    }));
  });

  Future<void> open(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const CategoriesScreen()),
      );

  testWidgets('shows tile skeletons, then the categories', (tester) async {
    gate = Completer<void>();
    await open(tester);
    await tester.pump();

    expect(find.byType(CategoryTileSkeleton), findsWidgets);
    expect(find.text('Hair'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CategoryTileSkeleton), findsNothing);
    expect(find.text('Hair'), findsOneWidget);
    expect(find.text('Skin'), findsOneWidget);
  });

  testWidgets('pulling down fetches the categories again', (tester) async {
    await open(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, 1);

    await tester.fling(find.text('Hair'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(requests, 2);
  });

  testWidgets('an empty catalogue explains itself and retries', (tester) async {
    body = '{"categories":[]}';
    await open(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // It used to show the Combo tile alone and say nothing.
    expect(find.byType(InlineStatus), findsOneWidget);

    body = _catalogue;
    await tester.tap(find.byKey(InlineStatus.retryKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests, 2);
    expect(find.byType(InlineStatus), findsNothing);
    expect(find.text('Hair'), findsOneWidget);
  });
}
