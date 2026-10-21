import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/onboarding_draft.dart';
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

/// All salons the collaborator manages: assigned enquiries to onboard,
/// directory salons in their care, and submitted salons across all approval states.
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
  final _store = OnboardingDraftStore.instance;

  bool _isLoading = true;
  bool _firstLoad = true;
  List<dynamic> _salons = [];
  List<dynamic> _enquiries = [];
  List<dynamic> _assignedSalons = [];
  List<dynamic> _alerts = [];

  /// null = everything. Otherwise the salon status or group being shown:
  /// 'assigned', 'pending_approval', 'active', 'rejected'.
  String? _filter;

  /// Salons whose details are currently unfolded, by id.
  final Set<String> _expanded = {};

  static const _urgentDays = 5;

  static const _filters = <String?, String>{
    null: 'All',
    'assigned': 'Assigned',
    'pending_approval': 'Pending',
    'active': 'Approved',
    'rejected': 'Sent back',
  };

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _fetch();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// Re-reads the list. Called by the shell when the tab is re-selected.
  Future<void> reload() => _fetch();

  Future<void> _fetch() async {
    try {
      try {
        await _store.sync();
      } catch (e) {
        debugPrint('Error syncing onboarding drafts: $e');
      }

      final results = await Future.wait([
        CollaboratorApi.onboardedSalons(),
        CollaboratorApi.assignedEnquiries(),
        CollaboratorApi.assignedSalons(),
        CollaboratorApi.alerts(),
      ]);

      if (!mounted) return;
      setState(() {
        _salons = results[0];
        _enquiries = results[1];
        _assignedSalons = results[2];
        _alerts = results[3];
      });
      _reportBadges(_salons, _enquiries);
    } catch (e) {
      debugPrint('Error fetching collaborator salons: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _firstLoad = false;
        });
      }
    }
  }

  void _reportBadges(List<dynamic> salons, List<dynamic> enquiries) {
    final awaiting = salons.where((s) => _isPending((s as Map)['status']?.toString())).length;
    final sentBack = salons.where((s) {
      final st = (s as Map)['status']?.toString();
      return _isRejected(st);
    }).length +
        enquiries.where((e) =>
            (e as Map)['needs_correction'] == true &&
            !salons.any((s) => s['id']?.toString() == e['salon_id']?.toString())).length;

    widget.badges?.reportMySalons(
      awaitingApproval: awaiting,
      sentBack: sentBack,
    );
  }

  @visibleForTesting
  void seedForTest(
    List<Map<String, dynamic>> salons, {
    List<dynamic>? enquiries,
    List<dynamic>? assignedSalons,
    List<dynamic>? alerts,
  }) {
    setState(() {
      _salons = salons;
      if (enquiries != null) _enquiries = enquiries;
      if (assignedSalons != null) _assignedSalons = assignedSalons;
      if (alerts != null) _alerts = alerts;
      _isLoading = false;
      _firstLoad = false;
    });
  }

  static bool _isApproved(String? status) {
    final s = status?.toLowerCase().trim();
    return s == 'active' || s == 'approved';
  }

  static bool _isPending(String? status) {
    final s = status?.toLowerCase().trim();
    return s == 'pending_approval' || s == 'pending';
  }

  static bool _isRejected(String? status) {
    final s = status?.toLowerCase().trim();
    return s == 'rejected' || s == 'needs_correction';
  }

  List<Map<String, dynamic>> get _combinedSalons {
    final seen = <String>{};
    final combined = <Map<String, dynamic>>[];

    for (final raw in _salons) {
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        final id = item['id']?.toString();
        if (id != null && seen.add(id)) {
          combined.add(item);
        }
      }
    }

    for (final raw in _assignedSalons) {
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        final id = item['id']?.toString();
        if (id != null && seen.add(id)) {
          combined.add(item);
        }
      }
    }

    return combined;
  }

  int _countOf(String? status) {
    if (status == null) {
      final unlinkedEnquiries = _enquiries.where(
        (e) =>
            e['salon_id'] == null ||
            !_combinedSalons.any((s) => s['id']?.toString() == e['salon_id']?.toString()),
      ).length;
      return unlinkedEnquiries + _assignedSalons.length + _salons.length;
    }
    if (status == 'assigned') {
      return _enquiries.length + _assignedSalons.length;
    }
    if (status == 'rejected') {
      final rejectedSalons = _combinedSalons.where((s) {
        final st = s['status']?.toString();
        return _isRejected(st);
      }).length;
      final rejectedEnquiries = _enquiries.where(
        (e) =>
            (e as Map)['needs_correction'] == true &&
            !_combinedSalons.any((s) => s['id']?.toString() == e['salon_id']?.toString()),
      ).length;
      return rejectedSalons + rejectedEnquiries;
    }
    if (status == 'pending_approval' || status == 'pending') {
      final fromSalons = _salons.where((s) => _isPending(s['status']?.toString())).length;
      final fromAssigned = _assignedSalons.where((s) =>
          _isPending(s['status']?.toString()) &&
          !_salons.any((ms) => ms['id']?.toString() == s['id']?.toString())).length;
      return fromSalons + fromAssigned;
    }
    if (status == 'active' || status == 'approved') {
      final fromSalons = _salons.where((s) => _isApproved(s['status']?.toString())).length;
      final fromAssigned = _assignedSalons.where((s) =>
          _isApproved(s['status']?.toString()) &&
          !_salons.any((ms) => ms['id']?.toString() == s['id']?.toString())).length;
      return fromSalons + fromAssigned;
    }
    return _salons.where((s) => (s as Map)['status'] == status).length;
  }

  Future<void> _openOnboarding(Map<String, dynamic> enquiry) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OnboardSalonScreen(enquiry: enquiry)),
    );

    if (submitted == true) await _fetch();
    if (mounted) setState(() {});
  }

  Future<void> _edit(Map<String, dynamic> salon) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardSalonScreen(
          enquiry: salon['enquiry_id'] != null
              ? {
                  'id': salon['enquiry_id'],
                  'salon_name': salon['name'],
                  'owner_name': salon['owner_name'],
                  'phone': salon['owner_phone'],
                  'city': salon['city'],
                }
              : null,
          editingSalonId: salon['id']?.toString(),
        ),
      ),
    );

    if (saved == true) await _fetch();
  }

  Future<void> _callOwner(String? phone, String salonName) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text('No phone number on file for $salonName.'),
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text('Could not start a call. The number is $phone.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLoad && _isLoading) {
      return const CollaboratorCardSkeleton(count: 3);
    }

    final hasAnyData = _salons.isNotEmpty ||
        _enquiries.isNotEmpty ||
        _assignedSalons.isNotEmpty ||
        _alerts.isNotEmpty ||
        _store.queuedCount > 0;

    if (!hasAnyData) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppTheme.accentColor,
      child: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _buildFilteredBody(),
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

  Widget _buildFilteredBody() {
    if (_filter == 'assigned') {
      final hasAssigned =
          _enquiries.isNotEmpty || _assignedSalons.isNotEmpty || _store.queuedCount > 0;
      if (!hasAssigned) {
        return _buildNothingInFilter();
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          if (_store.queuedCount > 0) _buildQueueBanner(),
          if (_enquiries.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _enquiries.length == 1
                    ? '1 salon to onboard'
                    : '${_enquiries.length} salons to onboard',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            for (final enquiry in _enquiries)
              _buildEnquiryCard(Map<String, dynamic>.from(enquiry as Map)),
          ],
          if (_assignedSalons.isNotEmpty) _buildAssignedSalonsSection(),
        ],
      );
    }

    if (_filter == 'pending_approval' || _filter == 'active' || _filter == 'rejected') {
      final List<Map<String, dynamic>> visibleSalons = _combinedSalons
          .where((s) {
            final st = s['status']?.toString();
            if (_filter == 'rejected') {
              return _isRejected(st);
            }
            if (_filter == 'active') {
              return _isApproved(st);
            }
            if (_filter == 'pending_approval') {
              return _isPending(st);
            }
            return st == _filter;
          })
          .toList();

      final List<Map<String, dynamic>> extraEnquiries = _filter == 'rejected'
          ? _enquiries
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((e) =>
                  e['needs_correction'] == true &&
                  !visibleSalons.any((s) => s['id']?.toString() == e['salon_id']?.toString()))
              .toList()
          : [];

      if (visibleSalons.isEmpty && extraEnquiries.isEmpty) {
        return _buildNothingInFilter();
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          for (final enquiry in extraEnquiries) _buildEnquiryCard(enquiry),
          for (final salon in visibleSalons) _buildSalonCard(salon),
        ],
      );
    }

    // _filter == null (All)
    final hasItems = _salons.isNotEmpty ||
        _enquiries.isNotEmpty ||
        _assignedSalons.isNotEmpty ||
        _alerts.isNotEmpty ||
        _store.queuedCount > 0;
    if (!hasItems) {
      return _buildNothingInFilter();
    }

    // Deduplicate: enquiries whose salon is already in _salons
    final deduplicatedEnquiries = _enquiries.where((e) {
      final salonId = e['salon_id']?.toString();
      final enquiryId = e['id']?.toString();
      return !_salons.any((s) =>
          (salonId != null && s['id']?.toString() == salonId) ||
          (enquiryId != null && s['enquiry_id']?.toString() == enquiryId));
    }).toList();

    final hasMultipleSections =
        (deduplicatedEnquiries.isNotEmpty || _assignedSalons.isNotEmpty) && _salons.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        if (_store.queuedCount > 0) _buildQueueBanner(),
        if (_alerts.isNotEmpty) _buildAlertsSection(),
        if (deduplicatedEnquiries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Text(
              deduplicatedEnquiries.length == 1
                  ? '1 salon to onboard'
                  : '${deduplicatedEnquiries.length} salons to onboard',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          for (final raw in deduplicatedEnquiries)
            _buildEnquiryCard(Map<String, dynamic>.from(raw as Map)),
        ],
        if (_assignedSalons.isNotEmpty) _buildAssignedSalonsSection(),
        if (_salons.isNotEmpty) ...[
          if (hasMultipleSections)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Text(
                _salons.length == 1
                    ? '1 submitted salon'
                    : '${_salons.length} submitted salons',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          for (final raw in _salons)
            _buildSalonCard(Map<String, dynamic>.from(raw as Map)),
        ],
      ],
    );
  }

  Widget _buildEnquiryCard(Map<String, dynamic> enquiry) {
    final id = enquiry['id'].toString();
    final draft = _store.forEnquiry(id);
    final needsCorrection = enquiry['needs_correction'] == true;
    final palette = context.colors;
    final phone = enquiry['phone']?.toString();
    final salonName = enquiry['salon_name']?.toString() ?? 'the salon';

    return CollaboratorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  enquiry['salon_name']?.toString() ?? 'Unknown salon',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              _statusChip(needsCorrection, draft),
            ],
          ),
          const SizedBox(height: 12),

          _detail(
            Icons.person_outline,
            enquiry['owner_name']?.toString() ?? 'Unknown owner',
          ),
          _detail(
            Icons.phone_outlined,
            phone ?? 'No phone',
          ),
          _detail(
            Icons.location_city_outlined,
            enquiry['city']?.toString() ?? 'Unknown city',
          ),

          if ((enquiry['message']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                enquiry['message'].toString(),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],

          if (needsCorrection &&
              (enquiry['rejection_reason']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.dangerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: palette.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SuperAdmin sent this back: ${enquiry['rejection_reason']}',
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

          if (draft?.lastError != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last submission was refused: ${draft!.lastError}',
              style: TextStyle(fontSize: 12, color: palette.danger),
            ),
          ],

          const SizedBox(height: 14),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                draft != null
                    ? 'Draft saved ${_ago(draft.updatedAt)}'
                    : 'Assigned ${_assignedOn(enquiry['assigned_at'])}',
                style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
              ),
              if (phone != null && phone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _callOwner(phone, salonName),
                  icon: const Icon(Icons.call, size: 14),
                  label: const Text('Call', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openOnboarding(enquiry),
              icon: Icon(
                needsCorrection
                    ? Icons.edit_outlined
                    : draft != null
                        ? Icons.play_arrow_rounded
                        : Icons.rocket_launch_outlined,
                size: 19,
              ),
              label: Text(
                needsCorrection
                    ? 'Fix and resubmit'
                    : draft != null
                        ? 'Continue onboarding'
                        : 'Start onboarding',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppTheme.accentColor,
                foregroundColor: palette.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(bool needsCorrection, OnboardingDraft? draft) {
    final palette = context.colors;

    final (label, colour) = switch (true) {
      _ when needsCorrection => ('Needs fixing', palette.danger),
      _ when draft != null && draft.isComplete => (
        'Ready to send',
        palette.warning,
      ),
      _ when draft != null => ('In progress', palette.info),
      _ => ('Assigned', AppTheme.accentColor),
    };

    return CollaboratorChip(label: label, colour: colour);
  }

  Widget _detail(IconData icon, String text) {
    final palette = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.textTertiary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  static String _assignedOn(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null
        ? 'recently'
        : 'on ${DateFormat('d MMM yyyy').format(parsed.toLocal())}';
  }

  static String _ago(DateTime when) {
    final gap = DateTime.now().difference(when);

    if (gap.inMinutes < 1) return 'just now';
    if (gap.inHours < 1) return '${gap.inMinutes} min ago';
    if (gap.inDays < 1) return '${gap.inHours}h ago';
    return 'on ${DateFormat('d MMM').format(when)}';
  }

  Widget _buildAssignedSalonsSection() {
    final palette = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.how_to_reg_outlined, size: 17, color: palette.info),
            const SizedBox(width: 8),
            Text(
              _assignedSalons.length == 1
                  ? '1 salon in your care'
                  : '${_assignedSalons.length} salons in your care',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Already registered by their owners. SuperAdmin put you on them — no onboarding needed.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: palette.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        for (final raw in _assignedSalons)
          _buildAssignedSalonCard(Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }

  Widget _buildAssignedSalonCard(Map<String, dynamic> salon) {
    final needsPlan = salon['needs_plan'] == true;
    final daysLeft = salon['days_left'] as int?;
    final noServices = (salon['services_count'] ?? 0) == 0;
    final palette = context.colors;

    return CollaboratorCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [salon['address'], salon['city']]
                          .where((p) => p != null && p.toString().isNotEmpty)
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${salon['owner_name'] ?? 'Owner'} · '
                      '${salon['services_count'] ?? 0} '
                      '${salon['services_count'] == 1 ? 'service' : 'services'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (needsPlan ||
              noServices ||
              (daysLeft != null && daysLeft <= 7)) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (needsPlan)
                  CollaboratorChip(
                    label: 'No plan chosen yet',
                    colour: palette.warning,
                  ),
                if (daysLeft != null && daysLeft <= 7)
                  CollaboratorChip(
                    label: daysLeft <= 0
                        ? 'Plan ends today'
                        : 'Plan ends in $daysLeft days',
                    colour: palette.danger,
                  ),
                if (noServices)
                  CollaboratorChip(
                    label: 'Menu is empty',
                    colour: palette.info,
                  ),
              ],
            ),
          ] else if (salon['plan_name'] != null) ...[
            const SizedBox(height: 11),
            CollaboratorChip(
              label: 'On ${salon['plan_name']}',
              colour: palette.success,
            ),
          ],

          const SizedBox(height: 12),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _callOwner(
                salon['owner_phone']?.toString(),
                salon['name']?.toString() ?? 'the salon',
              ),
              icon: const Icon(Icons.call, size: 16),
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
                  ? '1 salon needs a call'
                  : '${_alerts.length} salons need a call',
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
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final lapsed = alert['severity'] == 'lapsed';
    final palette = context.colors;
    final colour = lapsed ? palette.danger : palette.warning;

    return CollaboratorCard(
      padding: const EdgeInsets.all(14),
      color: lapsed ? palette.dangerBg : palette.warningBg,
      borderColor: colour.withValues(alpha: 0.3),
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
                    color: palette.textSecondary,
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

  Widget _buildQueueBanner() {
    final palette = context.colors;
    final warning = palette.warning;

    return CollaboratorCard(
      padding: const EdgeInsets.all(14),
      color: palette.warningBg,
      borderColor: warning.withValues(alpha: 0.3),
      child: Row(
        children: [
          if (_store.isSyncing)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: warning),
            )
          else
            Icon(Icons.cloud_upload_outlined, size: 20, color: warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _store.isSyncing
                  ? 'Sending ${_store.queuedCount} finished ${_store.queuedCount == 1 ? 'salon' : 'salons'}…'
                  : '${_store.queuedCount} finished ${_store.queuedCount == 1 ? 'salon is' : 'salons are'} '
                      'waiting for a connection. They will send themselves.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: warning),
            ),
          ),
          if (!_store.isSyncing)
            TextButton(
              onPressed: _store.sync,
              style: TextButton.styleFrom(
                foregroundColor: warning,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

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
      onTap: canEdit
          ? () => _edit(salon)
          : expandableFor(salon)
              ? () => _toggleExpanded(id)
              : null,
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
                      'Submitted ${_submittedOn(salon['submitted_at'] ?? salon['registered_at'])}',
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
                    '${salon['services_count'] == 1 ? 'service' : 'services'} priced',
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

  bool expandableFor(Map<String, dynamic> salon) => salon['can_edit'] != true;

  void _toggleExpanded(String? id) {
    if (id == null) return;
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  bool _isUrgent(Map<String, dynamic> salon) {
    if (!_isApproved(salon['status']?.toString())) return false;
    if (salon['lapsed'] == true) return true;
    final days = (salon['days_left'] as num?)?.toInt();
    return days != null && days <= _urgentDays;
  }

  (String, Color, IconData)? _subscriptionLook(Map<String, dynamic> salon) {
    if (!_isApproved(salon['status']?.toString())) return null;
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

    return days == 1 ? 'Last day$date' : '$days days left$date';
  }

  (String, Color, IconData) _statusLook(String status) {
    final palette = context.colors;

    if (_isApproved(status)) {
      return (
        'Approved & live',
        palette.success,
        Icons.check_circle_outline,
      );
    }
    if (_isRejected(status)) {
      return ('Sent back', palette.danger, Icons.error_outline);
    }
    if (status.toLowerCase().trim() == 'suspended' || status.toLowerCase().trim() == 'deactivated') {
      return (
        'Suspended',
        palette.textSecondary,
        Icons.pause_circle_outline,
      );
    }
    return ('Waiting on SuperAdmin', palette.warning, Icons.hourglass_empty);
  }

  static String _submittedOn(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null
        ? 'recently'
        : DateFormat('d MMM yyyy').format(parsed.toLocal());
  }

  Widget _buildNothingInFilter() {
    final filterName = _filters[_filter] ?? 'selected';
    final (icon, title, body) = switch (_filter) {
      'assigned' => (
        Icons.inbox_outlined,
        'No assigned salons',
        'No salons are currently assigned to you for onboarding or care.',
      ),
      'pending_approval' => (
        Icons.hourglass_empty,
        'No pending salons',
        'No submitted salons are currently waiting for SuperAdmin approval.',
      ),
      'active' => (
        Icons.check_circle_outline,
        'No approved salons',
        'No salons have completed onboarding and gone live yet.',
      ),
      'rejected' => (
        Icons.error_outline,
        'No salons sent back',
        'No salons currently need corrections or fixes.',
      ),
      _ => (
        Icons.filter_alt_off_outlined,
        'Nothing ${filterName.toLowerCase()}',
        'No salons match this filter at the moment.',
      ),
    };

    return CollaboratorEmptyState(
      icon: icon,
      title: title,
      body: body,
      actionLabel: 'Show all',
      onAction: () => setState(() => _filter = null),
    );
  }

  Widget _buildEmptyState() {
    return CollaboratorEmptyState(
      icon: Icons.storefront_outlined,
      title: 'No salons yet',
      body:
          'Salons assigned to you or submitted by you will appear here with their status.',
      actionLabel: 'Onboard New Salon',
      onAction: () async {
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => const OnboardSalonScreen(),
          ),
        );
        if (saved == true) await _fetch();
      },
    );
  }
}
