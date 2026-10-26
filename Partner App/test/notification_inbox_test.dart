import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partner_app/screens/dashboard/collaborator_tabs/collaborator_notifications_screen.dart';
import 'package:partner_app/screens/notifications_screen.dart';
import 'package:partner_app/services/collaborator_api.dart';
import 'package:partner_app/theme/app_theme.dart';

/// Inbox filters (Today, Yesterday, Past week, Past month) and deleting, for
/// salon owners and staff, and for collaborators.
void main() {
  Map<String, dynamic> n(String id, String title) => {
        'id': id,
        'type': 'general',
        'title': title,
        'message': '$title message',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      };

  Future<void> sized(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('owner and staff inbox', () {
    testWidgets('filter capsules ask the server for that period', (tester) async {
      await sized(tester);
      final asked = <String?>[];
      await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
          fetch: ({String? period, String? salonId}) async {
            asked.add(period);
            return {'notifications': [n('1', period ?? 'everything')], 'unread_count': 1};
          },
        ),
      ));
      await tester.pumpAndSettle();

      for (final label in ['Today', 'Yesterday', 'Past week', 'Past month', 'All']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('notification_period_today')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification_period_month')));
      await tester.pumpAndSettle();

      expect(asked, [null, 'today', 'month']);
      expect(find.text('month'), findsOneWidget);
    });

    testWidgets('swiping deletes one notification', (tester) async {
      await sized(tester);
      final deleted = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
          fetch: ({String? period, String? salonId}) async => {'notifications': [n('1', 'First'), n('2', 'Second')], 'unread_count': 2},
          delete: (id) async => deleted.add(id),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.text('First'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(deleted, ['1']);
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('a refused delete puts the notification back', (tester) async {
      await sized(tester);
      await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
          fetch: ({String? period, String? salonId}) async => {'notifications': [n('1', 'First')], 'unread_count': 1},
          delete: (id) async => throw Exception('no'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.text('First'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('First'), findsOneWidget);
      expect(find.textContaining('Could not delete'), findsOneWidget);
    });

    testWidgets('delete all asks first and deletes only the filtered period', (tester) async {
      await sized(tester);
      final deletedPeriods = <String?>[];
      await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
          fetch: ({String? period, String? salonId}) async => {'notifications': [n('1', 'First')], 'unread_count': 1},
          deleteMany: ({String? period, String? salonId}) async {
            deletedPeriods.add(period);
            return 1;
          },
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification_period_yesterday')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notifications_delete_all')));
      await tester.pumpAndSettle();
      expect(find.text('Delete notifications?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notifications_delete_cancel')));
      await tester.pumpAndSettle();
      expect(deletedPeriods, isEmpty);

      await tester.tap(find.byKey(const ValueKey('notifications_delete_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notifications_delete_confirm')));
      await tester.pumpAndSettle();
      expect(deletedPeriods, ['yesterday']);
    });
  });

  group('collaborator inbox', () {
    CollaboratorNotification cn(String id, String title) => CollaboratorNotification.fromJson({
          'id': id,
          'type': 'general',
          'title': title,
          'message': '$title message',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });

    testWidgets('has the same filters and delete', (tester) async {
      await sized(tester);
      final asked = <String?>[];
      final deleted = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CollaboratorNotificationsScreen(
          fetch: ({String? period}) async {
            asked.add(period);
            return CollaboratorInbox(notifications: [cn('1', 'Plan ending')]);
          },
          delete: (id) async => deleted.add(id),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notification_period_week')));
      await tester.pumpAndSettle();
      expect(asked, [null, 'week']);

      await tester.drag(find.text('Plan ending'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(deleted, ['1']);
    });
  });
}
