import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/collaborator_api.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/collaborator/collaborator_card.dart';
import '../../../widgets/collaborator/collaborator_empty_state.dart';

/// The collaborator's inbox.
///
/// Opens from the bell on Home. Not the owner's notification screen: this list
/// only ever holds notices about the salons assigned to this collaborator, which
/// is what makes it worth reading — every card is a salon they are answerable
/// for, and tapping one gives them the one thing they can actually do about it.
///
/// Order is the server's, and it is strictly chronological, newest first — an
/// inbox that reordered itself would hide when a lapse actually happened, which
/// is the one thing these notices are for. Importance is not lost by that: the
/// bell badge counts only the important unread ones, and each important card is
/// drawn differently on the way down the list.
class CollaboratorNotificationsScreen extends StatefulWidget {
  /// Returned so the bell behind this screen can drop its badge the moment the
  /// collaborator comes back, rather than waiting for the next poll.
  final Future<void> Function()? onRead;

  const CollaboratorNotificationsScreen({super.key, this.onRead});

  @override
  State<CollaboratorNotificationsScreen> createState() =>
      _CollaboratorNotificationsScreenState();
}

class _CollaboratorNotificationsScreenState
    extends State<CollaboratorNotificationsScreen> {
  List<CollaboratorNotification> _notifications = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = _notifications.isEmpty);
    }

    final inbox = await CollaboratorApi.notifications();

    if (!mounted) return;

    setState(() {
      _notifications = inbox.notifications;
      _loading = false;
    });

    // Deliberately no [onRead] here. Nothing has been read yet by opening the
    // screen, so telling the bell to re-poll would spend a request to learn the
    // same count it already had. [onRead] fires on the marks that change it.
  }

  /// Read state is optimistic: the card goes read on tap and the dot disappears
  /// immediately. The request is fire-and-forget because a notification that
  /// refuses to mark itself read is not worth an error dialog, and the next
  /// load tells the truth regardless.
  void _markRead(CollaboratorNotification notification) {
    if (notification.isRead) return;

    setState(() {
      _notifications = _notifications
          .map((n) => n.id == notification.id ? n.copyWith(read: true) : n)
          .toList();
    });

    CollaboratorApi.markNotificationRead(notification.id);
  }

  Future<void> _markAllRead() async {
    setState(() {
      _notifications = _notifications
          .map((n) => n.copyWith(read: true))
          .toList();
    });

    await CollaboratorApi.markAllNotificationsRead();
    if (mounted) await widget.onRead?.call();
  }

  /// What tapping a card does depends on the notice.
  ///
  /// An expiring salon can only be answered with a phone — a collaborator cannot
  /// pay for someone else's plan — so the primary action is the owner's number.
  /// A renewal has nothing to chase, so the card just acknowledges.
  Future<void> _open(CollaboratorNotification notification) async {
    _markRead(notification);

    if (!notification.canCallOwner) return;

    final palette = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Call ${notification.salonName ?? 'the owner'}?'),
        content: Text(
          'Ring ${notification.ownerPhone} to let them know '
          '${notification.salonName ?? 'their salon'} needs attention.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: palette.success),
            child: const Text('Call'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // The dialer is the deliverable. A launch failure here is a device with no
    // telephony at all, which is rare enough not to warrant an interrupt.
    await launchUrl(
      Uri(scheme: 'tel', path: notification.ownerPhone!.replaceAll(' ', '')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final unread = _notifications.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentColor,
              ),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _buildBody(palette),
    );
  }

  Widget _buildBody(AppColors palette) {
    if (_loading) return const CollaboratorLoadingState();

    if (_notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.accentColor,
        child: ListView(
          children: const [
            SizedBox(height: 90),
            CollaboratorEmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'Nothing needs you right now',
              body:
                  'When a salon you onboarded is close to its plan ending, '
                  'or the owner renews it, you will be told here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentColor,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        itemCount: _notifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _buildCard(_notifications[index], palette),
      ),
    );
  }

  Widget _buildCard(CollaboratorNotification notification, AppColors palette) {
    final expiring = notification.type == 'assigned_salon_expiring';
    final renewed = notification.type == 'assigned_salon_renewed';

    // The server says whether the plan has actually lapsed rather than leaving
    // it to be inferred from the day count, which would read a notice with no
    // day count at all as a failure that never happened.
    final lapsed = notification.lapsed;

    final (icon, tint, tintBg) = expiring
        ? (
            lapsed ? Icons.cloud_off_outlined : Icons.schedule_outlined,
            lapsed ? palette.danger : palette.warning,
            lapsed ? palette.dangerBg : palette.warningBg,
          )
        : renewed
        ? (Icons.check_circle_outline, palette.success, palette.successBg)
        : (Icons.notifications_none, palette.info, palette.infoBg);

    return CollaboratorCard(
      margin: EdgeInsets.zero,
      radius: 14,
      color: notification.isRead ? null : palette.surface,
      borderColor: notification.isRead
          ? null
          : tint.withValues(alpha: notification.important ? 0.45 : 0.22),
      onTap: () => _open(notification),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tintBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: notification.isRead
                              ? FontWeight.w600
                              : FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _dot(notification.isRead, tint),
                  ],
                ),
                if (notification.salonName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    notification.salonName!,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  notification.message,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: notification.isRead
                        ? palette.textSecondary
                        : palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _when(notification.createdAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: palette.textTertiary,
                      ),
                    ),
                    if (notification.canCallOwner) ...[
                      const SizedBox(width: 10),
                      _chip('Call owner', palette.info, palette.infoBg),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(bool isRead, Color tint) => AnimatedOpacity(
    opacity: isRead ? 0.0 : 1.0,
    duration: const Duration(milliseconds: 160),
    child: Container(
      margin: const EdgeInsets.only(top: 5),
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
    ),
  );

  Widget _chip(String label, Color colour, Color background) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: colour,
      ),
    ),
  );

  /// Relative for today, an absolute date beyond that. "2 hours ago" is what a
  /// collaborator needs when they are deciding whether to call now; "3 Sep" is
  /// what they need for anything older.
  static String _when(DateTime? at) {
    if (at == null) return '';

    final local = at.toLocal();
    final gap = DateTime.now().difference(local);

    if (gap.inMinutes < 1) return 'Just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    if (gap.inHours < 24) {
      return '${gap.inHours} hour${gap.inHours == 1 ? '' : 's'} ago';
    }

    return DateFormat('d MMM').format(local);
  }
}
