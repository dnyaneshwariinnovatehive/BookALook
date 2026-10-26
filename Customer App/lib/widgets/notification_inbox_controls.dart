import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The date filters every inbox offers. [apiValue] is what the server's
/// `?period=` expects; null means everything.
enum NotificationPeriod {
  all('All', null),
  today('Today', 'today'),
  yesterday('Yesterday', 'yesterday'),
  week('Past week', 'week'),
  month('Past month', 'month');

  final String label;
  final String? apiValue;
  const NotificationPeriod(this.label, this.apiValue);
}

/// A row of filter capsules: All · Today · Yesterday · Past week · Past month.
class NotificationPeriodChips extends StatelessWidget {
  final NotificationPeriod selected;
  final ValueChanged<NotificationPeriod> onChanged;

  const NotificationPeriodChips({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: NotificationPeriod.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final period = NotificationPeriod.values[i];
          final isSelected = period == selected;
          return ChoiceChip(
            key: ValueKey('notification_period_${period.name}'),
            label: Text(period.label),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onChanged(period),
            selectedColor: AppTheme.accentColor,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : null,
            ),
            shape: const StadiumBorder(),
          );
        },
      ),
    );
  }
}

/// Asks before deleting every notification in view. True when confirmed.
Future<bool> confirmDeleteNotifications(BuildContext context, {required int count, required NotificationPeriod period}) async {
  final scope = period == NotificationPeriod.all ? 'all your notifications' : 'the $count notification${count == 1 ? '' : 's'} from ${period.label.toLowerCase()}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete notifications?'),
      content: Text('This will delete $scope. This cannot be undone.'),
      actions: [
        TextButton(key: const ValueKey('notifications_delete_cancel'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          key: const ValueKey('notifications_delete_confirm'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Swipe left to delete one notification.
class DeletableNotification extends StatelessWidget {
  final String id;
  final Widget child;
  final VoidCallback onDelete;

  const DeletableNotification({super.key, required this.id, required this.child, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('notification_$id'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(16)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white),
            SizedBox(width: 6),
            Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      child: child,
    );
  }
}
