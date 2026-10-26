import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import 'reschedule_screen.dart';
import '../theme/app_colors.dart';
import '../utils/bottom_clearance.dart';
import '../widgets/skeleton.dart';
import '../widgets/notification_inbox_controls.dart';

/// The customer's message inbox. A salon-closure notice is actionable: tapping
/// it goes straight to picking a new slot.
class NotificationsScreen extends StatefulWidget {
  /// Test seam; defaults to the real service.
  final NotificationService? service;

  const NotificationsScreen({Key? key, this.service}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationService _service = widget.service ?? NotificationService();

  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String _error = '';
  NotificationPeriod _period = NotificationPeriod.all;
  bool _deleting = false;
  int _restoreTick = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.fetch(period: _period.apiValue);
      if (!mounted) return;
      setState(() {
        _notifications = data['notifications'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    await _service.markAllRead();
    _load();
  }

  void _setPeriod(NotificationPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _isLoading = true;
      _error = '';
    });
    _load();
  }

  /// Swiped away: gone at once, put back if the server refuses.
  Future<void> _deleteOne(Map<String, dynamic> notification) async {
    final index = _notifications.indexOf(notification);
    setState(() => _notifications.remove(notification));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.delete(notification['id'].toString());
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Notification deleted'), duration: Duration(seconds: 2)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // A fresh key: the swiped-away row cannot be reused once dismissed.
        _restoreTick++;
        _notifications.insert(index.clamp(0, _notifications.length), notification);
      });
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Could not delete the notification. Try again.')));
    }
  }

  Future<void> _deleteAll() async {
    if (_deleting || _notifications.isEmpty) return;
    final ok = await confirmDeleteNotifications(context, count: _notifications.length, period: _period);
    if (!ok || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deleted = await _service.deleteMany(period: _period.apiValue);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('$deleted notification${deleted == 1 ? '' : 's'} deleted')));
      await _load();
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Could not delete the notifications. Try again.')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _open(Map<String, dynamic> notification) async {
    if (notification['is_read'] != true) {
      await _service.markRead(notification['id'].toString());
    }

    final data = notification['data'] as Map<String, dynamic>?;
    final appointmentId = notification['appointment_id'];

    if (data?['action'] == 'reschedule_appointment' && appointmentId != null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RescheduleScreen(
            appointmentId: appointmentId.toString(),
            freeReschedule: data?['free_reschedule'] == true,
          ),
        ),
      );
    }

    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications', style: Theme.of(context).appBarTheme.titleTextStyle),
        centerTitle: true,
        actions: [
          if (_notifications.any((n) => n['is_read'] != true))
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.accentColor)),
            ),
          if (_notifications.isNotEmpty)
            IconButton(
              key: const ValueKey('notifications_delete_all'),
              tooltip: 'Delete notifications',
              onPressed: _deleting ? null : _deleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: NotificationPeriodChips(selected: _period, onChanged: _setPeriod),
        ),
      ),
      body: _isLoading
          ? SkeletonList(
              padding: const EdgeInsets.all(16),
              itemBuilder: (_) => const NotificationSkeleton(),
              count: 4,
            )
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: GoogleFonts.outfit(color: context.colors.danger)))
              : _notifications.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      color: AppTheme.accentColor,
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          16 + bottomClearance(context),
                        ),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final n = _notifications[index] as Map<String, dynamic>;
                          return DeletableNotification(
                            id: '${n['id']}#$_restoreTick',
                            onDelete: () => _deleteOne(n),
                            child: _buildTile(n),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 72, color: context.colors.textTertiary),
            const SizedBox(height: 12),
            Text(_period == NotificationPeriod.all ? 'Nothing to catch up on' : 'Nothing from ${_period.label.toLowerCase()}',
                style: GoogleFonts.outfit(fontSize: 16, color: context.colors.textSecondary)),
          ],
        ),
      );

  Widget _buildTile(Map<String, dynamic> notification) {
    final isRead = notification['is_read'] == true;
    final data = notification['data'] as Map<String, dynamic>?;
    final isActionable =
        data?['action'] == 'reschedule_appointment' && notification['appointment_id'] != null;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(notification),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? context.colors.surface : context.colors.accentSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead ? context.colors.border : AppTheme.accentColor.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActionable ? Icons.event_busy : Icons.notifications_outlined,
                  size: 18,
                  color: isActionable ? context.colors.warning : AppTheme.accentColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notification['title'] ?? '',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: AppTheme.accentColor, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notification['message'] ?? '',
              style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  _timeAgo(notification['created_at']),
                  style: GoogleFonts.outfit(fontSize: 11, color: context.colors.textTertiary),
                ),
                const Spacer(),
                if (isActionable)
                  Text('Pick a new time  →',
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(dynamic timestamp) {
    final parsed = DateTime.tryParse('$timestamp');
    if (parsed == null) return '';

    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return DateFormat('d MMM').format(parsed.toLocal());
  }
}
