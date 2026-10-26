import 'package:customer_app/screens/notifications_screen.dart';
import 'package:customer_app/services/notification_service.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInbox extends NotificationService {
  final List<String?> asked = [];
  final List<String> deleted = [];
  final List<String?> deletedPeriods = [];
  bool failDelete = false;
  List<Map<String, dynamic>> items;

  _FakeInbox(this.items);

  @override
  Future<Map<String, dynamic>> fetch({String? period}) async {
    asked.add(period);
    return {'notifications': items, 'unread_count': items.length};
  }

  @override
  Future<void> delete(String id) async {
    if (failDelete) throw Exception('no');
    deleted.add(id);
  }

  @override
  Future<int> deleteMany({String? period}) async {
    deletedPeriods.add(period);
    return items.length;
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}
}

/// The customer inbox: Today / Yesterday / Past week / Past month filters,
/// swipe to delete, and delete-all with a confirmation.
void main() {
  setUp(() => dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api'));

  Map<String, dynamic> n(String id, String title) => {
        'id': id,
        'title': title,
        'message': '$title message',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      };

  Future<void> pump(WidgetTester tester, _FakeInbox inbox) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: NotificationsScreen(service: inbox)));
    await tester.pumpAndSettle();
  }

  testWidgets('filters ask the server for that period', (tester) async {
    final inbox = _FakeInbox([n('1', 'Booking confirmed')]);
    await pump(tester, inbox);

    for (final label in ['All', 'Today', 'Yesterday', 'Past week', 'Past month']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('notification_period_yesterday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notification_period_week')));
    await tester.pumpAndSettle();

    expect(inbox.asked, [null, 'yesterday', 'week']);
  });

  testWidgets('swipe to delete; a refusal puts it back', (tester) async {
    final inbox = _FakeInbox([n('1', 'First'), n('2', 'Second')]);
    await pump(tester, inbox);

    await tester.drag(find.text('First'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(inbox.deleted, ['1']);
    expect(find.text('First'), findsNothing);

    inbox.failDelete = true;
    await tester.drag(find.text('Second'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.textContaining('Could not delete'), findsOneWidget);
  });

  testWidgets('delete all asks, and Cancel deletes nothing', (tester) async {
    final inbox = _FakeInbox([n('1', 'First')]);
    await pump(tester, inbox);

    await tester.tap(find.byKey(const ValueKey('notifications_delete_all')));
    await tester.pumpAndSettle();
    expect(find.textContaining('all your notifications'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notifications_delete_cancel')));
    await tester.pumpAndSettle();
    expect(inbox.deletedPeriods, isEmpty);

    await tester.tap(find.byKey(const ValueKey('notifications_delete_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notifications_delete_confirm')));
    await tester.pumpAndSettle();
    expect(inbox.deletedPeriods, [null]);
  });
}
