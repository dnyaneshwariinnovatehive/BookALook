import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/time_window.dart';
import 'package:customer_app/widgets/slot_time_info_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appointment times are shown start to end, and the slot picker says its
/// times are start times.
void main() {
  test('a booking reads start to end', () {
    expect(formatTimeWindow('10:00:00', '10:45:00'), '10:00 AM – 10:45 AM');
    expect(formatTimeWindow('14:30', '16:00'), '2:30 PM – 4:00 PM');
  });

  test('a missing end shows just the start', () {
    expect(formatTimeWindow('09:15:00', null), '9:15 AM');
    expect(formatTimeWindow('09:15:00', ''), '9:15 AM');
    expect(formatTimeWindow(null, null), '');
  });

  test('the end is worked out from the start and duration', () {
    expect(addMinutesToClock('10:00', 45), '10:45');
    expect(addMinutesToClock('11:30', 90), '13:00');
    expect(addMinutesToClock('10:00', 0), isNull);
    expect(addMinutesToClock(null, 30), isNull);
  });

  testWidgets('the i button explains that slot times are start times', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: SlotTimeInfoButton(durationMinutes: 45, selectedStart: '10:00')),
    ));

    await tester.tap(find.byKey(const ValueKey('slot_time_info')));
    await tester.pumpAndSettle();

    expect(find.text('Slot times are start times'), findsOneWidget);
    expect(find.textContaining('10:00 AM – 10:45 AM'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Slot times are start times'), findsNothing);
  });
}
