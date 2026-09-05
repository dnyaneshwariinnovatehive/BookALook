import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/services/api_config.dart';

class CollaboratorAssignedTab extends StatefulWidget {
  const CollaboratorAssignedTab({super.key});

  @override
  State<CollaboratorAssignedTab> createState() => _CollaboratorAssignedTabState();
}

class _CollaboratorAssignedTabState extends State<CollaboratorAssignedTab> {
  bool _isLoading = true;
  List<dynamic> _enquiries = [];
  final String _baseUrl = ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _fetchEnquiries();
  }

  Future<void> _fetchEnquiries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$_baseUrl/partner/collaborator/assigned-enquiries'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);
      if (data != null && data['success'] == true) {
        setState(() {
          _enquiries = data['data'] as List<dynamic>? ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching assigned enquiries: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_enquiries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_ind_outlined,
              size: 80,
              color: (theme.brightness == Brightness.dark ? AppTheme.darkWarning : AppTheme.lightWarning),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Assigned Salons',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'You currently have no new salon enquiries assigned to you. When the SuperAdmin assigns a salon, it will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.54),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchEnquiries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _enquiries.length,
        itemBuilder: (context, index) {
          final enquiry = _enquiries[index];
          final assignedAt = enquiry['assigned_at'] != null 
              ? DateTime.parse(enquiry['assigned_at']).toLocal().toString().split('.')[0] 
              : 'Unknown';

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          enquiry['salon_name'] ?? 'Unknown Salon',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Assigned',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(enquiry['owner_name'] ?? 'Unknown Owner', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(enquiry['city'] ?? 'Unknown City', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(enquiry['phone'] ?? 'No Phone', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  if (enquiry['message'] != null && enquiry['message'].toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Message:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enquiry['message'],
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Assigned on: $assignedAt',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Implement onboarding workflow
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Onboarding flow not implemented yet.')),
                        );
                      },
                      icon: const Icon(Icons.rocket_launch),
                      label: const Text('Start Onboarding'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

