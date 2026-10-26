import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/admin_provider_models.dart';
import 'package:partner_app/screens/dashboard/dashboard_screen.dart';
import 'package:partner_app/screens/dashboard/more/bank_details_screen.dart';
import 'package:partner_app/screens/dashboard/salon_selection_screen.dart';
import 'package:partner_app/screens/dashboard/salon_switching.dart';
import 'package:partner_app/screens/notifications_screen.dart';
import 'package:partner_app/screens/partner_home.dart';
import 'package:partner_app/screens/registration/steps/step_bank_details.dart';
import 'package:partner_app/screens/subscription_locked_screen.dart';
import 'package:partner_app/services/bank_details_api.dart';
import 'package:partner_app/services/salon_access_api.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One owner, several salons: the app opens the last one used, the list is
/// fresh and says which salons cannot open, a locked salon lets the owner
/// switch, bank details can be reused, and the inbox says which salon is which.
void main() {
  Map<String, dynamic> salon(String id, String status, {String? name}) =>
      {'id': id, 'name': name ?? 'Salon $id', 'status': status};

  Future<void> sized(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('which salon opens', () {
    test('the last salon used opens straight away', () {
      final salons = [salon('a', 'active'), salon('b', 'active')];
      expect(SalonSession.startSalon(salons, 'b')?['id'], 'b');
    });

    test('several salons and no last one: the owner chooses', () {
      final salons = [salon('a', 'active'), salon('b', 'active')];
      expect(SalonSession.startSalon(salons, null), isNull);
      expect(SalonSession.homeFor(salons), isA<SalonSelectionScreen>());
    });

    test('a last salon that can no longer open falls back to the list', () {
      final salons = [salon('a', 'active'), salon('b', 'deactivated')];
      expect(SalonSession.startSalon(salons, 'b'), isNull);
    });

    test('the only salon opens directly, unless it is still pending', () {
      expect(SalonSession.homeFor([salon('a', 'active')]), isA<DashboardScreen>());
      expect(SalonSession.homeFor([salon('a', 'pending_approval')]), isA<SalonSelectionScreen>());
      expect(partnerHomeFor({'role': 'admin', 'salons': [salon('a', 'active')]}), isA<DashboardScreen>());
    });

    test('remembers the salon and saves a fresh list for next time', () async {
      SharedPreferences.setMockInitialValues({
        'auth_state': jsonEncode({'role': 'admin', 'salons': [salon('a', 'pending_approval')]}),
      });
      await SalonSession.remember('a');
      expect(await SalonSession.lastSalonId(), 'a');

      final fresh = await SalonSession.refresh(fetch: () async => [salon('a', 'active')]);
      expect(fresh!.single['status'], 'active');
      expect((await SalonSession.cachedSalons()).single['status'], 'active');

      expect(await SalonSession.refresh(fetch: () async => throw Exception('offline')), isNull);
    });
  });

  group('salon list', () {
    testWidgets('re-reads the salons as it opens', (tester) async {
      await sized(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: SalonSelectionScreen(
          salons: [salon('a', 'pending_approval', name: 'Glow Baner')],
          fetchSalons: () async => [salon('a', 'active', name: 'Glow Baner')],
        ),
      ));
      expect(find.text('Pending'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsNothing);
    });

    testWidgets('marks suspended and deactivated salons, and explains a deactivated one', (tester) async {
      await sized(tester);
      final salons = [salon('a', 'suspended', name: 'Glow Baner'), salon('b', 'deactivated', name: 'Glow Aundh')];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: SalonSelectionScreen(salons: salons, fetchSalons: () async => salons),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('salon_badge_Suspended')), findsOneWidget);
      expect(find.byKey(const ValueKey('salon_badge_Deactivated')), findsOneWidget);

      await tester.tap(find.text('Glow Aundh'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('salon_deactivated_dialog')), findsOneWidget);
    });
  });

  testWidgets('a locked salon offers a switch when the owner has another', (tester) async {
    await sized(tester);
    var switched = 0;
    final access = SalonAccess(salonName: 'Glow Baner', isLocked: true, reason: 'subscription_expired', canRenew: true);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SubscriptionLockedScreen(access: access, onRecheck: () async {}, onSwitchSalon: () => switched++)),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('locked_switch_salon')));
    await tester.tap(find.byKey(const ValueKey('locked_switch_salon')));
    expect(switched, 1);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SubscriptionLockedScreen(access: access, onRecheck: () async {})),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('locked_switch_salon')), findsNothing);
  });

  test('owner-as-provider at another salon carries its message', () {
    final status = AdminProviderStatus.fromJson({
      'is_provider_enabled': false,
      'provider': null,
      'setup_validation': <String, dynamic>{},
      'provider_elsewhere': {
        'salon_id': 'a',
        'salon_name': 'Glow Baner',
        'is_active': true,
        'message': 'You already work as a service provider at Glow Baner.',
      },
    });
    expect(status.providerElsewhere?.salonName, 'Glow Baner');
    expect(status.providerElsewhere?.message, contains('Glow Baner'));
    expect(AdminProviderStatus.fromJson({'setup_validation': <String, dynamic>{}}).providerElsewhere, isNull);
  });

  group('same as my other salon', () {
    const other = OtherSalonBank(
      salonId: 'a',
      salonName: 'Glow Baner',
      details: BankDetails(bankName: 'HDFC Bank', ifsc: 'HDFC0001234', accountNumberLast4: '6789', hasRequired: true),
    );

    testWidgets('bank details: copies another salon\'s account after confirming', (tester) async {
      await sized(tester);
      final copied = <String>[];
      final results = <bool?>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => results.add(await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => BankDetailsScreen(
                    salonId: 'b',
                    load: (_) async => const BankDetailsStatus(
                      details: BankDetails(),
                      showMissingWarning: true,
                      otherSalons: [other],
                    ),
                    copyFrom: (salonId, from) async {
                      copied.add('$from->$salonId');
                      return BankDetailsStatus(details: other.details, showMissingWarning: false);
                    },
                  ),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('bank_same_as_other')));
      await tester.pumpAndSettle();
      expect(find.textContaining('the same account as Glow Baner'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bank_confirm_ok')));
      await tester.pumpAndSettle();

      expect(copied, ['a->b']);
      expect(results, [true]);
    });

    testWidgets('bank details: no other salon, no button', (tester) async {
      await sized(tester);
      await tester.pumpWidget(MaterialApp(
        home: BankDetailsScreen(
          salonId: 'b',
          load: (_) async => const BankDetailsStatus(details: BankDetails(), showMissingWarning: true),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bank_same_as_other')), findsNothing);
    });

    testWidgets('registering a branch: reuses another salon\'s account', (tester) async {
      await sized(tester);
      final out = <Map<String, dynamic>>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StepBankDetails(onNext: out.add, onBack: () {}, offerSaved: true, loadSaved: () async => [other]),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('bank_same_as_other')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reg_bank_copying')), findsOneWidget);
      expect(find.byKey(const ValueKey('bank_holder')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('reg_bank_continue')));
      await tester.pump();

      expect(out.single['bank_copy_from_salon_id'], 'a');
      expect(out.single['bank_account_number'], isNull);
    });
  });

  group('inbox for several salons', () {
    Map<String, dynamic> n(String id, String title, String salonName) => {
          'id': id,
          'type': 'general',
          'title': title,
          'message': '$title message',
          'is_read': false,
          'salon_name': salonName,
          'created_at': DateTime.now().toIso8601String(),
        };
    const salons = [
      {'id': 'a', 'name': 'Glow Baner', 'unread_count': 1},
      {'id': 'b', 'name': 'Glow Aundh', 'unread_count': 0},
    ];

    testWidgets('each notice names its salon, and the salon capsules filter', (tester) async {
      await sized(tester);
      final asked = <String?>[];
      final deletedFor = <String?>[];
      await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
          fetch: ({String? period, String? salonId}) async {
            asked.add(salonId);
            return {
              'notifications': [
                if (salonId != 'b') n('1', 'New booking', 'Glow Baner'),
                if (salonId != 'a') n('2', 'Leave request', 'Glow Aundh'),
              ],
              'unread_count': 2,
              'salons': salons,
            };
          },
          deleteMany: ({String? period, String? salonId}) async {
            deletedFor.add(salonId);
            return 1;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Glow Baner (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('notification_salon_tag_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('notification_salon_tag_2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notification_salon_b')));
      await tester.pumpAndSettle();
      expect(asked, [null, 'b']);
      expect(find.text('New booking'), findsNothing);
      // Narrowed to one salon, the tag would only repeat the filter.
      expect(find.byKey(const ValueKey('notification_salon_tag_2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('notifications_delete_all')));
      await tester.pumpAndSettle();
      expect(find.textContaining('for Glow Aundh'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notifications_delete_confirm')));
      await tester.pumpAndSettle();
      expect(deletedFor, ['b']);
    });

    testWidgets('a single-salon owner sees no salon capsules or tags', (tester) async {
      await sized(tester);
      await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
          fetch: ({String? period, String? salonId}) async => {
            'notifications': [n('1', 'New booking', 'Glow Baner')],
            'unread_count': 1,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification_salon_all')), findsNothing);
      expect(find.byKey(const ValueKey('notification_salon_tag_1')), findsNothing);
    });
  });
}
