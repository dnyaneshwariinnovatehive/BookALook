import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import 'reschedule_screen.dart';

/// The customer's message inbox. A salon-closure notice is actionable: tapping
/// it goes straight to picking a new slot.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService();

  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.fetch();
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
        title: Text('Notifications', style: AppTheme.lightTheme.appBarTheme.titleTextStyle),
        centerTitle: true,
        actions: [
          if (_notifications.any((n) => n['is_read'] != true))
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.accentColor)),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: GoogleFonts.outfit(color: AppTheme.lightDanger)))
              : _notifications.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      color: AppTheme.accentColor,
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _buildTile(_notifications[index] as Map<String, dynamic>),
                      ),
                    ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 72, color: AppTheme.lightTextLight),
            const SizedBox(height: 12),
            Text('Nothing to catch up on',
                style: GoogleFonts.outfit(fontSize: 16, color: AppTheme.lightTextBody)),
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
          color: isRead ? AppTheme.lightSurface : AppTheme.lightAccentSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead ? AppTheme.lightBorder : AppTheme.accentColor.withOpacity(0.4),
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
                  color: isActionable ? AppTheme.lightWarning : AppTheme.accentColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notification['title'] ?? '',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                      color: AppTheme.lightTextHeading,
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
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  _timeAgo(notification['created_at']),
                  style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextLight),
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
