import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

    return CollaboratorCard(
      onTap: canEdit ? () => _edit(salon) : null,
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
                        color: context.colors.textPrimary,
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
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CollaboratorChip(
                      label: statusLabel,
                      colour: statusColour,
                      icon: statusIcon,
                    ),
                  ],
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
                color: context.colors.dangerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 15,
                    color: context.colors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rejectionReason,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.colors.danger,
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
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Submitted ${_submittedOn(salon['submitted_at'])}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textTertiary,
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
                    backgroundColor: context.colors.accentSoft,
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
                      color: context.colors.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Handed over',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
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
