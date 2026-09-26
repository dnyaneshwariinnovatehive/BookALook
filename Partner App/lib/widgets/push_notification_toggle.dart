import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class PushNotificationToggle extends StatefulWidget {
  const PushNotificationToggle({super.key});

  @override
  State<PushNotificationToggle> createState() => _PushNotificationToggleState();
}

class _PushNotificationToggleState extends State<PushNotificationToggle> {
  bool _pushEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await PartnerNotificationService.getPreferences();
      if (mounted) {
        setState(() {
          _pushEnabled = prefs['push_enabled'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePush(bool value) async {
    setState(() => _pushEnabled = value);
    try {
      final success = await PartnerNotificationService.updatePreferences({
        'push_enabled': value,
      });
      if (!success && mounted) {
        // Revert on failure
        setState(() => _pushEnabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pushEnabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ListTile(
        title: Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        trailing: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      );
    }
    
    return SwitchListTile(
      value: _pushEnabled,
      onChanged: _togglePush,
      secondary: Icon(
        _pushEnabled ? Icons.notifications_active : Icons.notifications_off,
        color: _pushEnabled ? Colors.green : Colors.grey,
      ),
      title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
