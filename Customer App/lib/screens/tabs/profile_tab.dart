import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../../legal/legal_document_screen.dart';
import '../../legal/legal_documents.dart';
import '../../services/auth_service.dart';
import '../../services/http_client.dart' show loginRouteName;
import '../../services/profile_service.dart';
import '../phone_screen.dart';
import 'favourites_tab.dart';
import '../../widgets/logout_confirmation_dialog.dart';
import '../../utils/app_haptics.dart';
import '../../theme/app_colors.dart';
import '../../utils/bottom_clearance.dart';
import '../../main.dart'; // To access themeNotifier
import '../edit_profile_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/appointment_service.dart';
import '../../widgets/complaint_bottom_sheet.dart';

class ProfileTab extends StatefulWidget {
  final bool isGuest;

  const ProfileTab({super.key, required this.isGuest});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final ProfileService _profileService = ProfileService();

  /// The documents a customer can reach from the profile. Partner Terms is
  /// deliberately absent — it governs salon partners, who use the Partner App,
  /// and showing it to a customer invites them to agree to the wrong contract.
  /// Insertion order is the reading order: what you agreed to, what happens to
  /// your money, then who we are.
  static const Map<String, IconData> _legalDocuments = {
    'terms': Icons.description_outlined,
    'cancellation-refund': Icons.event_busy_outlined,
    'privacy': Icons.lock_outline,
    'about': Icons.info_outline,
  };

  Map<String, dynamic>? _userProfile;
  int _appointmentsCount = 0;
  int _favSalonsCount = 0;
  bool _isLoading = true;
  String _error = '';

  // Settings states
  bool _pushNotifications = true;
  bool _locationAccess = true;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadProfileData();
      _loadSettings();
    }
  }

  Future<void> _loadProfileData() async {
    try {
      final data = await _profileService.getProfile();
      if (mounted) {
        setState(() {
          _userProfile = data['user'];
          _appointmentsCount = data['appointments_count'] ?? 0;
          _favSalonsCount = data['fav_salons_count'] ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load profile details.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _locationAccess = prefs.getBool('location_access') ?? true;
      });
    }

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    bool osEnabled =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    bool apiEnabled = true;

    // Load Push notification preference from backend if not guest
    if (!widget.isGuest) {
      try {
        final prefsData = await _profileService.getNotificationPreferences();
        apiEnabled = prefsData['push_enabled'] ?? true;
      } catch (e) {
        debugPrint('Error loading notification preferences: $e');
      }
    } else {
      apiEnabled = prefs.getBool('push_notifications') ?? true;
    }

    if (mounted) {
      setState(() {
        _pushNotifications = osEnabled && apiEnabled;
      });
    }
  }

  Future<void> _toggleSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Signing out ends the session and clears the token on this device, so the
  /// account being signed out of is named before it happens.
  Future<void> _logout(BuildContext context) async {
    Map<String, dynamic>? profile = _userProfile;
    if (profile == null && !widget.isGuest) {
      try {
        final data = await _profileService.getProfile();
        profile = data['user'] as Map<String, dynamic>?;
      } catch (_) {}
    }

    if (!context.mounted) return;

    final name = (profile?['name'] ?? '').toString().trim();
    final phone = (profile?['phone'] ?? '').toString().trim();

    final confirmed = await LogoutConfirmationDialog.show(
      context,
      name: name.isNotEmpty ? name : null,
      phone: phone.isNotEmpty ? phone : null,
    );

    if (confirmed != true) return;

    final authService = AuthService();
    await authService.logout();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: loginRouteName),
        builder: (context) => const PhoneScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final textHeading = context.colors.textPrimary;
    final textBody = context.colors.textSecondary;
    final danger = context.colors.danger;
    final surface = context.colors.surface;

    AppHaptics.lightImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: surface,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        title: Text(
          'Delete Account?',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: danger,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action is permanent and cannot be undone.',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textHeading,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'You will be logged out and your profile will be removed. However, past transaction records (appointments and payments) will be securely retained for financial compliance.',
              style: GoogleFonts.outfit(fontSize: 14, color: textBody),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(dialogContext, false);
            },
            child: Text('Cancel', style: GoogleFonts.outfit(color: textBody)),
          ),
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(dialogContext, true);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.outfit(
                color: danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final authService = AuthService();
    final success = await authService.deleteAccount();

    if (!context.mounted) return;

    if (success) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: loginRouteName),
          builder: (context) => const PhoneScreen(),
        ),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account. Please try again.')),
      );
    }
  }

  /// Favourites is a page pushed inside the profile tab, so the footer stays put
  /// and the tab's own back gesture still works. The count is refreshed on the
  /// way back, because un-favouriting on that page changes it.
  Future<void> _openFavourites() async {
    AppHaptics.lightImpact();

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FavouritesTab(isGuest: false)),
    );

    if (!mounted) return;
    _loadProfileData();
  }

  Future<void> _onTogglePushNotifications(bool val) async {
    if (val) {
      NotificationSettings settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied ||
          settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await FirebaseMessaging.instance.requestPermission();
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Notifications Disabled'),
              content: const Text(
                'Please enable notifications for BookALook in your device settings to receive updates.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() => _pushNotifications = val);
    if (!widget.isGuest) {
      try {
        await _profileService.updateNotificationPreferences({
          'push_enabled': val,
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _pushNotifications = !val);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    } else {
      _toggleSetting('push_notifications', val);
    }
  }

  String _formatJoinDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return 'Member';
    try {
      final date = DateTime.parse(dateStr);
      return 'Member Since ${DateFormat('MMM yyyy').format(date)}';
    } catch (e) {
      return 'Member';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) {
      return GuestRestrictedView(
        title: 'Sign In Required',
        message: 'Please sign in to access your profile settings and history.',
        // Favourites left the footer, so Profile is the last tab.
        tabIndex: 3,
        icon: Icons.person_outline,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerColor = context.colors.danger;
    final headingColor = context.colors.textPrimary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final bgColor = context.colors.pageTint;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accentColor),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error, style: TextStyle(color: dangerColor)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = '';
                  });
                  _loadProfileData();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final userName = (_userProfile?['name'] ?? 'Guest').toString();
    final joinDate = _formatJoinDate(_userProfile?['created_at']);
    final avatarUrl =
        (_userProfile?['profile_photo'] ?? _userProfile?['avatar'])?.toString();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20.0,
            16.0,
            20.0,
            bottomClearance(context, gap: 32),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Page Title: My Profile
              Text(
                'My Profile',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: headingColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),

              // Profile Header: Avatar, Name, Edit Icon, Join Date
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accentColor,
                        width: 2.2,
                      ),
                    ),
                    padding: const EdgeInsets.all(3.5),
                    child: CircleAvatar(
                      backgroundColor: context.colors.accentSoft,
                      backgroundImage:
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: (avatarUrl == null || avatarUrl.isEmpty)
                          ? Icon(
                              Icons.person,
                              size: 38,
                              color: AppTheme.accentColor,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                userName,
                                style: GoogleFonts.outfit(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  color: headingColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  if (_userProfile == null) return;
                                  AppHaptics.lightImpact();
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditProfileScreen(
                                        user: _userProfile!,
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    _loadProfileData();
                                  }
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 19,
                                    color: AppTheme.accentColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          joinDate,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Statistics Cards: Appointments & Fav Salons
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      count: _appointmentsCount.toString(),
                      label: 'Appointments',
                      surfaceColor: surfaceColor,
                      borderColor: borderColor,
                      headingColor: headingColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      count: _favSalonsCount.toString(),
                      label: 'Fav Salons',
                      surfaceColor: surfaceColor,
                      borderColor: borderColor,
                      headingColor: headingColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // My Favourites Full-Width Row
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.15)
                          : const Color(0xFF6B46C1).withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openFavourites,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Icon(
                              Icons.favorite_border_rounded,
                              size: 22,
                              color: AppTheme.accentColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'My Favourites',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: headingColor,
                              ),
                            ),
                          ),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 24,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.colors.accentSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$_favSalonsCount',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: context.colors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ACCOUNT SETTINGS Header
              _buildSectionHeader(context, 'ACCOUNT SETTINGS'),
              const SizedBox(height: 8),

              // Account Settings Card Container
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.15)
                          : const Color(0xFF6B46C1).withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    children: [
                      _buildToggleRow(
                        context,
                        icon: Icons.dark_mode_outlined,
                        label: 'Dark Mode',
                        value: isDark,
                        onChanged: (val) {
                          themeNotifier.value = val
                              ? ThemeMode.dark
                              : ThemeMode.light;
                        },
                      ),
                      Divider(height: 1, thickness: 1, color: borderColor),
                      _buildToggleRow(
                        context,
                        icon: Icons.notifications_none_rounded,
                        label: 'Push Notifications',
                        value: _pushNotifications,
                        onChanged: _onTogglePushNotifications,
                      ),
                      Divider(height: 1, thickness: 1, color: borderColor),
                      _buildToggleRow(
                        context,
                        icon: Icons.location_on_outlined,
                        label: 'Location Access',
                        value: _locationAccess,
                        onChanged: (val) {
                          setState(() => _locationAccess = val);
                          _toggleSetting('location_access', val);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // HELP & LEGAL Header
              _buildSectionHeader(context, 'HELP & LEGAL'),
              const SizedBox(height: 8),

              // Help & Legal Card Container
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.15)
                          : const Color(0xFF6B46C1).withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    children: [
                      _buildNavActionRow(
                        context,
                        icon: Icons.report_problem_outlined,
                        label: 'Report a Problem / Complaints',
                        onTap: () {
                          AppHaptics.lightImpact();
                          _showComplaintOrHelpOptions();
                        },
                      ),
                      Divider(height: 1, thickness: 1, color: borderColor),
                      for (int i = 0; i < _legalDocuments.length; i++) ...[
                        () {
                          final entry = _legalDocuments.entries.elementAt(i);
                          final doc = legalDocumentBySlug(entry.key);
                          final title = doc?.title ?? entry.key;
                          return _buildNavActionRow(
                            context,
                            icon: entry.value,
                            label: title,
                            onTap: () {
                              AppHaptics.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      LegalDocumentScreen(slug: entry.key),
                                ),
                              );
                            },
                          );
                        }(),
                        if (i < _legalDocuments.length - 1)
                          Divider(height: 1, thickness: 1, color: borderColor),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Legal contact info
              Center(
                child: Text(
                  'BooKalook · $kLegalContactEmail',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Logout Button
              Center(
                child: TextButton.icon(
                  onPressed: () => _logout(context),
                  icon: Icon(
                    Icons.logout_rounded,
                    color: dangerColor,
                    size: 18,
                  ),
                  label: Text(
                    'Log Out',
                    style: GoogleFonts.outfit(
                      color: dangerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    backgroundColor: context.colors.dangerSoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Delete Account
              Center(
                child: TextButton(
                  onPressed: () => _deleteAccount(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    'Delete Account',
                    style: GoogleFonts.outfit(
                      color: context.colors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: context.colors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String count,
    required String label,
    required Color surfaceColor,
    required Color borderColor,
    required Color headingColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : const Color(0xFF6B46C1).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            count,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: headingColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Icon(icon, size: 22, color: AppTheme.accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Container(
            width: 52,
            alignment: Alignment.centerRight,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeThumbColor: Colors.white,
              activeTrackColor: AppTheme.accentColor,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: isDark
                  ? const Color(0xFF4A4458)
                  : const Color(0xFFE2DEEC),
              trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavActionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Icon(icon, size: 22, color: AppTheme.accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              Container(
                width: 52,
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showComplaintOrHelpOptions() async {
    if (widget.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to report a problem or file a complaint.'),
        ),
      );
      return;
    }

    final surfaceColor = context.colors.surface;
    final textPrimary = context.colors.textPrimary;
    final textSecondary = context.colors.textSecondary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => Container(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          bottomClearance(bottomSheetContext, gap: 20),
        ),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Help & Complaints',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Have an issue with a visit or need assistance? We are here to help.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppTheme.accentColor,
                  size: 22,
                ),
              ),
              title: Text(
                'Report an issue with an appointment',
                style: GoogleFonts.outfit(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              subtitle: Text(
                'File a complaint or report a problem with a salon visit',
                style: GoogleFonts.outfit(fontSize: 12, color: textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _pickAppointmentForComplaint();
              },
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.mail_outline_rounded,
                  color: Color(0xFF2E7D32),
                  size: 22,
                ),
              ),
              title: Text(
                'Contact Customer Support',
                style: GoogleFonts.outfit(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              subtitle: Text(
                'Email $kLegalContactEmail',
                style: GoogleFonts.outfit(fontSize: 12, color: textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () async {
                Navigator.pop(bottomSheetContext);
                final uri = Uri.parse('mailto:$kLegalContactEmail?subject=Customer%20Support%20Inquiry');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAppointmentForComplaint() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<dynamic> pastBookings = [];
    try {
      final res = await AppointmentService().getMyBookings();
      pastBookings = res['past'] ?? [];
    } catch (_) {
      // Ignored
    } finally {
      if (mounted) Navigator.pop(context); // close loader
    }

    if (!mounted) return;

    if (pastBookings.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'No Past Appointments',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Text(
            'You do not have any past appointments to report an issue for yet.',
            style: GoogleFonts.outfit(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomClearance(ctx, gap: 16)),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Appointment',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the visit you would like to report an issue with:',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: pastBookings.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (itemCtx, index) {
                  final b = pastBookings[index];
                  final salonName = b['salon']?['name'] ?? 'Salon';
                  final date = b['appointment_date']?.toString() ?? '';
                  final time = b['start_time']?.toString() ?? '';
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    title: Text(
                      salonName,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    subtitle: Text(
                      '$date at $time',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      Navigator.pop(ctx);
                      ComplaintBottomSheet.show(context, b);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
