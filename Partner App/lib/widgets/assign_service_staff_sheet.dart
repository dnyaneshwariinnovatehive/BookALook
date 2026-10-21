import 'package:flutter/material.dart';
import '../models/service_models.dart';
import '../services/service_management_api.dart';
import '../theme/app_theme.dart';

class AssignServiceStaffSheet extends StatefulWidget {
  final String salonId;
  final String serviceId;
  final String serviceName;
  final List<UnassignedServiceItem>? unassignedServices;
  final List<dynamic>? initialStaff;
  final Set<String>? initialAssignedStaffIds;

  const AssignServiceStaffSheet({
    super.key,
    required this.salonId,
    required this.serviceId,
    required this.serviceName,
    this.unassignedServices,
    this.initialStaff,
    this.initialAssignedStaffIds,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String salonId,
    required String serviceId,
    required String serviceName,
    List<UnassignedServiceItem>? unassignedServices,
    List<dynamic>? initialStaff,
    Set<String>? initialAssignedStaffIds,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssignServiceStaffSheet(
        salonId: salonId,
        serviceId: serviceId,
        serviceName: serviceName,
        unassignedServices: unassignedServices,
        initialStaff: initialStaff,
        initialAssignedStaffIds: initialAssignedStaffIds,
      ),
    );
  }

  @override
  State<AssignServiceStaffSheet> createState() => _AssignServiceStaffSheetState();
}

class _AssignServiceStaffSheetState extends State<AssignServiceStaffSheet> {
  late String _currentServiceId;
  late String _currentServiceName;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  List<dynamic> _allStaff = [];
  final Set<String> _selectedStaffIds = {};

  @override
  void initState() {
    super.initState();
    _currentServiceId = widget.serviceId;
    _currentServiceName = widget.serviceName;

    if (widget.initialStaff != null) {
      _allStaff = widget.initialStaff!;
      if (widget.initialAssignedStaffIds != null) {
        _selectedStaffIds.addAll(widget.initialAssignedStaffIds!);
      }
      _isLoading = false;
    } else {
      _fetchStaffForService(_currentServiceId);
    }
  }

  Future<void> _fetchStaffForService(String serviceId) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await ServiceManagementApi.getServiceStaff(widget.salonId, serviceId);
      if (!mounted) return;

      setState(() {
        _allStaff = data['all_staff'] as List<dynamic>? ?? [];
        _selectedStaffIds.clear();
        final assigned = data['assigned_staff_ids'] as List<dynamic>? ?? [];
        for (final id in assigned) {
          _selectedStaffIds.add(id.toString());
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _switchService(UnassignedServiceItem service) {
    if (_currentServiceId == service.id) return;
    setState(() {
      _currentServiceId = service.id;
      _currentServiceName = service.name;
    });
    _fetchStaffForService(service.id);
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedStaffIds.length < _allStaff.length) {
        for (final staff in _allStaff) {
          final id = staff['id']?.toString();
          if (id != null) _selectedStaffIds.add(id);
        }
      } else {
        _selectedStaffIds.clear();
      }
    });
  }

  Future<void> _assignStaff() async {
    if (_selectedStaffIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one staff member to assign this service.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await ServiceManagementApi.assignServiceStaff(
        widget.salonId,
        _currentServiceId,
        _selectedStaffIds.toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Service assigned to ${_selectedStaffIds.length} staff member(s)'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign staff: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _getStaffName(Map<String, dynamic> staff) {
    final user = staff['user'] as Map<String, dynamic>?;
    if (user != null) {
      final name = user['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
      final firstName = user['first_name']?.toString().trim() ?? '';
      final lastName = user['last_name']?.toString().trim() ?? '';
      final combined = '$firstName $lastName'.trim();
      if (combined.isNotEmpty) return combined;
    }
    return 'Staff Member';
  }

  bool _isAdminProvider(Map<String, dynamic> staff) {
    if (staff['is_admin_provider'] == true || staff['is_admin_provider'] == 1) {
      return true;
    }
    final user = staff['user'] as Map<String, dynamic>?;
    return user?['role'] == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = theme.colorScheme.surface;
    final textColor = theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row: Title & Close Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add_alt_1, color: AppTheme.accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assign to Staff',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Text(
                          'Add this service to service providers\' skillsets',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            // Active Service Card / Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.content_cut, size: 16, color: AppTheme.accentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Service',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white54 : Colors.black45,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentServiceName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Unassigned',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Switcher if multiple unassigned services exist
            if (widget.unassignedServices != null && widget.unassignedServices!.length > 1) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.unassignedServices!.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final item = widget.unassignedServices![index];
                      final isSelected = item.id == _currentServiceId;
                      return ChoiceChip(
                        label: Text(item.name),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) _switchService(item);
                        },
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                        selectedColor: AppTheme.accentColor,
                        backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      );
                    },
                  ),
                ),
              ),
            ],

            // Selection Controls (Counter + Select All)
            if (!_isLoading && _error == null && _allStaff.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Providers (${_selectedStaffIds.length}/${_allStaff.length} selected)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    TextButton(
                      onPressed: _toggleSelectAll,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppTheme.accentColor,
                      ),
                      child: Text(
                        _selectedStaffIds.length < _allStaff.length ? 'Select All' : 'Deselect All',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Staff List / Loading / Error Body
            Flexible(
              child: _buildStaffContent(context),
            ),

            // Bottom Action Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: ElevatedButton(
                onPressed: _isSaving || _isLoading || _allStaff.isEmpty
                    ? null
                    : _assignStaff,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _selectedStaffIds.isNotEmpty
                            ? 'Assign (${_selectedStaffIds.length} Staff)'
                            : 'Assign to Staff',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffContent(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppTheme.accentColor),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 36),
              const SizedBox(height: 8),
              Text(
                'Failed to load providers',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _fetchStaffForService(_currentServiceId),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_allStaff.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline,
                size: 44,
                color: isDark ? Colors.white30 : Colors.black26,
              ),
              const SizedBox(height: 10),
              Text(
                'No Active Service Providers',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'There are no active staff members in this salon. Add staff or enable Provider Mode for the Admin to assign services.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      itemCount: _allStaff.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final staff = _allStaff[index] as Map<String, dynamic>;
        final staffId = staff['id']?.toString() ?? '';
        final isSelected = _selectedStaffIds.contains(staffId);
        final name = _getStaffName(staff);
        final specialization = staff['specialization']?.toString() ?? 'Staff';
        final isAdmin = _isAdminProvider(staff);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedStaffIds.remove(staffId);
              } else {
                _selectedStaffIds.add(staffId);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accentColor.withValues(alpha: isDark ? 0.15 : 0.08)
                  : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppTheme.accentColor.withValues(alpha: 0.6)
                    : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Selection Checkbox
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected,
                    activeColor: AppTheme.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedStaffIds.add(staffId);
                        } else {
                          _selectedStaffIds.remove(staffId);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),

                // Avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isAdmin
                      ? Colors.deepPurple.shade100
                      : AppTheme.accentColor.withValues(alpha: 0.12),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isAdmin ? Colors.deepPurple.shade800 : AppTheme.accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Specialization
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.deepPurple.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                'Admin (Provider)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        specialization,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
