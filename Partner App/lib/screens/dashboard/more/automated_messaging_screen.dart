import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../utils/constants.dart';
import '../../../../theme/app_theme.dart';

class AutomatedMessagingScreen extends StatefulWidget {
  final String salonId;
  const AutomatedMessagingScreen({super.key, required this.salonId});

  @override
  State<AutomatedMessagingScreen> createState() => _AutomatedMessagingScreenState();
}

class _AutomatedMessagingScreenState extends State<AutomatedMessagingScreen> {
  bool isLoading = true;
  bool isSaving = false;
  
  bool is25DaysReminderEnabled = false;
  bool isBirthdayReminderEnabled = false;

  int thisMonthSent = 0;
  int totalSent = 0;
  List<dynamic> recentMessages = [];

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('partner_token');
      final response = await http.get(
        Uri.parse('${Constants.apiBaseUrl}/partner/salons/${widget.salonId}/automated-messaging'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            is25DaysReminderEnabled = data['settings']['whatsapp_25_days_enabled'] ?? false;
            isBirthdayReminderEnabled = data['settings']['whatsapp_birthday_enabled'] ?? false;
            thisMonthSent = data['analytics']['this_month_sent'] ?? 0;
            totalSent = data['analytics']['total_sent'] ?? 0;
            recentMessages = data['analytics']['recent_messages'] ?? [];
          });
        }
      } else {
        _showError('Failed to load settings');
      }
    } catch (e) {
      _showError('Connection error while fetching settings');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    setState(() => isSaving = true);
    
    // Optimistic UI update
    setState(() {
      if (key == 'whatsapp_25_days_enabled') is25DaysReminderEnabled = value;
      if (key == 'whatsapp_birthday_enabled') isBirthdayReminderEnabled = value;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('partner_token');
      final response = await http.put(
        Uri.parse('${Constants.apiBaseUrl}/partner/salons/${widget.salonId}/automated-messaging'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          key: value,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update');
      }
    } catch (e) {
      // Rollback on failure
      setState(() {
        if (key == 'whatsapp_25_days_enabled') is25DaysReminderEnabled = !value;
        if (key == 'whatsapp_birthday_enabled') isBirthdayReminderEnabled = !value;
      });
      _showError('Failed to update settings');
    } finally {
      setState(() => isSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Automated Messaging', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAnalyticsCard(theme, isDark),
                  const SizedBox(height: 24),
                  const Text('Automations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildToggleCard(
                    theme,
                    title: '25 Days Reminder',
                    description: 'Send a WhatsApp message to customers who visited 25 days ago (no salon name included).',
                    value: is25DaysReminderEnabled,
                    onChanged: (val) => _updateSetting('whatsapp_25_days_enabled', val),
                  ),
                  const SizedBox(height: 12),
                  _buildToggleCard(
                    theme,
                    title: 'Birthday Message',
                    description: 'Send a happy birthday WhatsApp message to customers (no salon name included).',
                    value: isBirthdayReminderEnabled,
                    onChanged: (val) => _updateSetting('whatsapp_birthday_enabled', val),
                  ),
                  const SizedBox(height: 24),
                  if (recentMessages.isNotEmpty) ...[
                    const Text('Recent Messages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildRecentMessagesList(theme, isDark),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildRecentMessagesList(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        children: recentMessages.map((msg) {
          final isLast = recentMessages.last == msg;
          final template = msg['template'] == 'birthday_message' ? 'Birthday' : '25 Days';
          final phone = msg['recipient_phone'] ?? 'Unknown';
          
          return Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.accentColor.withOpacity(0.1),
                  child: Icon(
                    msg['template'] == 'birthday_message' ? Icons.cake : Icons.calendar_today,
                    color: AppTheme.accentColor,
                    size: 20,
                  ),
                ),
                title: Text(phone, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('$template Message', style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 13)),
              ),
              if (!isLast) Divider(height: 1, indent: 70),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAnalyticsCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('This Month', thisMonthSent.toString(), theme),
              Container(width: 1, height: 40, color: theme.dividerColor),
              _buildStatItem('Total Sent', totalSent.toString(), theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, ThemeData theme) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 14, color: theme.textTheme.bodyMedium?.color)),
      ],
    );
  }

  Widget _buildToggleCard(
    ThemeData theme, {
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: SwitchListTile(
        title: Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(description, style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color, height: 1.4)),
        ),
        value: value,
        activeColor: AppTheme.accentColor,
        onChanged: isSaving ? null : onChanged,
      ),
    );
  }
}
