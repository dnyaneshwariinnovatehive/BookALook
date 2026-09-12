import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/collaborator_api.dart';
import '../../../theme/app_theme.dart';
import '../../phone_screen.dart';
import 'edit_collaborator_profile_sheet.dart';

/// The collaborator's own page: who they are, what they have done, and out.
///
/// The tally is here rather than only on Home because this is the screen a
/// collaborator opens when they want to see their own work counted — and it is
/// the one number nobody else in the app shows them.
class CollaboratorProfileTab extends StatefulWidget {
  const CollaboratorProfileTab({super.key});

  @override
  State<CollaboratorProfileTab> createState() => _CollaboratorProfileTabState();
}

class _CollaboratorProfileTabState extends State<CollaboratorProfileTab> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      if (mounted) setState(() => _loading = false);
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
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
            'you have finished before logging out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.lightDanger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PhoneScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_failed) _buildOfflineNote() else ...[
            _buildHeaderCard(),
            const SizedBox(height: 18),
            _buildStatsCard(),
            const SizedBox(height: 18),
            _buildDetailsCard(),
          ],
          const SizedBox(height: 24),
          _buildLogoutButton(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeaderCard() {
    final name = _profile!['name']?.toString() ?? 'Collaborator';

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
                    fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  _profile!['phone']?.toString() ?? '',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text('Collaborator',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  // ----------------------------------------------------------------- stats

  Widget _buildStatsCard() {
    final stats = Map<String, dynamic>.from(_profile!['stats'] as Map? ?? {});

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your work',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('${stats['approved'] ?? 0}', 'Live', AppTheme.lightSuccess),
              _divider(),
              _stat('${stats['pending'] ?? 0}', 'Pending', AppTheme.lightWarning),
              _divider(),
              _stat('${stats['rejected'] ?? 0}', 'Sent back', AppTheme.lightDanger),
              _divider(),
              _stat('${stats['assigned'] ?? 0}', 'To do', AppTheme.accentColor),
            ],
          ),
          if ((stats['submitted'] ?? 0) > 0) ...[
            const SizedBox(height: 16),
            Text(
              '${stats['submitted']} ${stats['submitted'] == 1 ? 'salon' : 'salons'} onboarded in total.',
              style: const TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color colour) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: colour)),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: AppTheme.lightTextBody)),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 32,
        color: AppTheme.lightBorder,
      );

  // --------------------------------------------------------------- details

  Widget _buildDetailsCard() {
    final dob = DateTime.tryParse(_profile!['date_of_birth']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Contact details',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _row(Icons.person_outline, 'Name', _profile!['name']?.toString()),
          _row(Icons.smartphone_outlined, 'Phone', _profile!['phone']?.toString(),
              note: 'Used to sign in'),
          _row(Icons.alternate_email, 'Email', _profile!['email']?.toString()),
          _row(Icons.wc_outlined, 'Gender', _prettyGender(_profile!['gender']?.toString())),
          _row(Icons.cake_outlined, 'Date of birth',
              dob == null ? null : DateFormat('d MMMM yyyy').format(dob)),
          _row(Icons.home_outlined, 'Address', _profile!['address']?.toString()),
          _row(Icons.pin_drop_outlined, 'Pincode', _profile!['pincode']?.toString(),
              isLast: true),
        ],
      ),
    );
  }

  static String? _prettyGender(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'unspecified') return null;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  Widget _row(IconData icon, String label, String? value,
          {String? note, bool isLast = false}) =>
      Padding(
        padding: EdgeInsets.only(top: 12, bottom: isLast ? 0 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.lightTextLight),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 11, color: AppTheme.lightTextLight)),
                  const SizedBox(height: 2),
                  Text(
                    value == null || value.isEmpty ? 'Not set' : value,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: value == null || value.isEmpty
                          ? AppTheme.lightTextLight
                          : AppTheme.lightTextHeading,
                      fontStyle: value == null || value.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(note,
                        style: const TextStyle(fontSize: 10.5, color: AppTheme.lightTextLight)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------- states

  Widget _buildOfflineNote() => Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: AppTheme.lightTextLight),
            const SizedBox(height: 14),
            const Text('Could not load your profile',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Your saved drafts are safe on this device either way.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.lightTextBody),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentColor),
            ),
          ],
        ),
      );

  Widget _buildLogoutButton() => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Log out', style: TextStyle(fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.lightDanger,
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: AppTheme.lightDanger.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      );
}
