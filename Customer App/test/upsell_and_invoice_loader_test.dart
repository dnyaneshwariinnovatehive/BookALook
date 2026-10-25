import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/cart_offers.dart';
import 'package:customer_app/widgets/invoice_loader.dart';
import 'package:customer_app/widgets/pairs_well_with_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Step through frames so animation completions and the timers they start
/// both get their turn.
Future<void> _run(WidgetTester tester, Duration total) async {
  for (var t = Duration.zero; t < total; t += const Duration(milliseconds: 50)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget child, {bool reduceMotion = false, Size size = const Size(400, 800)}) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('InvoiceLoader', () {
    testWidgets('sits in the centre of the space it is given', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(InvoiceLoader(isReady: false, onFinished: () {})));
      await tester.pump(const Duration(milliseconds: 300));

      final loader = tester.getRect(find.byKey(const ValueKey('invoice_loader')));
      final check = tester.getRect(find.byKey(const ValueKey('invoice_loader_check')));
      // The document graphic is centred horizontally, and the whole group
      // sits around the middle rather than at the top.
      expect((check.center.dx - loader.center.dx).abs(), lessThan(100));
      final group = tester.getRect(find.byType(FittedBox).first);
      expect((group.center.dy - loader.center.dy).abs(), lessThan(4));
      expect((group.center.dx - loader.center.dx).abs(), lessThan(4));
    });

    testWidgets('fits a short screen without overflowing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(InvoiceLoader(isReady: false, onFinished: () {}), size: const Size(320, 260)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('waits for the page, then hands over once', (tester) async {
      var finished = 0;
      Widget build(bool ready) => _app(InvoiceLoader(isReady: ready, onFinished: () => finished++));

      await tester.pumpWidget(build(false));
      await _run(tester, const Duration(seconds: 3));
      expect(finished, 0);
      expect(find.text('Preparing your invoice'), findsOneWidget);

      await tester.pumpWidget(build(true));
      await _run(tester, const Duration(milliseconds: 100));
      expect(find.text('Your invoice is ready'), findsOneWidget);

      await _run(tester, const Duration(seconds: 2));
      expect(finished, 1);
    });

    testWidgets('a fast load still shows the writing before handing over', (tester) async {
      var finished = 0;
      await tester.pumpWidget(_app(InvoiceLoader(isReady: true, onFinished: () => finished++)));

      await _run(tester, const Duration(milliseconds: 500));
      expect(finished, 0);

      await _run(tester, const Duration(seconds: 3));
      expect(finished, 1);
    });

    testWidgets('reduced motion skips straight to the hand-over', (tester) async {
      var finished = 0;
      await tester.pumpWidget(_app(InvoiceLoader(isReady: true, onFinished: () => finished++), reduceMotion: true));
      await _run(tester, const Duration(seconds: 1));
      expect(finished, 1);
    });
  });

  group('PairsWellWithSheet', () {
    testWidgets('adds a pick in one tap and marks it added', (tester) async {
      final added = <String>[];
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showPairsWellWithSheet(
              context,
              baseName: 'Haircut',
              salonName: 'Glow Studio',
              services: [
                {'id': 's-spa', 'name': 'Hair Spa', 'price': 800, 'duration_minutes': 45},
              ],
              onAdd: (id) async {
                added.add(id);
                return true;
              },
            ),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Pairs well with your Haircut'), findsOneWidget);
      expect(find.text('Recommended by Glow Studio'), findsOneWidget);
      expect(find.text('45 min  ·  ₹800'), findsOneWidget);
      expect(find.text('No thanks'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pairs_well_add_s-spa')));
      await tester.pumpAndSettle();

      expect(added, ['s-spa']);
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('SuggestionStrip', () {
    testWidgets("labels the salon's picks and says what they go with", (tester) async {
      await tester.pumpWidget(_app(SuggestionStrip(
        salonName: 'Glow Studio',
        suggestions: const [
          {'id': 'a', 'name': 'Hair Spa', 'price': 800, 'duration_minutes': 45, 'reason': 'salon_pick', 'paired_with': 'Haircut'},
          {'id': 'b', 'name': 'Beard Trim', 'price': 150, 'duration_minutes': 30, 'reason': 'bought_together', 'together_percent': 40},
        ],
        onAdd: (_) {},
      )));

      expect(find.text('Recommended for your visit'), findsOneWidget);
      expect(find.text('Picked by Glow Studio'), findsOneWidget);
      expect(find.text("Salon's pick"), findsOneWidget);
      expect(find.text('Goes with your Haircut'), findsOneWidget);
      expect(find.text('With 40% of these bookings'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('without picks it keeps the history wording', (tester) async {
      await tester.pumpWidget(_app(SuggestionStrip(
        suggestions: const [
          {'id': 'b', 'name': 'Beard Trim', 'price': 150, 'reason': 'bought_together', 'together_percent': 40},
        ],
      )));

      expect(find.text('Often booked together here'), findsOneWidget);
      expect(find.text("Salon's pick"), findsNothing);
    });
  });
}
