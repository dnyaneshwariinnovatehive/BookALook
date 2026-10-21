import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/collaborator_api.dart';
import '../../../services/collaborator_badges.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/collaborator/collaborator_card.dart';
import '../../../widgets/collaborator/collaborator_chip.dart';
import '../../../widgets/collaborator/collaborator_empty_state.dart';
import '../../../widgets/collaborator/collaborator_skeleton.dart';
import '../../../widgets/collaborator/collaborator_thumb.dart';

/// 3rd tab: Approved Salons.
///
/// Displays ONLY salons that have been explicitly approved by SuperAdmin
/// and are associated with the currently logged-in collaborator.
class CollaboratorApprovedTab extends StatefulWidget {
  /// Counts the bottom navigation badges are drawn from.
  final CollaboratorBadges? badges;

  /// Navigates to the My Salons tab to view all submissions and their statuses.
  final VoidCallback? onGoToMySalons;

  const CollaboratorApprovedTab({
    super.key,
    this.badges,
    this.onGoToMySalons,
  });

  @override
  State<CollaboratorApprovedTab> createState() => CollaboratorApprovedTabState();
}

class CollaboratorApprovedTabState extends State<CollaboratorApprovedTab> {
  bool _isLoading = true;
  bool _firstLoad = true;
  String? _errorMessage;
  List<dynamic> _salons = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// Reloads approved salons. Called by the shell when tab is tapped or re-selected.
  Future<void> reload() => _fetch();

  @visibleForTesting
  void seedForTest(List<dynamic> salons) {
    setState(() {
      _salons = salons;
      _isLoading = false;
      _firstLoad = false;
      _errorMessage = null;
    });
    widget.badges?.reportApproved(_salons.length);
  }

  Future<void> _fetch() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final salons = await CollaboratorApi.approvedSalons();

      if (!mounted) return;
      setState(() {
        _salons = salons;
        _errorMessage = null;
      });

      widget.badges?.reportApproved(_salons.length);
    } catch (e) {
      debugPrint('Error fetching approved salons: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e is HttpException
              ? e.message
              : 'Unable to load approved salons. Please check your internet connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _firstLoad = false;
        });
      }
    }
  }

  Future<void> _callOwner(String? phone, String salonName) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text('No phone number on file for $salonName.'),
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone.trim());
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

    if (_errorMessage != null && _salons.isEmpty) {
      return _buildErrorState();
    }

    if (_salons.isEmpty) {
      return _buildEmptyState();
    }

    final palette = context.colors;

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppTheme.accentColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.verified, size: 18, color: palette.success),
                const SizedBox(width: 8),
                Text(
                  _salons.length == 1
                      ? '1 approved salon live on platform'
                      : '${_salons.length} approved salons live on platform',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          for (final raw in _salons)
            _buildSalonCard(Map<String, dynamic>.from(raw as Map)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return CollaboratorEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Could not load approved salons',
      body: _errorMessage ?? 'Something went wrong while connecting to the server.',
      actionLabel: 'Retry',
      onAction: _fetch,
    );
  }

  Widget _buildEmptyState() {
    return CollaboratorEmptyState(
      icon: Icons.verified_outlined,
      title: 'No approved salons yet',
      body:
          'Salons you onboard will appear here once they have been reviewed and explicitly approved by SuperAdmin.',
      actionLabel: 'View My Salons',
      onAction: widget.onGoToMySalons,
    );
  }

  Widget _buildSalonCard(Map<String, dynamic> salon) {
    final palette = context.colors;
    final name = salon['name']?.toString() ?? 'Unnamed Salon';
    final city = salon['city']?.toString();
    final address = salon['address']?.toString();
    final locationText = [address, city]
        .where((p) => p != null && p.isNotEmpty)
        .join(', ');

    final approvedAtRaw = salon['approved_at'];
    final approvedDateText = _formatApprovedDate(approvedAtRaw);
    final servicesCount = (salon['services_count'] as num?)?.toInt() ?? 0;
    final planName = salon['plan_name']?.toString();
    final daysLeft = (salon['days_left'] as num?)?.toInt();
    final lapsed = salon['lapsed'] == true;
    final needsPlan = salon['needs_plan'] == true;
    final ownerName = salon['owner_name']?.toString() ?? 'Owner';
    final ownerPhone = salon['owner_phone']?.toString();

    return CollaboratorCard(
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
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (locationText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        locationText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        CollaboratorChip(
                          label: 'Approved & live',
                          colour: palette.success,
                          icon: Icons.check_circle_outline,
                        ),
                        if (approvedDateText != null)
                          CollaboratorChip(
                            label: approvedDateText,
                            colour: palette.textSecondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Plan & services status
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (servicesCount > 0)
                CollaboratorChip(
                  label: servicesCount == 1 ? '1 service' : '$servicesCount services',
                  colour: palette.textSecondary,
                  icon: Icons.content_cut_outlined,
                )
              else
                CollaboratorChip(
                  label: 'No services priced',
                  colour: palette.warning,
                  icon: Icons.info_outline,
                ),
              if (planName != null && planName.isNotEmpty)
                CollaboratorChip(
                  label: 'Plan: $planName',
                  colour: palette.success,
                  icon: Icons.card_membership_outlined,
                )
              else if (needsPlan)
                CollaboratorChip(
                  label: 'Needs plan selected',
                  colour: palette.warning,
                  icon: Icons.payment_outlined,
                ),
              if (lapsed)
                CollaboratorChip(
                  label: 'Plan lapsed',
                  colour: palette.danger,
                  icon: Icons.error_outline,
                )
              else if (daysLeft != null && daysLeft <= 7)
                CollaboratorChip(
                  label: daysLeft <= 0 ? 'Plan ends today' : '$daysLeft days left',
                  colour: palette.danger,
                  icon: Icons.timer_outlined,
                ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 6),

          // Owner contact and call action
          Row(
            children: [
              Icon(Icons.person_outline, size: 15, color: palette.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _callOwner(ownerPhone, name),
                icon: const Icon(Icons.call, size: 15),
                label: Text(
                  'Call $ownerName',
                  style: const TextStyle(fontSize: 12.5),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String? _formatApprovedDate(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return 'Approved ${DateFormat('d MMM yyyy').format(parsed.toLocal())}';
  }
}
