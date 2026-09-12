import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/collaborator_api.dart';
import '../../../services/onboarding_draft_store.dart';
import '../../../theme/app_theme.dart';
import '../../collaborator/onboard_salon_screen.dart';

/// Everything this collaborator has submitted, and what SuperAdmin did with it.
///
/// Two jobs. First, accountability in one direction: a collaborator should
/// never have to ask anyone whether a salon they set up went live. Second, it
/// is where editing happens — a salon can be corrected right up to the moment
/// it is approved, and never after, so the edit button disappears at exactly
/// the point the salon stops being theirs.
class CollaboratorOnboardedTab extends StatefulWidget {
  const CollaboratorOnboardedTab({super.key});

  @override
  State<CollaboratorOnboardedTab> createState() => _CollaboratorOnboardedTabState();
}

class _CollaboratorOnboardedTabState extends State<CollaboratorOnboardedTab> {
  bool _isLoading = true;
  List<dynamic> _salons = [];

  /// null = everything. Otherwise the salon status being shown.
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

  Future<void> _fetch() async {
    // Anything finished but unsent should go before the collaborator concludes
    // from a short list that their afternoon vanished.
    await OnboardingDraftStore.instance.sync();

    try {
      final salons = await CollaboratorApi.onboardedSalons();
      if (mounted) setState(() => _salons = salons);
    } catch (e) {
      debugPrint('Error fetching onboarded salons: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_salons.isEmpty) return _buildEmptyState();

    final visible = _visible;

    return RefreshIndicator(
      onRefresh: _fetch,
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
              _filterChip(entry.key, entry.value),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _filterChip(String? status, String label) {
    final selected = _filter == status;
    final count = _countOf(status);

    return GestureDetector(
      onTap: () => setState(() => _filter = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppTheme.accentColor : AppTheme.lightBorder),
        ),
        child: Text(
          '$label · $count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? Colors.white : AppTheme.lightTextBody,
          ),
        ),
      ),
    );
  }

  Widget _buildSalonCard(Map<String, dynamic> salon) {
    final status = salon['status']?.toString() ?? 'pending_approval';
    final (label, colour, icon) = _statusLook(status);
    final canEdit = salon['can_edit'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCover(salon['cover_photo_url']?.toString()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(salon['name']?.toString() ?? 'Salon',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        [salon['address'], salon['city']]
                            .where((p) => p != null && p.toString().isNotEmpty)
                            .join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.lightTextBody),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: colour.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 12, color: colour),
                            const SizedBox(width: 5),
                            Text(label,
                                style: TextStyle(
                                    color: colour,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if ((salon['rejection_reason']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.lightDangerBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppTheme.lightDanger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(salon['rejection_reason'].toString(),
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: AppTheme.lightDanger)),
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
                        style: const TextStyle(
                            fontSize: 11.5, color: AppTheme.lightTextBody),
                      ),
                      const SizedBox(height: 2),
                      Text('Submitted ${_submittedOn(salon['submitted_at'])}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.lightTextLight)),
                    ],
                  ),
                ),
                if (canEdit)
                  OutlinedButton.icon(
                    onPressed: () => _edit(salon),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: Text(status == 'rejected' ? 'Fix' : 'Edit',
                        style: const TextStyle(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                      side: const BorderSide(color: AppTheme.accentColor),
                      visualDensity: VisualDensity.compact,
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    ),
                  )
                else
                  // Approved: the salon now belongs to its owner, and saying so
                  // is kinder than a button that would be refused.
                  const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 13, color: AppTheme.lightTextLight),
                      SizedBox(width: 5),
                      Text('Handed over',
                          style: TextStyle(
                              fontSize: 11.5, color: AppTheme.lightTextLight)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(String? url) {
    const size = 62.0;

    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.lightAccentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.storefront_outlined, color: AppTheme.accentColor),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: AppTheme.lightAccentSoft,
          child: const Icon(Icons.storefront_outlined, color: AppTheme.accentColor),
        ),
      ),
    );
  }

  /// Salon status as the collaborator experiences it, not as the column spells
  /// it.
  static (String, Color, IconData) _statusLook(String status) => switch (status) {
        'active' => ('Approved & live', AppTheme.lightSuccess, Icons.check_circle_outline),
        'rejected' => ('Sent back', AppTheme.lightDanger, Icons.error_outline),
        'suspended' => ('Suspended', AppTheme.lightTextBody, Icons.pause_circle_outline),
        _ => ('Waiting on SuperAdmin', AppTheme.lightWarning, Icons.hourglass_empty),
      };

  static String _submittedOn(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? 'recently' : DateFormat('d MMM yyyy').format(parsed.toLocal());
  }

  Widget _buildNothingInFilter() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Nothing ${_filters[_filter]!.toLowerCase()} right now.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppTheme.lightTextBody),
          ),
        ),
      );

  Widget _buildEmptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fact_check_outlined,
                  size: 72, color: AppTheme.lightTextLight),
              const SizedBox(height: 20),
              const Text('Nothing submitted yet',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Salons you onboard show up here with their approval status, so you '
                'always know which ones went live.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.lightTextBody),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _fetch,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
}
