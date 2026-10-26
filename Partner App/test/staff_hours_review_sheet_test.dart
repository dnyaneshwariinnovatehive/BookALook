import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/models/salon_working_hour.dart';
import 'package:partner_app/models/staff_models.dart';
import 'package:partner_app/services/salon_settings_api.dart';
import 'package:partner_app/widgets/staff_hours_review_sheet.dart';

void main() {
  SalonWorkingHour day(int d, String? open, String? close) =>
      SalonWorkingHour(dayOfWeek: d, isClosed: open == null, openTime: open, closeTime: close);

  // Before: 10:00–20:00 every day. After: Saturday 09:00–22:00, Sunday closed.
  final before = List.generate(7, (d) => day(d, '10:00:00', '20:00:00'));
  final after = List.generate(
    7,
    (d) => d == 6 ? day(6, '09:00:00', '22:00:00') : d == 0 ? day(0, null, null) : day(d, '10:00:00', '20:00:00'),
  );

  List<StaffWorkingHour> week(String start, String end, {Set<int> off = const {}}) => List.generate(
        7,
        (d) => StaffWorkingHour(
          dayOfWeek: d,
          isWeeklyOff: off.contains(d),
          shiftStart: off.contains(d) ? null : start,
          shiftEnd: off.contains(d) ? null : end,
        ),
      );

  StaffMember member(String id, String name, {required bool follows, List<StaffWorkingHour>? hours}) => StaffMember(
        id: id,
        userId: 'u-$id',
        salonId: 'salon-1',
        baseSalary: 0,
        commissionPercentage: 10,
        isActive: true,
        useSalonHours: follows,
        user: {'name': name},
        workingHours: hours ?? week('10:00:00', '20:00:00'),
      );

  group('salonHourChanges', () {
    test('lists only the days that changed', () {
      final changes = salonHourChanges(before, after);
      expect(changes.map((c) => c.dayOfWeek), [0, 6]);
      expect(changes.first.nowClosed, isTrue);
      expect(changes.last.nowClosed, isFalse);
    });

    test('treats 09:00 and 09:00:00 as the same time', () {
      final a = [day(1, '09:00', '18:00')];
      final b = [day(1, '09:00:00', '18:00:00')];
      expect(salonHourChanges(a, b), isEmpty);
    });

    test('a day that opens again is newly open', () {
      final changes = salonHourChanges([day(0, null, null)], [day(0, '10:00:00', '14:00:00')]);
      expect(changes.single.newlyOpen, isTrue);
    });
  });

  Future<List<Map<String, dynamic>>> pumpSheet(
    WidgetTester tester,
    List<StaffMember> staff, {
    WorkingHoursSaveResult result = const WorkingHoursSaveResult(),
    List<int?>? returned,
  }) async {
    final calls = <Map<String, dynamic>>[];
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await showStaffHoursReviewSheet(
                  context,
                  salonId: 'salon-1',
                  staff: staff,
                  changes: salonHourChanges(before, after),
                  result: result,
                  save: ({required salonId, required staffId, required hours}) async {
                    calls.add({'staffId': staffId, 'hours': hours});
                  },
                );
                returned?.add(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('staff on salon hours are only mentioned, not asked', (tester) async {
    await pumpSheet(tester, [
      member('a', 'Asha', follows: true),
      member('p', 'Priya', follows: false, hours: week('11:00:00', '19:00:00')),
    ]);

    expect(find.byKey(const ValueKey('staff_hours_following_note')), findsOneWidget);
    expect(find.textContaining('Asha follows salon hours'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff_hours_row_a_6')), findsNothing);
    // Custom staff are asked about the changed open day only.
    expect(find.byKey(const ValueKey('staff_hours_row_p_6')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff_hours_row_p_1')), findsNothing);
    // Sunday closed is information, not a question.
    expect(find.byKey(const ValueKey('staff_hours_closed_0')), findsOneWidget);
  });

  testWidgets('keeping everyone saves nothing', (tester) async {
    final returned = <int?>[];
    final calls = await pumpSheet(
      tester,
      [member('p', 'Priya', follows: false, hours: week('11:00:00', '19:00:00'))],
      returned: returned,
    );

    await tester.tap(find.byKey(const ValueKey('staff_hours_save')));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(returned, [0]);
  });

  testWidgets('extending changes only that day and keeps the rest of the week', (tester) async {
    final calls = await pumpSheet(tester, [
      member('p', 'Priya', follows: false, hours: week('11:00:00', '19:00:00')),
    ]);

    await tester.tap(find.byKey(const ValueKey('staff_hours_salon_p_6')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff_hours_save')));
    await tester.pumpAndSettle();

    final hours = calls.single['hours'] as List<StaffWorkingHour>;
    expect(hours[6].shiftStart, '09:00:00');
    expect(hours[6].shiftEnd, '22:00:00');
    expect(hours[1].shiftStart, '11:00:00');
    expect(hours[1].shiftEnd, '19:00:00');
  });

  testWidgets('"extend everyone" puts every custom row on salon hours', (tester) async {
    final calls = await pumpSheet(tester, [
      member('p', 'Priya', follows: false, hours: week('11:00:00', '19:00:00')),
      member('r', 'Ravi', follows: false, hours: week('12:00:00', '18:00:00')),
    ]);

    await tester.tap(find.byKey(const ValueKey('staff_hours_extend_all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff_hours_save')));
    await tester.pumpAndSettle();

    expect(calls.map((c) => c['staffId']), containsAll(['p', 'r']));
    for (final c in calls) {
      final hours = c['hours'] as List<StaffWorkingHour>;
      expect(hours[6].shiftStart, '09:00:00');
      expect(hours[6].shiftEnd, '22:00:00');
    }
  });

  testWidgets('someone off that day can stay off or start working', (tester) async {
    final calls = await pumpSheet(tester, [
      member('p', 'Priya', follows: false, hours: week('11:00:00', '19:00:00', off: {6})),
    ]);

    expect(find.text('Stay off'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('staff_hours_salon_p_6')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff_hours_save')));
    await tester.pumpAndSettle();

    final hours = calls.single['hours'] as List<StaffWorkingHour>;
    expect(hours[6].isWeeklyOff, isFalse);
    expect(hours[6].shiftStart, '09:00:00');
  });

  testWidgets('shows trimmed shifts and warns about bookings outside the hours', (tester) async {
    await pumpSheet(
      tester,
      [member('p', 'Priya', follows: false, hours: week('09:00:00', '22:00:00'))],
      result: const WorkingHoursSaveResult(
        trimmed: [
          TrimmedShift(providerId: 'p', name: 'Priya', dayOfWeek: 6, fromStart: '08:00', fromEnd: '23:00', toStart: '09:00', toEnd: '22:00'),
        ],
        bookingsOutsideHours: {6: 2},
      ),
    );

    expect(find.byKey(const ValueKey('staff_hours_trimmed_p_6')), findsOneWidget);
    expect(find.byKey(const ValueKey('staff_hours_bookings_warning')), findsOneWidget);
    expect(find.textContaining('2 upcoming bookings'), findsOneWidget);
    expect(find.textContaining('have not been moved'), findsOneWidget);
  });

  test('the sheet is skipped when there is nothing to ask or warn about', () {
    final changes = salonHourChanges(before, after);
    expect(
      staffHoursSheetNeeded(changes: changes, staff: [member('a', 'Asha', follows: true)], result: const WorkingHoursSaveResult()),
      isFalse,
    );
    expect(
      staffHoursSheetNeeded(changes: changes, staff: [member('p', 'Priya', follows: false)], result: const WorkingHoursSaveResult()),
      isTrue,
    );
  });
}
