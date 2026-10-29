import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/subscription_locked_screen.dart';
import 'package:partner_app/services/salon_access_api.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/commission_dues_banner.dart';

Widget app(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  test('reads the dues block from the access payload', () {
    final access = SalonAccess.fromJson({
      'salon_name': 'Velvet',
      'is_locked': false,
      'can_renew': true,
      'bookings_paused': true,
      'dues': {
        'owed': 3800,
        'due_date': '2026-10-06',
        'days_overdue': 12,
        'under_review': 0,
        'actions': ['reminder', 'banner', 'force_advance', 'deduct', 'stop_bookings'],
        'stage': 'stop_bookings',
        'next': {'step': 'full_lock', 'label': 'Full lock', 'on': '2026-10-26'},
      },
    });

    expect(access.bookingsPaused, isTrue);
    expect(access.dues!.owed, 3800);
    expect(access.dues!.has('stop_bookings'), isTrue);
    expect(access.dues!.nextLabel, 'Full lock');
    expect(access.isCommissionLock, isFalse);
  });

  testWidgets('the banner says bookings are paused, what else applies, and what comes next', (tester) async {
    var paid = 0;
    await tester.pumpWidget(app(CommissionDuesBanner(
      salonId: 's1',
      onPay: () => paid++,
      dues: const CommissionDues(
        owed: 3800,
        dueDate: '2026-10-06',
        daysOverdue: 12,
        actions: ['reminder', 'banner', 'force_advance', 'deduct', 'stop_bookings'],
        stage: 'stop_bookings',
        nextLabel: 'Full lock',
        nextOn: '2026-10-26',
      ),
    )));

    expect(find.text('Online bookings paused'), findsOneWidget);
    expect(find.textContaining('Customers now pay the full amount online'), findsOneWidget);
    expect(find.textContaining('deducted from the money BookALook pays you'), findsOneWidget);
    expect(find.textContaining('From 26 Oct: full lock'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('commission_dues_pay')));
    expect(paid, 1);
  });

  testWidgets('before the due date it is a gentle reminder', (tester) async {
    await tester.pumpWidget(app(const CommissionDuesBanner(
      salonId: 's1',
      dues: CommissionDues(owed: 1200, dueDate: '2026-11-07', daysOverdue: -2, actions: ['reminder'], stage: 'reminder'),
    )));

    expect(find.textContaining('commission due 7 Nov'), findsOneWidget);
    expect(find.textContaining('Pay it before the due date'), findsOneWidget);
  });

  testWidgets('nothing at all when nothing applies', (tester) async {
    await tester.pumpWidget(app(const CommissionDuesBanner(salonId: 's1', dues: CommissionDues(owed: 0))));
    expect(find.byKey(const ValueKey('commission_dues_banner')), findsNothing);
  });

  testWidgets('a commission lock asks the owner to pay, not to renew a plan', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final access = SalonAccess(
      salonName: 'Velvet',
      isLocked: true,
      reason: 'commission_unsettled',
      canRenew: true,
      walletCoins: 500,
      walletValueInr: 500,
      dues: const CommissionDues(owed: 3800, dueDate: '2026-10-06', daysOverdue: 25, actions: ['full_lock'], stage: 'full_lock'),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SubscriptionLockedScreen(access: access, onRecheck: () async {})),
    ));
    await tester.pump();

    expect(find.text('Commission payment overdue'), findsOneWidget);
    expect(find.textContaining('₹3800 owed to BookALook has been overdue since 6 October'), findsOneWidget);
    expect(find.byKey(const ValueKey('locked_pay_commission')), findsOneWidget);
    expect(find.text('Renew now'), findsNothing);
  });
}
