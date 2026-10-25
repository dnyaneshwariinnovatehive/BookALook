import 'package:customer_app/screens/change_phone_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String?>> open(
    WidgetTester tester, {
    required Future<String> Function(String) send,
    required Future<String> Function(String, String) confirm,
  }) async {
    final results = <String?>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                results.add(await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangePhoneScreen(currentPhone: '9000000001', sendCode: send, confirm: confirm),
                  ),
                ));
              },
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

  testWidgets('sends a code to the new number, then saves it', (tester) async {
    final sent = <String>[];
    final confirmed = <String>[];
    final results = await open(
      tester,
      send: (p) async {
        sent.add(p);
        return 'OTP sent. For testing, use 123456.';
      },
      confirm: (p, otp) async {
        confirmed.add('$p/$otp');
        return p;
      },
    );

    await tester.enterText(find.byKey(const ValueKey('change_phone_number')), '98765 43210');
    await tester.tap(find.byKey(const ValueKey('change_phone_submit')));
    await tester.pumpAndSettle();

    expect(sent, ['9876543210']);
    expect(find.text('OTP sent. For testing, use 123456.'), findsOneWidget);
    expect(find.textContaining('Resend in'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('change_phone_otp')), '123456');
    await tester.tap(find.byKey(const ValueKey('change_phone_submit')));
    await tester.pumpAndSettle();

    expect(confirmed, ['9876543210/123456']);
    expect(results, ['9876543210']);
  });

  testWidgets('says why when the server refuses', (tester) async {
    await open(
      tester,
      send: (_) async => throw Exception('This number is already used by another account.'),
      confirm: (p, _) async => p,
    );

    await tester.enterText(find.byKey(const ValueKey('change_phone_number')), '9876543210');
    await tester.tap(find.byKey(const ValueKey('change_phone_submit')));
    await tester.pumpAndSettle();

    expect(find.text('This number is already used by another account.'), findsOneWidget);
    expect(find.byKey(const ValueKey('change_phone_otp')), findsNothing);
  });

  testWidgets('catches its own number and nonsense before asking the server', (tester) async {
    var calls = 0;
    await open(tester, send: (_) async {
      calls++;
      return 'sent';
    }, confirm: (p, _) async => p);

    await tester.enterText(find.byKey(const ValueKey('change_phone_number')), '9000000001');
    await tester.tap(find.byKey(const ValueKey('change_phone_submit')));
    await tester.pumpAndSettle();
    expect(find.text('This is already your phone number.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('change_phone_number')), '123');
    await tester.tap(find.byKey(const ValueKey('change_phone_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid phone number.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a wrong code keeps them on the screen with the reason', (tester) async {
    final results = await open(
      tester,
      send: (_) async => 'sent',
      confirm: (_, __) async => throw Exception('That code is not right.'),
    );

    await tester.enterText(find.byKey(const ValueKey('change_phone_number')), '9876543210');
    await tester.tap(find.byKey(const ValueKey('change_phone_submit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('change_phone_otp')), '000000');
    await tester.tap(find.byKey(const ValueKey('change_phone_submit')));
    await tester.pumpAndSettle();

    expect(find.text('That code is not right.'), findsOneWidget);
    expect(results, isEmpty);
  });
}
