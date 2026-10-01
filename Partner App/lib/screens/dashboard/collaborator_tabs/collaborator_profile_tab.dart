import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../main.dart';
import '../../../services/collaborator_api.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../phone_screen.dart';
import 'edit_collaborator_profile_sheet.dart';
import '../../../services/push_notification_service.dart';
import '../../../widgets/collaborator/collaborator_card.dart';
import '../../../widgets/collaborator/collaborator_empty_state.dart';
import '../../../widgets/push_notification_toggle.dart';

/// The collaborator's own page: who they are, what they have done, and out.
///
/// The tally is here rather than only on Home because this is the screen a
/// collaborator opens when they want to see their own work counted — and it is
/// the one number nobody else in the app shows them.
class CollaboratorProfileTab extends StatefulWidget {
  const CollaboratorProfileTab({super.key});

  @override
  State<CollaboratorProfileTab> createState() => CollaboratorProfileTabState();
}

/// Public so the shell can ask for a refresh when the tab is re-selected.
class CollaboratorProfileTabState extends State<CollaboratorProfileTab> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _firstLoad = true;
  bool _failed = false;

  /// Whether the contact-details capsule is showing its rows.
  ///
  /// Starts collapsed. The details are things a collaborator already knows and
  /// edits rarely — they are not what they open Profile to see, and Profile was
  /// scrolling past them every session on the way to the tally. The capsule
  /// keeps them one tap away without spending the height on them by default.
  bool _detailsExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Re-reads the profile. Called by the shell when the tab is re-selected.
  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _failed = false);

    try {
      final profile = await CollaboratorApi.profile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _failed = profile == null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _firstLoad = false;
        });
      }
    }
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditCollaboratorProfileSheet(profile: _profile!),
    );

    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Any salon drafts saved on this device will be cleared. Send anything '
          'you have finished before logging out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.colors.danger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await PushNotificationService().unregisterDevice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    // Must bypass the shell's per-tab navigators. Each tab is a [TabNavigator],
    // so a plain push here would put the login screen inside the Profile tab and
    // leave the bottom bar sitting under it. See lib/widgets/tab_navigator.dart.
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneScreen()),
      (route) => false,
    );
  }

  Future<void> _toggleDarkMode(bool value) async {
    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLoad && _loading) {
      return const CollaboratorLoadingState();
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentColor,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_failed)
            _buildOfflineNote()
          else ...[
            _buildHeaderCard(),
            const SizedBox(height: 18),
            _buildStatsCard(),
            const SizedBox(height: 18),
            _buildDetailsCard(),
            const SizedBox(height: 18),
            _buildAppearanceCard(),
          ],
          const SizedBox(height: 24),
          const PushNotificationToggle(),
          const SizedBox(height: 24),
          _buildLogoutButton(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Dark mode, offered here because the admin "More" tab and the provider
  /// profile both have it and the collaborator had no way to reach it at all.
  ///
  /// A collaborator who set dark mode while signed in as another role got a
  /// light-coloured app on every one of these four tabs, with no way to change
  /// it back without logging out.
  Widget _buildAppearanceCard() {
    final palette = context.colors;

    return CollaboratorCard(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, mode, _) {
          final isDark = mode == ThemeMode.dark;

          return Row(
            children: [
              Icon(
                isDark ? Icons.dark_mode : Icons.light_mode_outlined,
                size: 20,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dark mode',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDark ? 'On' : 'Off',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isDark,
                onChanged: _toggleDarkMode,
                activeThumbColor: AppTheme.accentColor,
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeaderCard() {
    final name = _profile!['name']?.toString() ?? 'Collaborator';

    // The gradient runs to [AppTheme.accentGradientEnd] in both modes. That is
    // deliberate: it is the brand mark, it carries white text, and a darker
    // variant for dark mode would read as a different brand rather than the
    // same one. Only the text on top of it needed checking for contrast.
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initials(name),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
                  name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _profile!['phone']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    'Collaborator',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  // ----------------------------------------------------------------- stats

  Widget _buildStatsCard() {
    final stats = Map<String, dynamic>.from(_profile!['stats'] as Map? ?? {});
    final palette = context.colors;

    return CollaboratorCard(
      margin: EdgeInsets.zero,
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your work',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('${stats['approved'] ?? 0}', 'Live', palette.success),
              _divider(),
              _stat('${stats['pending'] ?? 0}', 'Pending', palette.warning),
              _divider(),
              _stat('${stats['rejected'] ?? 0}', 'Sent back', palette.danger),
              _divider(),
              _stat('${stats['assigned'] ?? 0}', 'To do', AppTheme.accentColor),
            ],
          ),
          if ((stats['submitted'] ?? 0) > 0) ...[
            const SizedBox(height: 16),
            Text(
              '${stats['submitted']} ${stats['submitted'] == 1 ? 'salon' : 'salons'} onboarded in total.',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color colour) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: colour,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: context.colors.textSecondary),
        ),
      ],
    ),
  );

  Widget _divider() =>
      Container(width: 1, height: 32, color: context.colors.border);

  // --------------------------------------------------------------- details

  /// The contact details, as a capsule that opens.
  ///
  /// Collapsed it is one row: the label, enough of the details to recognise
  /// them without opening anything, and a chevron that says which way it goes.
  /// That matters more than the height it saves — an unlabelled row with no
  /// chevron reads as a setting, and a collaborator cannot tell whether tapping
  /// it navigates somewhere or just expands.
  ///
  /// [AnimatedCrossFade] rather than a conditional build, so opening it grows
  /// the card in place instead of the whole list jumping under the finger.
  Widget _buildDetailsCard() {
    final palette = context.colors;
    final dob = DateTime.tryParse(_profile!['date_of_birth']?.toString() ?? '');

    return CollaboratorCard(
      margin: EdgeInsets.zero,
      radius: 16,
      onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact details',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detailsExpanded ? 'Tap to hide' : _detailsSummary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Inside the capsule's own tap target, so this button has to stop
              // the tap from bubbling — otherwise editing also folds the capsule
              // shut behind the sheet.
              TextButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              AnimatedRotation(
                turns: _detailsExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            crossFadeState: _detailsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(
                    Icons.person_outline,
                    'Name',
                    _profile!['name']?.toString(),
                  ),
                  _row(
                    Icons.smartphone_outlined,
                    'Phone',
                    _profile!['phone']?.toString(),
                    note: 'Used to sign in',
                  ),
                  _row(
                    Icons.alternate_email,
                    'Email',
                    _profile!['email']?.toString(),
                  ),
                  _row(
                    Icons.wc_outlined,
                    'Gender',
                    _prettyGender(_profile!['gender']?.toString()),
                  ),
                  _row(
                    Icons.cake_outlined,
                    'Date of birth',
                    dob == null ? null : DateFormat('d MMMM yyyy').format(dob),
                  ),
                  _row(
                    Icons.home_outlined,
                    'Address',
                    _profile!['address']?.toString(),
                  ),
                  _row(
                    Icons.pin_drop_outlined,
                    'Pincode',
                    _profile!['pincode']?.toString(),
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the collapsed row shows instead of the rows themselves: one detail
  /// worth recognising, so the capsule is not a mystery box that has to be
  /// opened to find out what is in it.
  String _detailsSummary() {
    for (final key in ['email', 'phone']) {
      final value = (_profile![key]?.toString() ?? '').trim();
      if (value.isNotEmpty) return value;
    }

    return 'Tap to see';
  }

  static String? _prettyGender(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'unspecified') return null;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  Widget _row(
    IconData icon,
    String label,
    String? value, {
    String? note,
    bool isLast = false,
  }) {
    final palette = context.colors;
    final isEmpty = value == null || value.isEmpty;

    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: palette.textTertiary),
                ),
                const SizedBox(height: 2),
                Text(
                  isEmpty ? 'Not set' : value,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isEmpty ? palette.textTertiary : palette.textPrimary,
                    fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- states

  Widget _buildOfflineNote() {
    return CollaboratorEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Could not load your profile',
      body: 'Your saved drafts are safe on this device either way.',
      actionLabel: 'Try again',
      onAction: _load,
    );
  }

  Widget _buildLogoutButton() {
    final palette = context.colors;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout, size: 18),
        label: const Text(
          'Log out',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.danger,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: palette.danger.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
