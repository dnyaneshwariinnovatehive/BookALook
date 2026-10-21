import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/services/salon_access_api.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/widgets/subscription/subscription_bill_summary_sheet.dart';
import 'package:partner_app/widgets/subscription/payment_proof_viewer.dart';
import 'package:partner_app/screens/subscription_locked_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('SubscriptionBillSummarySheet Tests', () {
    testWidgets(
      'Displays plan name, validity, base price, coin discount, and net payable',
      (tester) async {
        final request = {
          'id': 101,
          'plan_name': 'Growth Pro Plan',
          'validity_days': 30,
          'base_price': 2000.0,
          'coins_to_redeem': 500,
          'coin_discount_inr': 500.0,
          'amount_payable_inr': 1500.0,
          'transaction_id': 'UTR987654321',
          'note': 'Transferred via PhonePe',
          'status': 'pending',
          'created_at': '2026-10-18T10:30:00Z',
          'screenshot_url': 'https://example.com/proof.jpg',
        };

        await tester.pumpWidget(
          _wrap(SubscriptionBillSummarySheet(request: request)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Subscription Bill Summary'), findsOneWidget);
        expect(find.text('UNDER REVIEW'), findsOneWidget);
        expect(find.text('Growth Pro Plan'), findsOneWidget);
        expect(find.text('30 days access per billing cycle'), findsOneWidget);

        // Financial breakdown
        expect(find.text('Base Plan Price'), findsOneWidget);
        expect(find.text('₹2000.00'), findsOneWidget);
        expect(find.text('Reward Coins Applied (500 coins)'), findsOneWidget);
        expect(find.text('−₹500.00'), findsOneWidget);
        expect(find.text('Amount Submitted'), findsOneWidget);
        expect(find.text('₹1500.00'), findsOneWidget);

        // Transaction audit
        expect(find.text('Manual Bank Transfer / UPI'), findsOneWidget);
        expect(find.text('UTR987654321'), findsOneWidget);
        expect(find.text('Transferred via PhonePe'), findsOneWidget);

        // Action button
        expect(find.text('View Payment Proof'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);
      },
    );

    testWidgets('Displays APPROVED status chip when request is approved', (
      tester,
    ) async {
      final request = {
        'id': 102,
        'plan_name': 'Basic Plan',
        'validity_days': 15,
        'base_price': 1000.0,
        'coins_to_redeem': 0,
        'coin_discount_inr': 0.0,
        'amount_payable_inr': 1000.0,
        'status': 'approved',
        'created_at': '2026-10-15T12:00:00Z',
      };

      await tester.pumpWidget(
        _wrap(SubscriptionBillSummarySheet(request: request)),
      );
      await tester.pumpAndSettle();

      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('Total Amount Paid'), findsOneWidget);
      expect(find.text('₹1000.00'), findsNWidgets(2));
    });

    testWidgets('Displays NOT ACCEPTED status chip when request is rejected', (
      tester,
    ) async {
      final request = {
        'id': 103,
        'plan_name': 'Growth Plan',
        'validity_days': 30,
        'base_price': 1999.0,
        'coins_to_redeem': 0,
        'coin_discount_inr': 0.0,
        'amount_payable_inr': 1999.0,
        'status': 'rejected',
        'created_at': '2026-10-16T12:00:00Z',
      };

      await tester.pumpWidget(
        _wrap(SubscriptionBillSummarySheet(request: request)),
      );
      await tester.pumpAndSettle();

      expect(find.text('NOT ACCEPTED'), findsOneWidget);
    });
  });

  group('PaymentProofViewer Tests', () {
    testWidgets('Renders header with reference, note, and close button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PaymentProofViewer(
            imageUrl: 'https://example.com/receipt.png',
            title: 'Transfer Proof',
            transactionId: 'UTR-112233',
            note: 'Bank statement line 42',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Transfer Proof'), findsOneWidget);
      expect(find.text('Ref: UTR-112233'), findsOneWidget);
      expect(find.text('Bank statement line 42'), findsOneWidget);
      expect(find.text('Open original'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });

  group('SubscriptionLockedScreen Tests', () {
    testWidgets(
      'Displays Payment Received — Under Review card when approval is pending',
      (tester) async {
        bool rechecked = false;

        final access = SalonAccess(
          salonName: 'Glow Studio',
          isLocked: true,
          canRenew: true,
          reason: 'no_subscription',
          hasPendingRequest: true,
          pendingRequest: {
            'id': 201,
            'plan_name': 'VIP Growth',
            'amount_payable_inr': 2499.0,
            'transaction_id': 'UTR-PENDING-77',
            'status': 'pending',
            'created_at': '2026-10-18T14:00:00Z',
          },
        );

        await tester.pumpWidget(
          _wrap(
            SubscriptionLockedScreen(
              access: access,
              onRecheck: () async {
                rechecked = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Payment Received — Under Review'), findsOneWidget);
        expect(find.text('UNDER REVIEW'), findsOneWidget);
        expect(find.text('VIP Growth'), findsOneWidget);
        expect(find.text('₹2499.00'), findsOneWidget);
        expect(find.text('UTR-PENDING-77'), findsOneWidget);
        expect(find.text('Bill Summary'), findsOneWidget);
        expect(find.text('Check Review Status'), findsOneWidget);

        await tester.tap(find.text('Check Review Status'));
        expect(rechecked, isTrue);
      },
    );

    testWidgets(
      'Displays Payment Not Accepted when latest request was rejected',
      (tester) async {
        final access = SalonAccess(
          salonName: 'Glow Studio',
          isLocked: true,
          canRenew: true,
          reason: 'subscription_expired',
          hasPendingRequest: false,
          latestRejectedRequest: {
            'id': 202,
            'plan_name': 'Growth',
            'status': 'rejected',
          },
        );

        await tester.pumpWidget(
          _wrap(
            SubscriptionLockedScreen(access: access, onRecheck: () async {}),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Payment Not Accepted'), findsOneWidget);
        expect(find.text('Choose a plan & re-submit'), findsOneWidget);
      },
    );

    testWidgets(
      'Displays normal welcome state when salon has never subscribed and has no pending payment',
      (tester) async {
        final access = SalonAccess(
          salonName: 'New Salon',
          isLocked: true,
          canRenew: true,
          reason: 'no_subscription',
          hasPendingRequest: false,
        );

        await tester.pumpWidget(
          _wrap(
            SubscriptionLockedScreen(access: access, onRecheck: () async {}),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Choose your plan'), findsOneWidget);
        expect(find.text('Choose a plan'), findsOneWidget);
      },
    );

    testWidgets(
      'Displays Payment Received — Under Review wall when brand new salon submitted proof (never shows Choose your plan)',
      (tester) async {
        final access = SalonAccess(
          salonName: 'Newly Approved Salon',
          isLocked: true,
          canRenew: true,
          reason: 'no_subscription',
          hasPendingRequest: true,
          pendingRequest: {
            'id': 301,
            'plan_name': 'Growth Plan',
            'amount_payable_inr': 1999.0,
            'transaction_id': 'GROWTH-REF-99',
            'status': 'pending',
          },
        );

        await tester.pumpWidget(
          _wrap(
            SubscriptionLockedScreen(access: access, onRecheck: () async {}),
          ),
        );
        await tester.pumpAndSettle();

        // Must show the Under Review screen and wall
        expect(find.text('Payment Received — Under Review'), findsOneWidget);
        expect(find.text('UNDER REVIEW'), findsOneWidget);
        expect(find.text('Growth Plan'), findsOneWidget);
        expect(find.text('Check Review Status'), findsOneWidget);

        // Must NOT show the first-time choose your plan welcome
        expect(find.text('Choose your plan'), findsNothing);
      },
    );

    testWidgets(
      'Preserves welcome_shown flags across logout on SubscriptionLockedScreen',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'auth_token': 'dummy-token',
          'welcome_shown_101': true,
          'welcome_shown_102': true,
          'other_key': 'to_be_cleared',
        });

        final access = SalonAccess(
          salonName: 'Test Salon',
          isLocked: true,
          canRenew: true,
          reason: 'no_subscription',
          hasPendingRequest: true,
          pendingRequest: {
            'id': 1,
            'plan_name': 'Growth',
            'status': 'pending',
          },
        );

        await tester.pumpWidget(
          _wrap(
            SubscriptionLockedScreen(access: access, onRecheck: () async {}),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll to and tap log out
        await tester.ensureVisible(find.text('Log out'));
        await tester.tap(find.text('Log out'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final prefs = await SharedPreferences.getInstance();
        // Auth keys should be wiped
        expect(prefs.getString('auth_token'), isNull);
        expect(prefs.getString('other_key'), isNull);
        // welcome_shown flags must be preserved!
        expect(prefs.getBool('welcome_shown_101'), isTrue);
        expect(prefs.getBool('welcome_shown_102'), isTrue);
      },
    );
  });
}
