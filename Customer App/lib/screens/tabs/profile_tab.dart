import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../../legal/legal_document_screen.dart';
import '../../legal/legal_documents.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../phone_screen.dart';
import 'favourites_tab.dart';
import '../../utils/app_haptics.dart';
import '../../main.dart'; // To access themeNotifier

class ProfileTab extends StatefulWidget {
  final bool isGuest;

  const ProfileTab({Key? key, required this.isGuest}) : super(key: key);

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
    'terms': Icons.gavel_outlined,
    'privacy': Icons.lock_outline,
    'cancellation-refund': Icons.event_busy_outlined,
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

    // Load Push notification preference from backend if not guest
    if (!widget.isGuest) {
      try {
        final prefsData = await _profileService.getNotificationPreferences();
        if (mounted) {
          setState(() {
            _pushNotifications = prefsData['push_enabled'] ?? true;
          });
        }
      } catch (e) {
        debugPrint('Error loading notification preferences: $e');
      }
    } else {
      if (mounted) {
        setState(() {
          _pushNotifications = prefs.getBool('push_notifications') ?? true;
        });
      }
    }
  }

  Future<void> _toggleSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Signing out ends the session and clears the token on this device, so the
  /// account being signed out of is named before it happens.
  Future<void> _logout(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textHeading = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final textBody = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final textLight = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;
    final danger = isDark ? AppTheme.darkDanger : AppTheme.lightDanger;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;

    final name = (_userProfile?['name'] ?? '').toString().trim();
    final phone = (_userProfile?['phone'] ?? '').toString().trim();
    final email = (_userProfile?['email'] ?? '').toString().trim();
    final contact = phone.isNotEmpty ? phone : (email.isNotEmpty ? email : '');

    AppHaptics.lightImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: surface,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        title: Text(
          'Log out of BookALook?',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: textHeading,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Text(
                name,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textHeading,
                ),
              ),
            if (contact.isNotEmpty) ...[
              if (name.isNotEmpty) const SizedBox(height: 2),
              Text(
                contact,
                style: GoogleFonts.outfit(fontSize: 14, color: textBody),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              contact.isNotEmpty
                  ? 'You will need to sign in again with $contact to reach your bookings, wallet and profile on this device.'
                  : 'You will need to sign in again to reach your bookings, wallet and profile on this device.',
              style: GoogleFonts.outfit(fontSize: 14, color: textBody),
            ),
            const SizedBox(height: 12),
            Text(
              'Your bookings and cart stay saved to your account.',
              style: GoogleFonts.outfit(fontSize: 12, color: textLight),
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
            child: Text(
              'Stay signed in',
              style: GoogleFonts.outfit(color: textBody),
            ),
          ),
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(dialogContext, true);
            },
            child: Text(
              'Log out',
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
    await authService.logout();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => PhoneScreen()),
      (route) => false,
    );
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

  String _formatJoinDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return 'Member Since ${DateFormat('MMM yyyy').format(date)}';
    } catch (e) {
      return '';
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
    final dangerColor = isDark ? AppTheme.darkDanger : AppTheme.lightDanger;
    final headingColor = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final bgColor = isDark ? AppTheme.darkBg : const Color(0xFFFBF9FF);

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

    final userName = _userProfile?['name'] ?? 'Guest';
    final joinDate = _formatJoinDate(_userProfile?['created_at']);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 140.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Profile Header
              Text(
                'My Profile',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: headingColor,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppTheme.accentColor, Colors.purpleAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: CircleAvatar(
                        backgroundColor: surfaceColor,
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: headingColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          joinDate,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.lightTextLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Stats Grid
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      _appointmentsCount.toString(),
                      'Appointments',
                      surfaceColor,
                      borderColor,
                      headingColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      _favSalonsCount.toString(),
                      'Fav Salons',
                      surfaceColor,
                      borderColor,
                      headingColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Favourites lives here rather than in the footer, where it took a
              // slot that the four core destinations use better.
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _buildNavRow(
                  context,
                  icon: Icons.favorite_outline,
                  label: 'My Favourites',
                  trailing: _favSalonsCount > 0 ? '${_favSalonsCount}' : null,
                  headingColor: headingColor,
                  onTap: _openFavourites,
                ),
              ),

              const SizedBox(height: 40),

              // Settings Header
              Text(
                'ACCOUNT SETTINGS',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: isDark
                      ? AppTheme.darkTextLight
                      : AppTheme.lightTextLight,
                ),
              ),
              const SizedBox(height: 16),

              // Settings Card
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
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
                      headingColor: headingColor,
                    ),
                    Divider(height: 1, color: borderColor),
                    _buildToggleRow(
                      context,
                      icon: Icons.notifications_outlined,
                      label: 'Push Notifications',
                      value: _pushNotifications,
                      onChanged: (val) {
                        setState(() => _pushNotifications = val);
                        if (!widget.isGuest) {
                          _profileService.updateNotificationPreferences({
                            'push_enabled': val,
                          });
                        } else {
                          _toggleSetting('push_notifications', val);
                        }
                      },
                      headingColor: headingColor,
                    ),
                    Divider(height: 1, color: borderColor),
                    _buildToggleRow(
                      context,
                      icon: Icons.location_on_outlined,
                      label: 'Location Access',
                      value: _locationAccess,
                      onChanged: (val) {
                        setState(() => _locationAccess = val);
                        _toggleSetting('location_access', val);
                      },
                      headingColor: headingColor,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Legal Header
              Text(
                'HELP & LEGAL',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: isDark
                      ? AppTheme.darkTextLight
                      : AppTheme.lightTextLight,
                ),
              ),
              const SizedBox(height: 16),

              // Always reachable, signed in or not. A guest reading the
              // cancellation policy before their first booking is exactly the
              // person most likely to need it.
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (final entry in _legalDocuments.entries) ...[
                      LegalDocumentTile(slug: entry.key, icon: entry.value),
                      if (entry.key != _legalDocuments.keys.last)
                        Divider(height: 1, color: borderColor),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Center(
                child: Text(
                  'BooKalook · ${kLegalContactEmail}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isDark
                        ? AppTheme.darkTextLight
                        : AppTheme.lightTextLight,
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Logout Button
              Center(
                child: TextButton.icon(
                  onPressed: () => _logout(context),
                  icon: Icon(Icons.logout, color: dangerColor, size: 20),
                  label: Text(
                    'Log Out',
                    style: GoogleFonts.outfit(
                      color: dangerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    backgroundColor: isDark
                        ? AppTheme.darkDangerBg
                        : const Color(0xFFFEE8EA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String count,
    String label,
    Color surfaceColor,
    Color borderColor,
    Color headingColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            count,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: headingColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkTextLight
                  : AppTheme.lightTextLight,
            ),
          ),
        ],
      ),
    );
  }

  /// A tappable destination, matching the account-settings rows so the profile
  /// reads as one list rather than two different card styles.
  Widget _buildNavRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color headingColor,
    required VoidCallback onTap,
    String? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: headingColor.withOpacity(0.7)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: headingColor,
                ),
              ),
            ),
            if (trailing != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkAccentSoft
                      : AppTheme.lightAccentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trailing,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentColor,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: headingColor.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color headingColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: headingColor.withOpacity(0.7)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: headingColor,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.accentColor,
            activeTrackColor: AppTheme.accentColor.withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}
