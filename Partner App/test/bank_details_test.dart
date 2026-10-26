import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/onboarding_draft.dart';
import 'package:partner_app/screens/dashboard/more/bank_details_screen.dart';
import 'package:partner_app/screens/registration/steps/step_bank_details.dart';
import 'package:partner_app/services/bank_details_api.dart';
import 'package:partner_app/widgets/bank_details_fields.dart';

void main() {
  group('rules', () {
    test('accept good values and blanks', () {
      expect(BankDetailsRules.ifsc('hdfc0001234'), isNull);
      expect(BankDetailsRules.ifsc(''), isNull);
      expect(BankDetailsRules.account('5010 0123 4567 89'), isNull);
      expect(BankDetailsRules.upi('asha@okhdfcbank'), isNull);
      expect(BankDetailsRules.holder("Asha D'Souza"), isNull);
    });

    test('refuse bad values', () {
      expect(BankDetailsRules.ifsc('HDFC1234567'), isNotNull);
      expect(BankDetailsRules.account('1234'), isNotNull);
      expect(BankDetailsRules.upi('asha'), isNotNull);
      expect(BankDetailsRules.holder('Asha 99'), isNotNull);
    });

    test('the four transfer fields go together', () {
      final c = BankDetailsControllers()..account.text = '50100123456789';
      c.confirmAccount.text = '50100123456789';
      expect(c.crossCheck(), contains('together'));

      c
        ..holder.text = 'Asha'
        ..bankName.text = 'HDFC Bank'
        ..ifsc.text = 'HDFC0001234';
      expect(c.crossCheck(), isNull);
      expect(c.toPayload()['bank_ifsc'], 'HDFC0001234');
    });

    test('a saved account counts, so a blank number is not missing', () {
      final c = BankDetailsControllers()
        ..holder.text = 'Asha'
        ..bankName.text = 'HDFC Bank'
        ..ifsc.text = 'HDFC0001234'
        ..hasSavedAccount = true;
      expect(c.crossCheck(), isNull);
      expect(c.toPayload().containsKey('bank_account_number'), isFalse);
    });
  });

  group('collaborator draft', () {
    test('half-entered bank details are flagged; none at all is fine', () {
      final d = OnboardingDraft(enquiryId: 'e1');
      expect(d.bankProblems, isEmpty);

      d.bankAccount = '50100123456789';
      expect(d.bankProblems.join(), contains('together'));

      d
        ..bankHolder = 'Asha'
        ..bankName = 'HDFC Bank'
        ..bankIfsc = 'HDFC0001234';
      expect(d.bankProblems, isEmpty);
      expect(d.toFormFields()['bank_account_number'], '50100123456789');
    });

    test('details from the website form prefill, masked', () {
      final d = OnboardingDraft.fromEnquiry({
        'id': 'e1',
        'bank_details': {
          'account_holder_name': 'Asha',
          'bank_name': 'HDFC Bank',
          'ifsc': 'HDFC0001234',
          'account_number_last4': '6789',
        },
      });
      expect(d.savedBankSummary, 'HDFC Bank •••• 6789');
      expect(d.bankAccount, isEmpty);
      expect(d.bankProblems, isEmpty);
      expect(d.toFormFields().containsKey('bank_account_number'), isFalse);
    });

    test('bank details survive the draft round trip', () {
      final d = OnboardingDraft(enquiryId: 'e1', bankHolder: 'Asha', bankIfsc: 'HDFC0001234', hasSavedBankAccount: true);
      final back = OnboardingDraft.fromJson(d.toJson());
      expect(back.bankHolder, 'Asha');
      expect(back.bankIfsc, 'HDFC0001234');
      expect(back.hasSavedBankAccount, isTrue);
    });
  });

  // ---------------------------------------------------------------- screen

  const empty = BankDetailsStatus(details: BankDetails(), showMissingWarning: true);
  const saved = BankDetailsStatus(
    details: BankDetails(
      accountHolderName: 'Asha',
      bankName: 'HDFC Bank',
      ifsc: 'HDFC0001234',
      accountNumberLast4: '6789',
      hasRequired: true,
      hasAny: true,
    ),
    showMissingWarning: false,
  );

  Future<List<bool?>> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final results = <bool?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('bank_holder')), 'Asha Kulkarni');
    await tester.enterText(find.byKey(const ValueKey('bank_name')), 'HDFC Bank');
    await tester.enterText(find.byKey(const ValueKey('bank_account')), '50100123456789');
    await tester.enterText(find.byKey(const ValueKey('bank_account_confirm')), '50100123456789');
    await tester.enterText(find.byKey(const ValueKey('bank_ifsc')), 'HDFC0001234');
    await tester.pump();
  }

  testWidgets('saving new details asks first; cancel saves nothing', (tester) async {
    var calls = 0;
    await open(
      tester,
      BankDetailsScreen(
        salonId: 's1',
        load: (_) async => empty,
        save: (_, __) async {
          calls++;
          return saved;
        },
      ),
    );

    await fill(tester);
    await tester.tap(find.byKey(const ValueKey('bank_save')));
    await tester.pumpAndSettle();

    expect(find.text('Are you sure you want to save these bank details? BookALook will send your settlements to this account.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bank_confirm_cancel')));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(BankDetailsScreen), findsOneWidget);
  });

  testWidgets('confirming saves, says so, and closes with true', (tester) async {
    Map<String, String>? sent;
    final results = await open(
      tester,
      BankDetailsScreen(
        salonId: 's1',
        load: (_) async => empty,
        save: (_, fields) async {
          sent = fields;
          return saved;
        },
      ),
    );

    await fill(tester);
    await tester.tap(find.byKey(const ValueKey('bank_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bank_confirm_ok')));
    await tester.pumpAndSettle();

    expect(sent?['bank_ifsc'], 'HDFC0001234');
    expect(sent?['bank_account_number'], '50100123456789');
    expect(results, [true]);
    expect(find.text('Bank details saved.'), findsOneWidget);
  });

  testWidgets('changing saved details warns that they will be replaced', (tester) async {
    await open(tester, BankDetailsScreen(salonId: 's1', load: (_) async => saved, save: (_, __) async => saved));

    expect(find.text('Update bank details'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bank_upi')), 'asha@okaxis');
    await tester.tap(find.byKey(const ValueKey('bank_save')));
    await tester.pumpAndSettle();

    expect(find.text('Replace saved bank details?'), findsOneWidget);
    expect(find.textContaining('HDFC Bank •••• 6789'), findsWidgets);
  });

  testWidgets('a failed save shows the error and stays open', (tester) async {
    final results = await open(
      tester,
      BankDetailsScreen(
        salonId: 's1',
        load: (_) async => empty,
        save: (_, __) async => throw Exception('Enter a valid IFSC code, for example HDFC0001234.'),
      ),
    );

    await fill(tester);
    await tester.tap(find.byKey(const ValueKey('bank_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bank_confirm_ok')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bank_form_error')), findsOneWidget);
    expect(find.text('Bank details saved.'), findsNothing);
    expect(results, isEmpty);
  });

  testWidgets('invalid input never reaches the confirm step', (tester) async {
    await open(tester, BankDetailsScreen(salonId: 's1', load: (_) async => empty, save: (_, __) async => saved));

    await fill(tester);
    await tester.enterText(find.byKey(const ValueKey('bank_ifsc')), 'BAD');
    await tester.tap(find.byKey(const ValueKey('bank_save')));
    await tester.pumpAndSettle();

    expect(find.text('Save bank details?'), findsNothing);
    expect(find.textContaining('valid IFSC'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks; Stay keeps them', (tester) async {
    await open(tester, BankDetailsScreen(salonId: 's1', load: (_) async => empty, save: (_, __) async => saved));

    await tester.enterText(find.byKey(const ValueKey('bank_holder')), 'Asha');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bank_leave_stay')));
    await tester.pumpAndSettle();
    expect(find.byType(BankDetailsScreen), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bank_leave_discard')));
    await tester.pumpAndSettle();
    expect(find.byType(BankDetailsScreen), findsNothing);
  });

  // ---------------------------------------------------------------- registration step

  Future<List<Map<String, dynamic>>> step(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final out = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StepBankDetails(onNext: out.add, onBack: () {}))));
    return out;
  }

  testWidgets('registration: skipping sends no bank details', (tester) async {
    final out = await step(tester);
    await tester.enterText(find.byKey(const ValueKey('bank_holder')), 'Half typed');
    await tester.tap(find.byKey(const ValueKey('reg_bank_skip')));
    await tester.pump();

    expect(out.single.values.every((v) => v == null), isTrue);
  });

  testWidgets('registration: continuing with full details sends them', (tester) async {
    final out = await step(tester);
    await fill(tester);
    await tester.tap(find.byKey(const ValueKey('reg_bank_continue')));
    await tester.pump();

    expect(out.single['bank_account_number'], '50100123456789');
    expect(out.single['bank_ifsc'], 'HDFC0001234');
  });

  testWidgets('registration: half an account blocks Continue with a reason', (tester) async {
    final out = await step(tester);
    await tester.enterText(find.byKey(const ValueKey('bank_holder')), 'Asha');
    await tester.tap(find.byKey(const ValueKey('reg_bank_continue')));
    await tester.pump();

    expect(out, isEmpty);
    expect(find.byKey(const ValueKey('reg_bank_error')), findsOneWidget);
  });
}
