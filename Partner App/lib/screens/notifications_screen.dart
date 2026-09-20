import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../services/notification_service.dart';

/// The salon owner's inbox. A superadmin warning is the message that matters
/// most here, so it is rendered as a distinct amber notice rather than a
/// plain entry — the owner should not be able to scroll past it.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _error = '';

  static const List<String> _warningTypes = ['complaint_warning'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _hasUnread => _notifications.any((n) => n['is_read'] != true);

  Future<void> _load() async {
    try {
      final data = await PartnerNotificationService.fetch();
      if (!mounted) return;
      setState(() {
        _notifications = (data['notifications'] ?? [])
            .map<Map<String, dynamic>>((n) => n as Map<String, dynamic>)
            .toList();
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
    try {
      await PartnerNotificationService.markAllRead();
    } catch (_) {}
    _load();
  }

  Future<void> _open(Map<String, dynamic> notification) async {
    if (notification['is_read'] != true) {
      try {
        await PartnerNotificationService.markRead(notification['id'].toString());
      } catch (_) {}
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (_hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentColor)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _error.isNotEmpty
              ? Center(
                  child: Text(_error,
                      style: TextStyle(
                          color: isDark ? AppTheme.darkDanger : AppTheme.lightDanger)),
                )
              : _notifications.isEmpty
                  ? _buildEmpty(theme)
                  : RefreshIndicator(
                      color: AppTheme.accentColor,
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _buildTile(_notifications[index], theme, isDark),
                      ),
                    ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none,
              size: 72,
              color: theme.brightness == Brightness.dark
                  ? AppTheme.darkTextLight
                  : AppTheme.lightTextLight),
          const SizedBox(height: 12),
          Text('No messages yet',
              style: TextStyle(
                  fontSize: 16,
                  color: theme.brightness == Brightness.dark
                      ? AppTheme.darkTextBody
                      : AppTheme.lightTextBody)),
        ],
      ),
    );
  }

  Widget _buildTile(
      Map<String, dynamic> notification, ThemeData theme, bool isDark) {
    final isRead = notification['is_read'] == true;
    final type = notification['type']?.toString() ?? '';
    final isWarning = _warningTypes.contains(type);
    final accent = isDark ? AppTheme.darkWarning : AppTheme.lightWarning;
    final accentBg = isDark ? AppTheme.darkWarningBg : AppTheme.lightWarningBg;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(notification),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isWarning
              ? accentBg
              : isRead
                  ? theme.colorScheme.surface
                  : (isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isWarning
                ? accent.withValues(alpha: 0.4)
                : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isWarning ? Icons.warning_amber_rounded : Icons.notifications_outlined,
                  size: 18,
                  color: isWarning ? accent : AppTheme.accentColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notification['title'] ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: isWarning ? accent : AppTheme.accentColor,
                        shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notification['message'] ?? '',
              style: TextStyle(
                  fontSize: 13,
                  color: theme.brightness == Brightness.dark
                      ? AppTheme.darkTextBody
                      : AppTheme.lightTextBody,
                  height: 1.4),
            ),
            const SizedBox(height: 10),
            Text(
              _timeAgo(notification['created_at']),
              style: TextStyle(
                  fontSize: 11,
                  color: theme.brightness == Brightness.dark
                      ? AppTheme.darkTextLight
                      : AppTheme.lightTextLight),
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