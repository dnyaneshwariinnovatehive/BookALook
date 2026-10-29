import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/contact_bookalook_screen.dart';
import 'package:partner_app/services/salon_support_api.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/settlements_card.dart';

SettlementSummary summary({
  int pending = 3,
  double toSalon = 2000,
  int toSalonCount = 2,
  double bySalon = 450,
  int bySalonCount = 1,
  int review = 1,
  int requests = 0,
}) =>
    SettlementSummary(
      pendingCount: pending,
      owedToSalon: toSalon,
      owedToSalonCount: toSalonCount,
      owedBySalon: bySalon,
      owedBySalonCount: bySalonCount,
      underReview: review,
      openRequests: requests,
      settlements: const [
        OpenSettlement(id: 'p1', label: '19 Oct – 25 Oct 2026', direction: 'pay_salon', amount: 1200),
        OpenSettlement(id: 'p2', label: '1 Sep – 30 Sep 2026', direction: 'salon_owes', amount: 450),
      ],
    );

Widget app(Widget child) => MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('settlements card on the lock screen', () {
    testWidgets('shows how many are pending and which way the money goes', (tester) async {
      await tester.pumpWidget(app(SettlementsCard(salonId: 's1', loader: (_) async => summary(requests: 1))));
      await tester.pumpAndSettle();

      expect(find.text('3 pending'), findsOneWidget);
      expect(find.text('BookALook owes you'), findsOneWidget);
      expect(find.text('₹2,000'), findsOneWidget);
      expect(find.text('You owe BookALook'), findsOneWidget);
      expect(find.text('₹450'), findsOneWidget);
      expect(find.textContaining('1 payment under review'), findsOneWidget);
      expect(find.textContaining('awaiting a reply'), findsOneWidget);
      expect(find.byKey(const ValueKey('locked_view_settlements')), findsOneWidget);
      expect(find.byKey(const ValueKey('locked_contact_bookalook')), findsOneWidget);
    });

    testWidgets('says so when everything is settled', (tester) async {
      await tester.pumpWidget(app(SettlementsCard(
        salonId: 's1',
        loader: (_) async => summary(pending: 0, toSalonCount: 0, bySalonCount: 0, review: 0),
      )));
      await tester.pumpAndSettle();

      expect(find.text('All settled'), findsOneWidget);
      expect(find.text('Nothing is pending either way.'), findsOneWidget);
      expect(find.text('BookALook owes you'), findsNothing);
    });

    testWidgets('a failed load offers a retry, and contact still works', (tester) async {
      await tester.pumpWidget(app(SettlementsCard(salonId: 's1', loader: (_) async => throw Exception('offline'))));
      await tester.pumpAndSettle();

      expect(find.text('Could not load settlements.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const ValueKey('locked_contact_bookalook')), findsOneWidget);
    });
  });

  group('contact BookALook', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(1080, 2400);
      binding.platformDispatcher.views.first.devicePixelRatio = 2.6;
    });
    tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

    testWidgets('sends the topic, settlement and message, then shows the history', (tester) async {
      final sent = <List<String?>>[];
      var history = <SupportRequest>[];

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ContactBookALookScreen(
          salonId: 's1',
          settlements: summary().settlements,
          loader: (_) async => (SalonSupportApi.defaultTopics, history),
          sender: (salonId, topic, message, payoutId) async {
            sent.add([salonId, topic, message, payoutId]);
            history = [
              SupportRequest(id: 'r1', topicLabel: 'Request my payout', message: message, status: 'open'),
            ];
            return 'Sent to BookALook.';
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nothing sent yet.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-payout_request')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('contact_settlement')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('19 Oct – 25 Oct 2026').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('contact_message')), 'Please release this payout.');
      await tester.ensureVisible(find.byKey(const ValueKey('contact_send')));
      await tester.tap(find.byKey(const ValueKey('contact_send')));
      await tester.pumpAndSettle();

      expect(sent.single, ['s1', 'payout_request', 'Please release this payout.', 'p1']);
      expect(find.text('Waiting'), findsOneWidget);
    });

    testWidgets('a too-short message is not sent', (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ContactBookALookScreen(
          salonId: 's1',
          loader: (_) async => (SalonSupportApi.defaultTopics, <SupportRequest>[]),
          sender: (_, _, _, _) async {
            calls++;
            return '';
          },
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('contact_message')), 'hi');
      await tester.ensureVisible(find.byKey(const ValueKey('contact_send')));
      await tester.tap(find.byKey(const ValueKey('contact_send')));
      await tester.pump();

      expect(calls, 0);
      expect(find.textContaining('Write a little more'), findsOneWidget);
    });

    testWidgets('a reply is shown under the message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ContactBookALookScreen(
          salonId: 's1',
          loader: (_) async => (
            SalonSupportApi.defaultTopics,
            [
              const SupportRequest(
                id: 'r1',
                topicLabel: 'Settlement query',
                message: 'Why is this cycle short?',
                status: 'resolved',
                reply: 'Two refunds were adjusted.',
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Two refunds were adjusted.'), findsOneWidget);

      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('BookALook replied'), findsOneWidget);
    });
  });
}
