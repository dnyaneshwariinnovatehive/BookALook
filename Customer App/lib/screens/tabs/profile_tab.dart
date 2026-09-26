import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../phone_screen.dart';
import '../../main.dart'; // To access themeNotifier

class ProfileTab extends StatefulWidget {
  final bool isGuest;

  const ProfileTab({Key? key, required this.isGuest}) : super(key: key);

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final ProfileService _profileService = ProfileService();
  
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

  void _logout(BuildContext context) async {
    final authService = AuthService();
    await authService.logout();
    
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => PhoneScreen()),
      (route) => false,
    );
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
        tabIndex: 4,
        icon: Icons.person_outline,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerColor = isDark ? AppTheme.darkDanger : AppTheme.lightDanger;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final bgColor = isDark ? AppTheme.darkBg : const Color(0xFFFBF9FF);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: AppTheme.accentColor)),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
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
                        child: Icon(Icons.person, size: 40, color: AppTheme.accentColor),
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
                            color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight,
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
              const SizedBox(height: 40),
              
              // Settings Header
              Text(
                'ACCOUNT SETTINGS',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight,
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
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.02),
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
                        themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
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
                          _profileService.updateNotificationPreferences({'push_enabled': val});
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: isDark ? AppTheme.darkDangerBg : const Color(0xFFFEE8EA),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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

  Widget _buildStatCard(BuildContext context, String count, String label, Color surfaceColor, Color borderColor, Color headingColor) {
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
              color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextLight : AppTheme.lightTextLight,
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
