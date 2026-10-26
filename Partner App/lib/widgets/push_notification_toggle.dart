import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../services/push_toggle_controller.dart';
import '../theme/app_theme.dart';

/// The Push Notifications switch for every Partner login — owner, staff and
/// collaborator. On only when the account wants pushes and the phone allows
/// them; see [PushToggleController] for how each side is handled.
class PushNotificationToggle extends StatefulWidget {
  final EdgeInsetsGeometry contentPadding;
  final bool compact;

  /// Test seam; defaults to the real API, phone permission and settings.
  final PushToggleController Function()? controllerFactory;

  const PushNotificationToggle({
    super.key,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.compact = false,
    this.controllerFactory,
  });

  @override
  State<PushNotificationToggle> createState() => _PushNotificationToggleState();
}

class _PushNotificationToggleState extends State<PushNotificationToggle> {
  late final PushToggleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controllerFactory?.call() ??
        PushToggleController(
          // The server answers {"preferences": {...}}. Reading push_enabled off
          // the top level found nothing, so the switch always showed off.
          loadServer: () async {
            final body = await PartnerNotificationService.getPreferences();
            final prefs = body['preferences'];
            return prefs is Map ? prefs['push_enabled'] != false : true;
          },
          saveServer: (enabled) async {
            final ok = await PartnerNotificationService.updatePreferences({'push_enabled': enabled});
            if (!ok) throw Exception('not saved');
          },
          registerDevice: () => PushNotificationService().registerDevice(),
        );
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle(bool value) async {
    final error = await _controller.setEnabled(
      value,
      askToOpenSettings: () => showOpenNotificationSettingsDialog(context),
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(milliseconds: 2500), content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;

        if (widget.compact) {
          if (c.loading) {
            return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
          }
          return Switch.adaptive(
            key: const ValueKey('push_toggle_switch'),
            value: c.enabled,
            activeTrackColor: AppTheme.accentColor,
            onChanged: c.saving ? null : _toggle,
          );
        }

        if (c.loading) {
          return ListTile(
            leading: const Icon(Icons.notifications_none, color: Colors.grey, size: 26),
            title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.normal, fontSize: 16)),
            trailing: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            contentPadding: widget.contentPadding,
          );
        }

        return SwitchListTile(
          key: const ValueKey('push_toggle_switch'),
          value: c.enabled,
          onChanged: c.saving ? null : _toggle,
          secondary: Icon(
            c.enabled ? Icons.notifications_active : Icons.notifications_off,
            color: c.enabled ? Colors.green : (c.blockedByPhone ? Colors.orange : Colors.grey),
            size: 26,
          ),
          title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.normal, fontSize: 16)),
          subtitle: Text(
            c.blockedByPhone ? 'Blocked in phone settings — turn on to fix' : c.statusText,
            key: const ValueKey('push_toggle_status'),
            style: TextStyle(fontSize: 12, color: c.blockedByPhone ? Colors.orange.shade800 : Colors.grey.shade600),
          ),
          contentPadding: widget.contentPadding,
        );
      },
    );
  }
}
