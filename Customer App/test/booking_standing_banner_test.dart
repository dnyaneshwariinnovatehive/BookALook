import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/booking_standing_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checkout tells a customer when the cancellation / no-show limit affects
/// their booking, and stays quiet otherwise.
void main() {
  Future<void> pump(WidgetTester tester, Map<String, dynamic>? standing) => tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: BookingStandingBanner(standing: standing))),
      );

  testWidgets('nothing shows for a customer in good standing', (tester) async {
    await pump(tester, {'restricted': false});
    expect(find.byKey(const ValueKey('booking_standing_banner')), findsNothing);
    await pump(tester, null);
    expect(find.byKey(const ValueKey('booking_standing_banner')), findsNothing);
  });

  testWidgets('a block says bookings are paused, with the reason', (tester) async {
    await pump(tester, {
      'restricted': true,
      'action': 'block',
      'message': 'You have 3 cancellations, so new bookings are paused until 12 Nov 2026.',
    });
    expect(find.text('Bookings are paused on your account'), findsOneWidget);
    expect(find.textContaining('until 12 Nov 2026'), findsOneWidget);
    expect(BookingStandingBanner.blocks({'restricted': true, 'action': 'block'}), isTrue);
  });

  testWidgets('full payment and warnings have their own wording', (tester) async {
    await pump(tester, {'restricted': true, 'action': 'full_payment', 'message': 'Pay in full.'});
    expect(find.text('Full payment needed for new bookings'), findsOneWidget);

    await pump(tester, {'restricted': true, 'action': 'warn', 'message': 'Careful.'});
    expect(find.text('Heads up about your bookings'), findsOneWidget);
    expect(BookingStandingBanner.blocks({'restricted': true, 'action': 'warn'}), isFalse);
  });
}
