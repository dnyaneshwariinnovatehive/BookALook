import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
      // In real-world apps, the toggle should also reflect the OS permission status.
      // If OS permission is denied, the toggle should be off regardless of API preferences.
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      bool osEnabled = settings.authorizationStatus == AuthorizationStatus.authorized || 
                       settings.authorizationStatus == AuthorizationStatus.provisional;
                       
      bool apiEnabled = prefs['push_enabled'] ?? false;
      
      bool actualEnabled = osEnabled && apiEnabled;

      if (mounted) {
        setState(() {
          _pushEnabled = actualEnabled;
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
    if (value) {
      // Trying to turn ON
      NotificationSettings settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied || 
          settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        
        settings = await FirebaseMessaging.instance.requestPermission();
        
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          
          if (!mounted) return;
          // User denied or permanently denied. Show dialog.
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Notifications Disabled'),
              content: const Text('Please enable notifications for BookALook in your device settings to receive updates.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return; // Don't toggle or update backend
        }
      }
    }

    setState(() => _pushEnabled = value);
    try {
      final success = await PartnerNotificationService.updatePreferences({
        'push_enabled': value,
      });
      if (!success && mounted) {
        // Revert on failure
        setState(() => _pushEnabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Failed to update preferences')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pushEnabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Error: $e')),
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
