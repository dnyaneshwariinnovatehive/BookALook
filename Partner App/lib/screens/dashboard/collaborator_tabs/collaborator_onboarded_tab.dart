import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/collaborator_api.dart';
import '../../../services/collaborator_badges.dart';
import '../../../services/onboarding_draft_store.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/collaborator/collaborator_card.dart';
import '../../../widgets/collaborator/collaborator_chip.dart';
import '../../../widgets/collaborator/collaborator_empty_state.dart';
import '../../../widgets/collaborator/collaborator_skeleton.dart';
import '../../../widgets/collaborator/collaborator_thumb.dart';
import '../../collaborator/onboard_salon_screen.dart';

/// Everything this collaborator has submitted, and what SuperAdmin did with it.
///
/// Two jobs. First, accountability in one direction: a collaborator should
/// never have to ask anyone whether a salon they set up went live. Second, it
/// is where editing happens — a salon can be corrected right up to the moment
/// it is approved, and never after, so the edit button disappears at exactly
/// the point the salon stops being theirs.
class CollaboratorOnboardedTab extends StatefulWidget {
  /// Counts the bottom navigation badges are drawn from. Null when the tab is
  /// used standalone.
  final CollaboratorBadges? badges;

  /// Sends the collaborator to Assigned, offered by the empty state as the
  /// only place work can actually come from.
  final VoidCallback? onGoToAssigned;

  const CollaboratorOnboardedTab({super.key, this.badges, this.onGoToAssigned});

  @override
  State<CollaboratorOnboardedTab> createState() =>
      CollaboratorOnboardedTabState();
}

/// Public so the shell can ask for a refresh when the tab is re-selected.
class CollaboratorOnboardedTabState extends State<CollaboratorOnboardedTab> {
  bool _isLoading = true;
  bool _firstLoad = true;
  List<dynamic> _salons = [];

  /// null = everything. Otherwise the salon status being shown.
  ///
  /// Kept across rebuilds now that the tab lives in an [IndexedStack] rather
  /// than being rebuilt on every switch — previously the collaborator lost
  /// their filter every time they glanced at Assigned and came back.
  String? _filter;

  /// Salons whose details are currently unfolded, by id.
  ///
  /// Only ever holds approved salons — the editable ones open the form on tap
  /// instead, so there is nothing here to remember for them.
  final Set<String> _expanded = {};

  /// Days remaining at which a plan is worth colouring the whole card red.
  ///
  /// Deliberately not the backend's reminder window. The scheduler decides when
  /// to send somebody an email; this decides what a collaborator sees before
  /// they have opened anything, and five days is roughly how long it takes a
  /// phone call to land with an owner who has not already decided.
  static const _urgentDays = 5;

  static const _filters = <String?, String>{
    null: 'All',
    'pending_approval': 'Pending',
    'active': 'Approved',
    'rejected': 'Sent back',
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// Re-reads the list. Called by the shell when the tab is re-selected.
  Future<void> reload() => _fetch();

  Future<void> _fetch() async {
    // Anything finished but unsent should go before the collaborator concludes
    // from a short list that their afternoon vanished.
    await OnboardingDraftStore.instance.sync();

    try {
      final salons = await CollaboratorApi.onboardedSalons();
      if (!mounted) return;
      setState(() => _salons = salons);
      _reportBadges(salons);
    } catch (e) {
      debugPrint('Error fetching onboarded salons: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _firstLoad = false;
        });
      }
    }
  }

  /// Only `rejected` and `pending_approval` reach the badge.
  ///
  /// An approved salon is finished business — it belongs to its owner now, and
  /// a badge that never clears because "Live" grows all session would train
  /// the collaborator to ignore the dot.
  void _reportBadges(List<dynamic> salons) {
    widget.badges?.reportMySalons(
      awaitingApproval: _statusCount(salons, 'pending_approval'),
      sentBack: _statusCount(salons, 'rejected'),
    );
  }

  static int _statusCount(List<dynamic> salons, String status) =>
      salons.where((s) => (s as Map)['status'] == status).length;

  /// Replaces the fetched list with [salons], for tests.
  ///
  /// The card's subscription capsule and its red-at-five-days treatment are the
  /// whole point of this tab's latest change, and both are decided from the
  /// server payload. Reaching them through a widget test needs a way in that
  /// does not involve standing up the API.
  @visibleForTesting
  void seedForTest(List<Map<String, dynamic>> salons) {
    setState(() {
      _salons = salons;
      _isLoading = false;
      _firstLoad = false;
    });
  }

  List<Map<String, dynamic>> get _visible => _salons
      .map((s) => Map<String, dynamic>.from(s as Map))
      .where((s) => _filter == null || s['status'] == _filter)
      .toList();

  int _countOf(String? status) => status == null
      ? _salons.length
      : _salons.where((s) => (s as Map)['status'] == status).length;

  Future<void> _edit(Map<String, dynamic> salon) async {
    // The onboarding form is built around an assignment, so it is handed the
    // enquiry this salon came from plus the salon to fill itself from.
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardSalonScreen(
          enquiry: {
            'id': salon['enquiry_id'],
            'salon_name': salon['name'],
            'owner_name': salon['owner_name'],
            'phone': salon['owner_phone'],
            'city': salon['city'],
          },
          editingSalonId: salon['id']?.toString(),
        ),
      ),
    );

    if (saved == true) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLoad && _isLoading) {
      return const CollaboratorCardSkeleton(count: 3);
    }
    if (_salons.isEmpty) return _buildEmptyState();

    final visible = _visible;

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppTheme.accentColor,
      child: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: visible.isEmpty
                ? _buildNothingInFilter()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: visible.length,
                    itemBuilder: (_, index) => _buildSalonCard(visible[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() => SizedBox(
    height: 56,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        for (final entry in _filters.entries) ...[
          CollaboratorFilterChip(
            label: entry.value,
            count: _countOf(entry.key),
            selected: _filter == entry.key,
            onTap: () => setState(() => _filter = entry.key),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );

  Widget _buildSalonCard(Map<String, dynamic> salon) {
    final status = salon['status']?.toString() ?? '';
    final (statusLabel, statusColour, statusIcon) = _statusLook(status);
    final canEdit = salon['can_edit'] == true;
    final rejectionReason = salon['rejection_reason']?.toString();
    final subscription = _subscriptionLook(salon);
    final urgent = _isUrgent(salon);
    final palette = context.colors;

    final id = salon['id']?.toString();
    final expanded = expandableFor(salon) && _expanded.contains(id);

    return CollaboratorCard(
      // An editable salon spends its tap on the form, which is the fastest route
      // to fixing it. An approved one has nothing left to edit, so the same tap
      // is spent on the details instead.
      onTap: canEdit
          ? () => _edit(salon)
          : expandableFor(salon)
              ? () => _toggleExpanded(id)
              : null,
      // Whole-card red rather than a single red capsule: five days is close
      // enough that scrolling past the card should catch it, not just looking
      // directly at it.
      color: urgent ? palette.dangerBg : null,
      borderColor: urgent ? palette.danger.withValues(alpha: 0.35) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CollaboratorThumb(url: salon['cover_photo_url']?.toString()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      salon['name']?.toString() ?? 'Salon',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [salon['address'], salon['city']]
                          .where((p) => p != null && p.toString().isNotEmpty)
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Wrap, not Row: two capsules side by side is the normal case
                    // now, and a long plan name must not push the approval
                    // status off the edge of the card.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        CollaboratorChip(
                          label: statusLabel,
                          colour: statusColour,
                          icon: statusIcon,
                        ),
                        if (subscription != null)
                          CollaboratorChip(
                            label: subscription.$1,
                            colour: subscription.$2,
                            icon: subscription.$3,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Spells out that the card opens, since a tap that expands reads
              // as broken until you know it is meant to.
              if (expandableFor(salon))
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: palette.textTertiary,
                  ),
                ),
            ],
          ),

          if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: palette.dangerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 15,
                    color: palette.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rejectionReason,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: palette.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${salon['owner_name'] ?? 'Owner'} · '
                      '${salon['services_count'] ?? 0} '
                      '${salon['services_count'] == 1 ? 'service' : 'services'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Submitted ${_submittedOn(salon['submitted_at'])}',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => _edit(salon),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text(
                    status == 'rejected' ? 'Fix' : 'Edit',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    backgroundColor: palette.accentSoft,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                )
              else
                // Approved: the salon now belongs to its owner, and saying so
                // is kinder than a button that would be refused.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 13,
                      color: palette.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Handed over',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          if (expanded) ...[
            const SizedBox(height: 12),
            _buildSalonDetails(salon),
          ],
        ],
      ),
    );
  }

  /// The details panel an approved salon opens instead of the edit form.
  ///
  /// Everything here is something the collaborator can no longer change but
  /// still has to act on, which for an approved salon is almost entirely about
  /// reaching the owner.
  Widget _buildSalonDetails(Map<String, dynamic> salon) {
    final palette = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(
            Icons.place_outlined,
            'Address',
            [salon['address'], salon['city'], salon['state']]
                .where((p) => p != null && p.toString().isNotEmpty)
                .join(', '),
          ),
          _detailRow(
            Icons.person_outline,
            'Owner',
            [
              salon['owner_name']?.toString(),
              if (salon['owner_phone'] != null) salon['owner_phone'].toString(),
            ].whereType<String>().join(' · '),
          ),
          _detailRow(
            Icons.workspace_premium_outlined,
            'Plan',
            salon['plan_name']?.toString() ?? 'None on file',
          ),
          _detailRow(
            Icons.event_outlined,
            'Renews',
            _renewsOn(salon),
          ),
          _detailRow(
            Icons.spa_outlined,
            'Menu',
            (salon['services_count'] ?? 0) == 0
                ? 'No services priced yet'
                : '${salon['services_count']} '
                      '${salon['services_count'] == 1 ? 'service' : 'services'} '
                      'priced',
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _callOwner(
                salon['owner_phone']?.toString(),
                salon['name']?.toString() ?? 'the salon',
              ),
              icon: const Icon(Icons.call, size: 15),
              label: Text(
                'Call ${salon['owner_name'] ?? 'owner'}',
                style: const TextStyle(fontSize: 12.5),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentColor,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final palette = context.colors;
    final shown = value.trim().isEmpty ? '—' : value.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: palette.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10.5, color: palette.textTertiary),
                ),
                const SizedBox(height: 1),
                Text(
                  shown,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Whether this card unfolds in place rather than opening the edit form.
  bool expandableFor(Map<String, dynamic> salon) => salon['can_edit'] != true;

  void _toggleExpanded(String? id) {
    if (id == null) return;
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  /// Whether the plan is close enough to ending to turn the whole card red.
  ///
  /// A lapsed plan counts even though there are no days left to count: the
  /// salon is offline right now, which is worse than any countdown.
  bool _isUrgent(Map<String, dynamic> salon) {
    if (salon['status'] != 'active') return false;
    if (salon['lapsed'] == true) return true;
    final days = (salon['days_left'] as num?)?.toInt();
    return days != null && days <= _urgentDays;
  }

  /// The subscription capsule for an approved salon, or null when there is
  /// nothing worth saying.
  ///
  /// Only ever shown once a salon is live. A salon still sitting in SuperAdmin's
  /// queue has no plan to run out, so a capsule there would be inventing a
  /// deadline that nobody set.
  (String, Color, IconData)? _subscriptionLook(Map<String, dynamic> salon) {
    if (salon['status'] != 'active') return null;
    final palette = context.colors;

    if (salon['lapsed'] == true) {
      return ('Plan expired', palette.danger, Icons.cloud_off_outlined);
    }

    final days = (salon['days_left'] as num?)?.toInt();
    if (days == null) {
      return salon['needs_plan'] == true
          ? ('No plan chosen yet', palette.warning, Icons.help_outline)
          : null;
    }

    if (days <= _urgentDays) {
      return (
        days <= 0 ? 'Ends today' : 'Ends in $days days',
        palette.danger,
        Icons.timer_outlined,
      );
    }

    return ('Ends in $days days', palette.success, Icons.event_available_outlined);
  }

  /// The renewal line in the details panel, in words rather than a number.
  static String _renewsOn(Map<String, dynamic> salon) {
    if (salon['lapsed'] == true) return 'Expired — salon is offline';
    if (salon['needs_plan'] == true) return 'Waiting on the owner to pick a plan';

    final days = (salon['days_left'] as num?)?.toInt();
    if (days == null) return '—';

    if (days <= 0) return 'Ends today';

    final parsed = DateTime.tryParse(salon['renews_on']?.toString() ?? '');
    final date = parsed == null
        ? ''
        : ' on ${DateFormat('d MMM yyyy').format(parsed.toLocal())}';

    return days == 1
        ? 'Last day$date'
        : '$days days left$date';
  }

  Future<void> _callOwner(String? phone, String salonName) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(milliseconds: 2500), content: Text('No phone number on file for $salonName.')),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Could not start a call. The number is $phone.')));
    }
  }

  /// Salon status as the collaborator experiences it, not as the column spells
  /// it.
  ///
  /// Takes a [context] rather than reaching for the light-mode constants:
  /// these are read as ink on a card, and the card is a different colour in
  /// dark mode. A hardcoded success green on a near-black card is not the same
  /// signal as the one on white.
  (String, Color, IconData) _statusLook(String status) {
    final palette = context.colors;

    return switch (status) {
      'active' => (
        'Approved & live',
        palette.success,
        Icons.check_circle_outline,
      ),
      'rejected' => ('Sent back', palette.danger, Icons.error_outline),
      'suspended' => (
        'Suspended',
        palette.textSecondary,
        Icons.pause_circle_outline,
      ),
      _ => ('Waiting on SuperAdmin', palette.warning, Icons.hourglass_empty),
    };
  }

  static String _submittedOn(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null
        ? 'recently'
        : DateFormat('d MMM yyyy').format(parsed.toLocal());
  }

  Widget _buildNothingInFilter() => CollaboratorEmptyState(
    icon: Icons.filter_alt_off_outlined,
    title: 'Nothing ${_filters[_filter]!.toLowerCase()}',
    body:
        'No salon you submitted is ${_filters[_filter]!.toLowerCase()} at the '
        'moment. Switch filters to see the rest.',
    actionLabel: 'Show all',
    onAction: () => setState(() => _filter = null),
  );

  Widget _buildEmptyState() {
    final assignedHint = widget.onGoToAssigned != null;

    return CollaboratorEmptyState(
      icon: Icons.storefront_outlined,
      title: 'Nothing submitted yet',
      body:
          'Salons you onboard show up here with their approval status, so you '
          'always know which ones went live.',
      actionLabel: 'Check again',
      onAction: _fetch,
      secondaryLabel: assignedHint ? 'Go to Assigned' : null,
      onSecondary: widget.onGoToAssigned,
    );
  }
}
