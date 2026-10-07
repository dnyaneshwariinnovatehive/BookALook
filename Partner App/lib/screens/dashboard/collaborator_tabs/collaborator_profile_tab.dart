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
import '../../../widgets/initials_avatar.dart';

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
        ).showSnackBar(const SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Profile updated.')));
      }
    }
  }

  Future<void> _logout() async {
    // Grabbed before anything is awaited. The root navigator is an ancestor of
    // the whole shell and outlives this tab, so holding on to it is safe — and it
    // is what lets the sign-out complete even if the Profile tab is disposed
    // while the dialog is open. Guarding on `mounted` instead would leave the
    // collaborator signed-in-but-stranded on a blank panel.
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    // The dialog must be popped with its OWN context. [showDialog] puts its
    // route on the root navigator, but this tab sits inside a [TabNavigator] —
    // so `Navigator.pop(context)` on the tab's context pops the tab's only
    // route instead of the dialog. The dialog then stays on screen forever and
    // `confirmed` never resolves, which reads to the user as a dead button.
    // Every collaborator tab is nested this way, so this is not a one-off.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Any salon drafts saved on this device will be cleared. Send anything '
          'you have finished before logging out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).brightness == Brightness.dark
                  ? AppTheme.darkDanger
                  : AppTheme.lightDanger,
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // The token has to go whether or not the device unregisters. A throw from
    // Firebase in here would otherwise leave the collaborator signed in with a
    // button that appears to do nothing, and no explanation.
    try {
      await PushNotificationService().unregisterDevice();
    } catch (e) {
      debugPrint('Could not unregister device on logout: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    rootNavigator.pushAndRemoveUntil(
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

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.accentColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_failed)
                _buildOfflineNote()
              else ...[
                _buildHeaderCard(),
                const SizedBox(height: 24),
                
                // Options List
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildStatsCard(),
                      Divider(height: 1, indent: 56, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12)),
                      _buildDetailsCard(),
                      Divider(height: 1, indent: 56, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12)),
                      _buildAppearanceCard(),
                      Divider(height: 1, indent: 56, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12)),
                      const PushNotificationToggle(),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                _buildLogoutButton(),
                const SizedBox(height: 40),
              ]
            ],
          ),
        ),
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return SwitchListTile(
          value: isDark,
          onChanged: _toggleDarkMode,
          secondary: Icon(
            isDark ? Icons.dark_mode : Icons.light_mode,
            color: isDark ? Colors.yellow : Colors.orange,
          ),
          title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        );
      },
    );
  }

  // ---------------------------------------------------------------- header


  Widget _buildHeaderCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = _profile!['name']?.toString() ?? 'Collaborator';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            InitialsAvatar(
              name: name,
              radius: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Collaborator',
                    style: TextStyle(color: AppTheme.accentColor, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _profile!['phone']?.toString() ?? '',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- stats


  Widget _buildStatsCard() {
    final stats = Map<String, dynamic>.from(_profile!['stats'] as Map? ?? {});
    final palette = context.colors;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(Icons.bar_chart, color: AppTheme.accentColor),
        title: const Text('Your work', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        children: [
          Row(
            children: [
              _stat('', 'Live', palette.success),
              _divider(),
              _stat('', 'Pending', palette.warning),
              _divider(),
              _stat('', 'Sent back', palette.danger),
              _divider(),
              _stat('', 'To do', AppTheme.accentColor),
            ],
          ),
          if ((stats['submitted'] ?? 0) > 0) ...[
            const SizedBox(height: 16),
            Text(
              '  onboarded in total.',
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

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(Icons.contact_mail_outlined, color: Colors.blue),
        title: const Text('Contact details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          _row(Icons.person_outline, 'Name', _profile!['name']?.toString()),
          _row(Icons.smartphone_outlined, 'Phone', _profile!['phone']?.toString(), note: 'Used to sign in'),
          _row(Icons.alternate_email, 'Email', _profile!['email']?.toString()),
          _row(Icons.wc_outlined, 'Gender', _prettyGender(_profile!['gender']?.toString())),
          _row(Icons.cake_outlined, 'Date of birth', dob == null ? null : DateFormat('d MMMM yyyy').format(dob)),
          _row(Icons.home_outlined, 'Address', _profile!['address']?.toString()),
          _row(Icons.pin_drop_outlined, 'Pincode', _profile!['pincode']?.toString(), isLast: true),
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
