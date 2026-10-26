import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../services/notification_service.dart';
import '../widgets/notification_inbox_controls.dart';

/// The salon owner's inbox. A superadmin warning is the message that matters
/// most here, so it is rendered as a distinct amber notice rather than a
/// plain entry — the owner should not be able to scroll past it.
///
/// An owner with several salons reads one inbox for all of them: each notice
/// carries its salon's name, and a second row of capsules narrows to one.
class NotificationsScreen extends StatefulWidget {
  /// Test seams; default to the real API.
  final Future<Map<String, dynamic>> Function({String? period, String? salonId})? fetch;
  final Future<void> Function(String id)? delete;
  final Future<int> Function({String? period, String? salonId})? deleteMany;

  const NotificationsScreen({super.key, this.fetch, this.delete, this.deleteMany});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _error = '';
  NotificationPeriod _period = NotificationPeriod.all;

  /// An owner's salons, when they have more than one; empty otherwise.
  List<NotificationSalon> _salons = const [];

  /// The salon filter; null for every salon.
  String? _salonId;
  bool _deleting = false;
  int _restoreTick = 0;

  static const List<String> _warningTypes = ['complaint_warning'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _hasUnread => _notifications.any((n) => n['is_read'] != true);

  Future<void> _load() async {
    try {
      final data = await (widget.fetch ??
          ({String? period, String? salonId}) => PartnerNotificationService.fetch(period: period, salonId: salonId))(
        period: _period.apiValue,
        salonId: _salonId,
      );
      if (!mounted) return;
      setState(() {
        _notifications = (data['notifications'] ?? [])
            .map<Map<String, dynamic>>((n) => n as Map<String, dynamic>)
            .toList();
        _salons = NotificationSalon.listFrom(data['salons']);
        // The salon filtered on is no longer the owner's: show everything.
        if (_salonId != null && !_salons.any((s) => s.id == _salonId)) _salonId = null;
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
      await PartnerNotificationService.markAllRead(salonId: _salonId);
    } catch (_) {}
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

  void _setSalon(String? salonId) {
    if (salonId == _salonId) return;
    setState(() {
      _salonId = salonId;
      _isLoading = true;
      _error = '';
    });
    _load();
  }

  String? get _selectedSalonName {
    for (final s in _salons) {
      if (s.id == _salonId) return s.name;
    }
    return null;
  }

  /// Swiped away: gone from the list at once, put back if the server refuses.
  Future<void> _deleteOne(Map<String, dynamic> notification) async {
    final index = _notifications.indexOf(notification);
    setState(() => _notifications.remove(notification));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await (widget.delete ?? PartnerNotificationService.delete)(notification['id'].toString());
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
    final ok = await confirmDeleteNotifications(
      context,
      count: _notifications.length,
      period: _period,
      salonName: _selectedSalonName,
    );
    if (!ok || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deleted = await (widget.deleteMany ??
          ({String? period, String? salonId}) => PartnerNotificationService.deleteMany(period: period, salonId: salonId))(
        period: _period.apiValue,
        salonId: _salonId,
      );
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
          if (_notifications.isNotEmpty)
            IconButton(
              key: const ValueKey('notifications_delete_all'),
              tooltip: 'Delete notifications',
              onPressed: _deleting ? null : _deleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_salons.isEmpty ? 48 : 92),
          child: Column(
            children: [
              if (_salons.isNotEmpty)
                NotificationSalonChips(salons: _salons, selected: _salonId, onChanged: _setSalon),
              NotificationPeriodChips(selected: _period, onChanged: _setPeriod),
            ],
          ),
        ),
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
                        itemBuilder: (context, index) {
                          final n = _notifications[index];
                          return DeletableNotification(
                            id: '${n['id']}#$_restoreTick',
                            onDelete: () => _deleteOne(n),
                            child: _buildTile(n, theme, isDark),
                          );
                        },
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
          Text(
              [
                _period == NotificationPeriod.all ? 'No messages yet' : 'Nothing from ${_period.label.toLowerCase()}',
                if (_selectedSalonName != null) 'for $_selectedSalonName',
              ].join(' '),
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
    // Only an owner with several salons needs telling which one; when the
    // inbox is already narrowed to one, the filter says it.
    final salonName = notification['salon_name']?.toString();
    final showSalon = _salons.isNotEmpty && _salonId == null && salonName != null && salonName.isNotEmpty;

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
            if (showSalon) ...[
              const SizedBox(height: 8),
              NotificationSalonTag(key: ValueKey('notification_salon_tag_${notification['id']}'), name: salonName),
            ],
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