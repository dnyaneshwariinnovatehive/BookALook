import 'dart:convert';
import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'dashboard_screen.dart';
import '../registration/admin_registration_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../phone_screen.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/logout_confirmation_dialog.dart';
import 'salon_switching.dart';

class SalonSelectionScreen extends StatefulWidget {
  final List<dynamic> salons;

  /// Test seam for the fresh list; defaults to the server.
  final Future<List<dynamic>?> Function()? fetchSalons;

  const SalonSelectionScreen({super.key, required this.salons, this.fetchSalons});

  @override
  State<SalonSelectionScreen> createState() => _SalonSelectionScreenState();
}

class _SalonSelectionScreenState extends State<SalonSelectionScreen> {
  late List<dynamic> _salons;

  @override
  void initState() {
    super.initState();
    _salons = List<dynamic>.from(widget.salons);
    // The list passed in may be the one saved at sign-in; a salon approved
    // since then must not still say "pending" when tapped.
    _refreshSalons();
  }

  Future<void> _refreshSalons() async {
    final fetched = await SalonSession.refresh(fetch: widget.fetchSalons);
    if (fetched != null && mounted) {
      setState(() {
        _salons = fetched;
      });
    }
  }

  void _selectSalon(BuildContext context, dynamic salon) {
    final status = salon['status']?.toString();

    if (status == 'needs_correction') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_outlined, color: AppTheme.accentColor),
              SizedBox(width: 8),
              Text('Corrections Requested', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SuperAdmin requested corrections before approving your salon:'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lightWarning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.lightWarning.withOpacity(0.3)),
                ),
                child: Text(
                  salon['correction_notes']?.toString().isNotEmpty == true
                      ? salon['correction_notes'].toString()
                      : 'Please review your uploaded photos, address, and commercial preferences.',
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Tap "Edit & Resubmit" to update your application without losing your information.',
                  style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.lightTextBody)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _editAndResubmitSalon(context, salon);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Edit & Resubmit'),
            ),
          ],
        ),
      );
      return;
    }

    if (status == 'rejected') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Application Rejected', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            salon['rejection_reason']?.toString().isNotEmpty == true
                ? 'Reason: ${salon['rejection_reason']}'
                : 'This salon application was rejected. Please contact support.',
            style: const TextStyle(color: AppTheme.lightTextBody, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    if (status == 'pending_approval') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Approval Pending',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'This salon is pending for approval. Contact on +91 9876543210 for more info.',
            style: TextStyle(color: AppTheme.lightTextBody, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: AppTheme.accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (status == 'deactivated') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('salon_deactivated_dialog'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Salon Deactivated', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            '${salon['name'] ?? 'This salon'} was deactivated and is no longer shown to customers. '
            'Contact BookALook support if you want to reopen it.',
            style: const TextStyle(color: AppTheme.lightTextBody, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // DashboardScreen remembers this salon, so the next launch opens it.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardScreen(salonData: salon),
      ),
      (route) => false,
    );
  }

  void _editAndResubmitSalon(BuildContext context, dynamic salon) async {
    final prefs = await SharedPreferences.getInstance();
    final authStateStr = prefs.getString('auth_state');
    String? phone;
    String? ownerName;
    String? email;

    if (authStateStr != null) {
      try {
        final authState = jsonDecode(authStateStr);
        final user = authState['user'];
        if (user != null) {
          phone = user['phone'];
          ownerName = user['name'];
          email = user['email'];
        }
      } catch (_) {}
    }

    final initialData = <String, dynamic>{
      'salon_id': salon['id']?.toString(),
      'salon_name': salon['name'],
      'description': salon['description'],
      'street_address': salon['address'],
      'city_id': salon['city_id']?.toString() ?? (salon['city'] is Map ? salon['city']['id']?.toString() : null),
      'sub_area_id': salon['sub_area_id']?.toString(),
      'pincode': salon['pincode'],
      'gender_focus': salon['gender_focus'],
      'preferred_plan_id': salon['preferred_plan_id']?.toString(),
      'preferred_commercial_model': salon['preferred_commercial_model'],
      'requested_commission_percentage': salon['requested_commission_percentage'],
      'cover_photo_url': salon['cover_photo_url'],
      'owner_name': salon['admin']?['name'] ?? ownerName,
      'email': salon['admin']?['email'] ?? email,
    };

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdminRegistrationScreen(
            phone: phone,
            initialData: initialData,
            isExistingAdmin: true,
          ),
        ),
      );
    }
  }

  /// Safely reads a salon's city, handling both the current nested `city`
  /// relation object (`{"id": ..., "name": "Mumbai"}`) and a legacy flat string.
  String _cityName(dynamic salon) {
    final city = salon['city'];
    if (city is Map) {
      final name = city['name'];
      if (name != null && name.toString().isNotEmpty) return name.toString();
    }
    final flat = city?.toString() ?? '';
    return flat.isNotEmpty ? flat : 'Unknown location';
  }

  void _addNewSalon(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final authStateStr = prefs.getString('auth_state');
    Map<String, dynamic>? userData;
    String? phone;

    if (authStateStr != null) {
      final authState = jsonDecode(authStateStr);
      final user = authState['user'];
      if (user != null) {
        phone = user['phone'];
        userData = {'owner_name': user['name'], 'email': user['email']};
      }
    }

    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdminRegistrationScreen(
            phone: phone,
            initialData: userData,
            isExistingAdmin: true,
          ),
        ),
      );
      if (mounted) {
        _refreshSalons();
      }
    }
  }

  void _logout(BuildContext context) async {
    final confirmed = await LogoutConfirmationDialog.show(
      context,
      secondaryNote: 'Your bookings and salon data stay saved to your account.',
    );
    if (confirmed != true) return;

    await PushNotificationService().unregisterDevice();
    final prefs = await SharedPreferences.getInstance();
    final welcomeKeys = prefs.getKeys().where((k) => k.startsWith('welcome_shown_')).toList();
    final welcomeBackup = {for (final k in welcomeKeys) k: prefs.getBool(k)};
    await prefs.clear();
    for (final entry in welcomeBackup.entries) {
      if (entry.value != null) {
        await prefs.setBool(entry.key, entry.value!);
      }
    }
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PhoneScreen()),
        (route) => false,
      );
    }
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      key: ValueKey('salon_badge_$label'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Text(
          'bookalook',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            fontFamily: 'InstagramLogo',
          ),
        ), // Fallback to standard bold if font not found
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () => _logout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Text(
                'Switch Account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshSalons,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _salons.length + 1, // +1 for "Add new salon"
                  itemBuilder: (context, index) {
                    if (index < _salons.length) {
                      final salon = _salons[index];
                    final status = salon['status']?.toString();
                    final isPending = status == 'pending_approval';
                    final isNeedsCorrection = status == 'needs_correction';
                    final isRejected = status == 'rejected';
                    final isDeactivated = status == 'deactivated';
                    final isSuspended = status == 'suspended';

                    return InkWell(
                      onTap: () => _selectSalon(context, salon),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: AppTheme.lightBorder,
                              backgroundImage: salon['cover_photo_url'] != null
                                  ? NetworkImage(salon['cover_photo_url'])
                                  : null,
                              child: salon['cover_photo_url'] == null
                                  ? Text(
                                      salon['name']
                                              ?.substring(0, 1)
                                              .toUpperCase() ??
                                          'S',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.lightTextHeading,
                                        fontSize: 24,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    salon['name'] ?? 'Unnamed Salon',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        _cityName(salon),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                      if (isPending) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (Theme.of(context).brightness ==
                                                            Brightness.dark
                                                        ? AppTheme.darkWarning
                                                        : AppTheme.lightWarning)
                                                    .withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Pending',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  (Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? AppTheme.darkWarning
                                                  : AppTheme.lightWarning),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (isNeedsCorrection) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentColor.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Needs Correction',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.accentColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (isRejected) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (Theme.of(context).brightness ==
                                                            Brightness.dark
                                                        ? AppTheme.darkDanger
                                                        : AppTheme.lightDanger)
                                                    .withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Rejected',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  (Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? AppTheme.darkDanger
                                                  : AppTheme.lightDanger),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (isSuspended) ...[
                                        const SizedBox(width: 8),
                                        _statusBadge(
                                          'Suspended',
                                          Theme.of(context).brightness == Brightness.dark
                                              ? AppTheme.darkDanger
                                              : AppTheme.lightDanger,
                                        ),
                                      ],
                                      if (isDeactivated) ...[
                                        const SizedBox(width: 8),
                                        _statusBadge('Deactivated', Colors.grey.shade600),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.radio_button_unchecked,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    // Add new salon button
                    return InkWell(
                      onTap: () => _addNewSalon(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.transparent,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.add,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Add new salon',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}
