import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/collaborator_api.dart';
import '../../../services/onboarding_draft_store.dart';
import '../../../theme/app_theme.dart';

/// Where a collaborator starts their day.
///
/// Answers one question in the first screenful: what needs doing. Assignments
/// waiting, drafts half typed, salons about to go dark — each with a tap that
/// leads straight to it. "Onboard New Salon" does not open a blank form: a
/// collaborator can only build a salon someone enquired about and SuperAdmin
/// then assigned to them, so the button leads to the worklist.
class CollaboratorHomeTab extends StatefulWidget {
  /// Takes the collaborator to the Assigned tab, the only entry into onboarding.
  final VoidCallback onGoToAssigned;

  /// Takes them to My Salons, where approval status lives.
  final VoidCallback onGoToMySalons;

  const CollaboratorHomeTab({
    super.key,
    required this.onGoToAssigned,
    required this.onGoToMySalons,
  });

  @override
  State<CollaboratorHomeTab> createState() => _CollaboratorHomeTabState();
}

class _CollaboratorHomeTabState extends State<CollaboratorHomeTab> {
  final _store = OnboardingDraftStore.instance;

  Map<String, dynamic>? _profile;
  List<dynamic> _alerts = [];
  int _assignedCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _store.load();

    try {
      // Three independent reads; one failing should not blank the other two.
      final results = await Future.wait([
        CollaboratorApi.assignedEnquiries(),
        CollaboratorApi.alerts(),
        CollaboratorApi.profile(),
      ]);

      if (!mounted) return;
      setState(() {
        _assignedCount = (results[0] as List).length;
        _alerts = results[1] as List;
        _profile = results[2] as Map<String, dynamic>?;
      });
    } catch (_) {
      // Offline. Whatever we last knew stays on screen, and the draft counts
      // below are local anyway.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _stats =>
      Map<String, dynamic>.from(_profile?['stats'] as Map? ?? {});

  Future<void> _callOwner(String? phone, String salonName) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No phone number on file for $salonName.')),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call. The number is $phone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          _buildGreeting(),
          const SizedBox(height: 20),

          if (_alerts.isNotEmpty) ...[
            _buildAlertsSection(),
            const SizedBox(height: 20),
          ],

          _buildWorkGrid(),

          if (_store.queuedCount > 0) ...[
            const SizedBox(height: 14),
            _buildQueueNote(),
          ],

          const SizedBox(height: 22),
          _buildPrimaryAction(),
          const SizedBox(height: 10),
          const Text(
            'Salons reach you through the website enquiry form. SuperAdmin assigns '
            'one to you and it appears under Assigned.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.45, color: AppTheme.lightTextLight),
          ),

          const SizedBox(height: 26),
          _buildHowItWorks(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- greeting

  Widget _buildGreeting() {
    final name = (_profile?['name']?.toString() ?? '').split(' ').first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Ready to onboard?' : '${_partOfDay()}, $name',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _loading
                    ? 'Catching up…'
                    : _assignedCount == 0
                        ? 'Nothing waiting on you right now.'
                        : '$_assignedCount ${_assignedCount == 1 ? 'salon is' : 'salons are'} '
                            'waiting to be onboarded.',
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4, color: AppTheme.lightTextBody),
              ),
            ],
          ),
        ),
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: AppTheme.lightAccentSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.storefront, color: AppTheme.accentColor),
        ),
      ],
    );
  }

  static String _partOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ---------------------------------------------------------------- alerts

  /// Salons the collaborator set up that are about to stop taking bookings.
  ///
  /// They cannot renew one — only the owner can pay — so the single action
  /// offered is the call. Nothing here pretends otherwise.
  Widget _buildAlertsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 17, color: AppTheme.lightWarning),
              const SizedBox(width: 8),
              Text(
                _alerts.length == 1 ? 'Needs a call' : '${_alerts.length} need a call',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final raw in _alerts) _buildAlertCard(Map<String, dynamic>.from(raw as Map)),
        ],
      );

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final lapsed = alert['severity'] == 'lapsed';
    final colour = lapsed ? AppTheme.lightDanger : AppTheme.lightWarning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lapsed ? AppTheme.lightDangerBg : AppTheme.lightWarningBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(lapsed ? Icons.wifi_off_rounded : Icons.timer_outlined,
                  size: 18, color: colour),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert['message']?.toString() ?? '',
                  style: TextStyle(fontSize: 13, height: 1.4, color: colour),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${alert['owner_name'] ?? 'Owner'}'
                  '${alert['city'] != null ? ' · ${alert['city']}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextBody),
                ),
              ),
              TextButton.icon(
                onPressed: () => _callOwner(
                  alert['owner_phone']?.toString(),
                  alert['salon_name']?.toString() ?? 'the salon',
                ),
                icon: const Icon(Icons.call, size: 15),
                label: const Text('Call owner', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  foregroundColor: colour,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ work

  Widget _buildWorkGrid() => Row(
        children: [
          Expanded(
            child: _tile(
              value: _loading ? '—' : '$_assignedCount',
              label: 'To onboard',
              icon: Icons.assignment_outlined,
              colour: AppTheme.accentColor,
              onTap: widget.onGoToAssigned,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile(
              value: '${_store.pendingCount}',
              label: 'Drafts on this phone',
              icon: Icons.edit_note_outlined,
              colour: AppTheme.lightInfo,
              onTap: widget.onGoToAssigned,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile(
              value: _loading ? '—' : '${_stats['approved'] ?? 0}',
              label: 'Live salons',
              icon: Icons.verified_outlined,
              colour: AppTheme.lightSuccess,
              onTap: widget.onGoToMySalons,
            ),
          ),
        ],
      );

  Widget _tile({
    required String value,
    required String label,
    required IconData icon,
    required Color colour,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 19, color: colour),
              const SizedBox(height: 10),
              Text(value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10.5, height: 1.3, color: AppTheme.lightTextBody)),
            ],
          ),
        ),
      );

  Widget _buildQueueNote() => GestureDetector(
        onTap: _store.sync,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppTheme.lightWarningBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (_store.isSyncing)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.lightWarning),
                )
              else
                const Icon(Icons.cloud_upload_outlined,
                    size: 18, color: AppTheme.lightWarning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _store.isSyncing
                      ? 'Sending ${_store.queuedCount}…'
                      : '${_store.queuedCount} finished '
                          '${_store.queuedCount == 1 ? 'salon is' : 'salons are'} waiting to '
                          'send. Tap to try now.',
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, color: AppTheme.lightWarning),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildPrimaryAction() => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: widget.onGoToAssigned,
          icon: const Icon(Icons.add_business),
          label: const Text('Onboard New Salon',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: AppTheme.accentColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  /// Worth stating plainly once: a collaborator's job has a defined end, and
  /// knowing that up front avoids them going looking for an edit button on a
  /// live salon later.
  Widget _buildHowItWorks() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How onboarding works',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _step('1', 'SuperAdmin assigns you a salon that filled in the enquiry form.'),
            _step('2', 'You visit it and build the profile — photos, hours, and services '
                'if the owner wants them priced now.'),
            _step('3', 'Submit for approval. No signal needed: it sends itself when you '
                'have one.'),
            _step('4', 'You can keep editing until SuperAdmin approves it. After that the '
                'salon is the owner\'s.', isLast: true),
          ],
        ),
      );

  Widget _step(String number, String text, {bool isLast = false}) => Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppTheme.lightAccentSoft,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(number,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentColor)),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.45, color: AppTheme.lightTextBody)),
            ),
          ],
        ),
      );
}
