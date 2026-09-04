import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class ProviderProfileTab extends StatelessWidget {
  final Map<String, dynamic> salon;
  final Map<String, dynamic> provider;
  final Map<String, dynamic> user;
  
  const ProviderProfileTab({
    super.key, 
    required this.salon,
    required this.provider,
    required this.user,
  });

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'Closed';
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      int h = int.tryParse(parts[0]) ?? 0;
      int m = int.tryParse(parts[1]) ?? 0;
      final tod = TimeOfDay(hour: h, minute: m);
      String period = tod.hour >= 12 ? 'PM' : 'AM';
      int displayHour = tod.hour > 12 ? tod.hour - 12 : (tod.hour == 0 ? 12 : tod.hour);
      return '${displayHour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')} $period';
    }
    return timeStr;
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> services = provider['services'] ?? [];
    final List<dynamic> workingHours = provider['working_hours'] ?? [];
    
    // Sort working hours by day of week (0 = Sunday, 1 = Monday...)
    workingHours.sort((a, b) => (a['day_of_week'] as int).compareTo(b['day_of_week'] as int));

    final List<String> daysOfWeek = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Profile',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 32),
                
                // Header Profile Section
                Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.accentColor, width: 2),
                        image: const DecorationImage(
                          image: NetworkImage('https://i.pravatar.cc/150?img=11'), // Generic avatar
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['name'] ?? 'Unknown',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Service Provider',
                              style: TextStyle(color: AppTheme.accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            salon['name'] ?? 'Luxe Studio Salon',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Services Chips
                if (services.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: services.map((s) => _buildServiceChip(s['name'] ?? 'Service')).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set by salon admin',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                  ),
                  const SizedBox(height: 40),
                ],

                // Personal Information Section
                Text(
                  'Personal Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 24),
                
                _buildInfoRow(context, 'FULL NAME', user['name'] ?? '', actionIcon: Icons.lock_outline),
                Divider(height: 32, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                
                _buildInfoRow(context, 'PHONE NUMBER', user['phone'] ?? '', actionText: 'Edit'),
                Divider(height: 32, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                
                _buildInfoRow(context, 'EMAIL ADDRESS', user['email'] ?? 'Not provided', actionIcon: Icons.lock_outline),
                Divider(height: 32, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                
                _buildPhotoUploadRow(context),
                
                const SizedBox(height: 40),

                // Working Hours Section
                Text(
                  'Working Hours',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 24),
                
                if (workingHours.isEmpty)
                  Text('No working hours assigned yet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)))
                else
                  ...workingHours.asMap().entries.map((entry) {
                    final index = entry.key;
                    final hour = entry.value;
                    final isOff = hour['is_weekly_off'] == 1 || hour['is_weekly_off'] == true;
                    
                    final workTime = isOff 
                      ? 'Closed' 
                      : '${_formatTime(hour['shift_start'])} - ${_formatTime(hour['shift_end'])}';
                      
                    final breakTime = hour['break_start'] != null 
                      ? '${_formatTime(hour['break_start'])} - ${_formatTime(hour['break_end'])}'
                      : 'No break';

                    return Column(
                      children: [
                        _buildWorkingHourRow(context, daysOfWeek[hour['day_of_week']], workTime, isOff ? null : breakTime),
                        if (index < workingHours.length - 1)
                          Divider(height: 32, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                      ],
                    );
                  }),
                
                const SizedBox(height: 80), // Padding for bottom nav
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: AppTheme.accentColor, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {IconData? actionIcon, String? actionText}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
        ),
        if (actionIcon != null)
          Icon(actionIcon, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.26)),
        if (actionText != null)
          Text(
            actionText,
            style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold, fontSize: 14),
          ),
      ],
    );
  }

  Widget _buildPhotoUploadRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PHOTO',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: const DecorationImage(
                        image: NetworkImage('https://i.pravatar.cc/150?img=11'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Tap to change photo',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text(
          'Upload',
          style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildWorkingHourRow(BuildContext context, String day, String workTime, String? breakTime) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          day,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
        ),
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  workTime,
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                ),
                if (breakTime != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Break: $breakTime',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38)),
                  ),
                ]
              ],
            ),
            const SizedBox(width: 12),
            Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.26)),
          ],
        ),
      ],
    );
  }
}
