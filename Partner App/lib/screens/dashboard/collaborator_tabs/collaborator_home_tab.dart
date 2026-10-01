import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/collaborator_api.dart';
import '../../../services/collaborator_badges.dart';
import '../../../services/onboarding_draft_store.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/collaborator/collaborator_card.dart';
import '../../../widgets/collaborator/collaborator_skeleton.dart';

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

  /// Counts the bottom navigation badges are drawn from. Null when the tab is
  /// used standalone.
  final CollaboratorBadges? badges;

  const CollaboratorHomeTab({
    super.key,
    required this.onGoToAssigned,
    required this.onGoToMySalons,
    this.badges,
  });

  @override
  State<CollaboratorHomeTab> createState() => CollaboratorHomeTabState();
}

/// Public so the shell can ask for a refresh when the collaborator comes back
/// to Home, the same way it already asks the other tabs.
class CollaboratorHomeTabState extends State<CollaboratorHomeTab> {
  final _store = OnboardingDraftStore.instance;

  Map<String, dynamic>? _profile;
  List<dynamic> _alerts = [];
  int _assignedCount = 0;
  bool _loading = true;
  bool _firstLoad = true;

  /// When the numbers on screen were last fetched.
  ///
  /// This tab is built around a collaborator working through a list with patchy
  /// signal, so showing how old the figures are matters as much as the figures
  /// themselves — otherwise a list that failed to refresh looks identical to an
  /// up-to-date one.
  DateTime? _fetchedAt;

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

  /// Re-reads the counts. Called by the shell when Home is re-selected or when
  /// the collaborator comes back from onboarding a salon.
  Future<void> reload() => _load();

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
        _fetchedAt = DateTime.now();
      });
      widget.badges?.reportAssigned(_assignedCount);
    } catch (_) {
      // Offline. Whatever we last knew stays on screen, and the draft counts
      // below are local anyway.
    } finally {
      // Cleared in a guard rather than an early return: a `return` inside
      // `finally` swallows anything still in flight, and it would also skip the
      // clearing below whenever the widget went away mid-fetch.
      if (mounted) {
        setState(() {
          _loading = false;
          _firstLoad = false;
        });
      }
    }
  }

  Map<String, dynamic> get _stats =>
      Map<String, dynamic>.from(_profile?['stats'] as Map? ?? {});

  String get _name => (_profile?['name']?.toString() ?? '').split(' ').first;

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
        SnackBar(
          content: Text('Could not start a call. The number is $phone.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLoad && _loading) {
      return const CollaboratorCardSkeleton(count: 3);
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          _buildGreeting(),
          if (_fetchedAt != null) ...[
            const SizedBox(height: 4),
            _buildFreshness(),
          ],
          const SizedBox(height: 18),

          if (_alerts.isNotEmpty) ...[
            _buildAlertsSection(),
            const SizedBox(height: 18),
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
            style: TextStyle(fontSize: 11.5, height: 1.45),
          ),

          const SizedBox(height: 22),
          _buildHowItWorks(),

          if (_alerts.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildRenewalStrip(),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------- greeting

  Widget _buildGreeting() {
    final name = _name;
    final palette = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Ready to onboard?' : '${_partOfDay()}, $name',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _loading
                    ? 'Catching up…'
                    : _assignedCount == 0
                    ? 'Nothing waiting on you right now.'
                    : '$_assignedCount ${_assignedCount == 1 ? 'salon is' : 'salons are'} '
                          'waiting to be onboarded.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: palette.accentSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.storefront, color: AppTheme.accentColor),
        ),
      ],
    );
  }

  /// "Updated 2 min ago", under the greeting.
  Widget _buildFreshness() {
    final at = _fetchedAt;
    if (at == null) return const SizedBox.shrink();

    final gap = DateTime.now().difference(at);
    final label = gap.inMinutes < 1
        ? 'just now'
        : gap.inHours < 1
        ? '${gap.inMinutes} min ago'
        : '${gap.inHours}h ago';

    return Text(
      'Updated $label',
      style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
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
  Widget _buildAlertsSection() {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 17,
              color: palette.warning,
            ),
            const SizedBox(width: 8),
            Text(
              _alerts.length == 1
                  ? 'Needs a call'
                  : '${_alerts.length} need a call',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final raw in _alerts)
          _buildAlertCard(Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final lapsed = alert['severity'] == 'lapsed';
    final colour = lapsed ? context.colors.danger : context.colors.warning;

    return CollaboratorCard(
      color: lapsed ? context.colors.dangerBg : context.colors.warningBg,
      borderColor: colour.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                lapsed ? Icons.wifi_off_rounded : Icons.timer_outlined,
                size: 18,
                color: colour,
              ),
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
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _callOwner(
                  alert['owner_phone']?.toString(),
                  alert['salon_name']?.toString() ?? 'the salon',
                ),
                icon: const Icon(Icons.call, size: 15),
                label: const Text(
                  'Call owner',
                  style: TextStyle(fontSize: 12.5),
                ),
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

  // -------------------------------------------------------------- renewals

  /// A short horizontal run of the salons whose plans are running out.
  ///
  /// The alerts section above this says the same thing in a paragraph. This one
  /// exists because renewal work is per-salon and you approach it as a queue:
  /// you want to see how many, glance at which, and work down them — not read
  /// about them. Both read the same [CollaboratorApi.alerts] payload, so they
  /// cannot disagree about who is on the list.
  Widget _buildRenewalStrip() {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_busy_outlined, size: 17, color: palette.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Renewals coming up',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'A collaborator cannot renew a plan — only the owner can pay. These are '
          'the calls worth making first.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: palette.textTertiary,
          ),
        ),
        const SizedBox(height: 11),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _alerts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _buildRenewalMiniCard(
              Map<String, dynamic>.from(_alerts[i] as Map),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRenewalMiniCard(Map<String, dynamic> alert) {
    final lapsed = alert['severity'] == 'lapsed';
    final days = (alert['days_left'] as num?)?.toInt();
    final colour = lapsed ? context.colors.danger : context.colors.warning;
    final palette = context.colors;

    final countdown = lapsed
        ? 'Offline'
        : days == null
        ? '—'
        : days <= 0
        ? 'Ends today'
        : days == 1
        ? '1 day left'
        : '$days days left';

    return SizedBox(
      width: 172,
      child: CollaboratorCard(
        color: lapsed ? palette.dangerBg : palette.warningBg,
        borderColor: colour.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  lapsed ? Icons.wifi_off_rounded : Icons.timer_outlined,
                  size: 14,
                  color: colour,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    countdown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colour,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              alert['salon_name']?.toString() ?? 'Salon',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              [alert['owner_name'], alert['city']]
                  .where((p) => p != null && p.toString().isNotEmpty)
                  .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _callOwner(
                  alert['owner_phone']?.toString(),
                  alert['salon_name']?.toString() ?? 'the salon',
                ),
                icon: const Icon(Icons.call, size: 14),
                label: const Text(
                  'Call owner',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colour,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ work

  Widget _buildWorkGrid() {
    if (_loading) {
      return SkeletonRow(
        children: const [
          SkeletonBox(height: 92, radius: 14),
          SkeletonBox(height: 92, radius: 14),
          SkeletonBox(height: 92, radius: 14),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _tile(
            value: '$_assignedCount',
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
            colour: context.colors.info,
            onTap: widget.onGoToAssigned,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tile(
            value: '${_stats['approved'] ?? 0}',
            label: 'Live salons',
            icon: Icons.verified_outlined,
            colour: context.colors.success,
            onTap: widget.onGoToMySalons,
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required String value,
    required String label,
    required IconData icon,
    required Color colour,
    required VoidCallback onTap,
  }) {
    final palette = context.colors;

    return CollaboratorCard(
      // Removed the zero bottom margin the old tile had, so the three tiles
      // sit flush in their row rather than leaving a gap under the last one.
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Semantics(
        button: true,
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: colour),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.3,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueNote() {
    final warning = context.colors.warning;

    return CollaboratorCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(13),
      color: context.colors.warningBg,
      borderColor: Colors.transparent,
      onTap: _store.sync,
      child: Semantics(
        button: true,
        label: _store.isSyncing
            ? 'Sending ${_store.queuedCount}'
            : '${_store.queuedCount} waiting to send. Tap to try now.',
        excludeSemantics: true,
        child: Row(
          children: [
            if (_store.isSyncing)
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: warning,
                ),
              )
            else
              Icon(Icons.cloud_upload_outlined, size: 18, color: warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _store.isSyncing
                    ? 'Sending ${_store.queuedCount}…'
                    : '${_store.queuedCount} finished '
                          '${_store.queuedCount == 1 ? 'salon is' : 'salons are'} waiting to '
                          'send. Tap to try now.',
                style: TextStyle(fontSize: 12, height: 1.4, color: warning),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: widget.onGoToAssigned,
      icon: const Icon(Icons.add_business),
      label: const Text(
        'Onboard New Salon',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: AppTheme.accentColor,
        foregroundColor: context.colors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  /// Worth stating plainly once, but not worth the screenful.
  ///
  /// This used to render all four steps inline, which pushed the primary
  /// action and the call alerts below the fold on a normal-sized phone — the
  /// reference material was competing with the work. It is now collapsed to a
  /// single tappable row and opens on demand.
  Widget _buildHowItWorks() {
    const steps = <(String, String)>[
      ('1', 'SuperAdmin assigns you a salon that filled in the enquiry form.'),
      (
        '2',
        'You visit it and build the profile — photos, hours, and services '
            'if the owner wants them priced now.',
      ),
      (
        '3',
        'Submit for approval. No signal needed: it sends itself when you '
            'have one.',
      ),
      (
        '4',
        'You can keep editing until SuperAdmin approves it. After that the '
            "salon is the owner's.",
      ),
    ];

    return _HowItWorksCard(steps: steps);
  }
}

/// Collapsible explainer. Kept in its own widget so its open/closed state
/// survives the parent's rebuilds.
class _HowItWorksCard extends StatefulWidget {
  final List<(String, String)> steps;

  const _HowItWorksCard({required this.steps});

  @override
  State<_HowItWorksCard> createState() => _HowItWorksCardState();
}

class _HowItWorksCardState extends State<_HowItWorksCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return CollaboratorCard(
      margin: EdgeInsets.zero,
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'How onboarding works',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 14),
            for (final (number, text) in widget.steps)
              Padding(
                padding: EdgeInsets.only(
                  bottom: number == widget.steps.last.$1 ? 0 : 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: palette.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          number,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
