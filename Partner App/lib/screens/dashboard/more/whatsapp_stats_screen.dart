import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../../services/insights_api.dart';

class WhatsappStatsScreen extends StatefulWidget {
  final String salonId;
  const WhatsappStatsScreen({super.key, required this.salonId});

  @override
  State<WhatsappStatsScreen> createState() => _WhatsappStatsScreenState();
}

class _WhatsappStatsScreenState extends State<WhatsappStatsScreen> {
  bool _isLoading = true;
  SalonInsights? _insights;
  
  String _selectedServiceFilter = 'Hair Coloring';
  String _selectedTimeframe = 'Last 6 months';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await InsightsApi.fetch(widget.salonId);
      if (mounted) {
        setState(() {
          _insights = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sendCampaign(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Starting WhatsApp campaign for $title...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Marketing & CRM', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.textTheme.bodyLarge?.color),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWhatsappOverview(isDark, theme),
                const SizedBox(height: 32),
                
                if (_insights?.advanced != true)
                  _buildUpgradeBanner(isDark)
                else ...[
                  _buildCustomerSegmentation(isDark),
                  const SizedBox(height: 32),
                  _buildServiceBasedTargeting(isDark, theme),
                  const SizedBox(height: 32),
                  _buildHighValueTargeting(isDark),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildWhatsappOverview(bool isDark, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_chat_read, color: AppTheme.accentColor, size: 24),
              const SizedBox(width: 8),
              Text('WhatsApp Campaigns', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Create automated promotional blasts. Broadcast stats and history will appear here once you launch a campaign.',
            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFF6366F1), size: 32),
          const SizedBox(height: 12),
          Text('Advanced CRM & Targeting', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5))),
          const SizedBox(height: 8),
          const Text(
            'Upgrade to the Growth Plan to automatically segment your customers, find VIPs, and retarget them based on past services!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSegmentation(bool isDark) {
    final buckets = _insights?.repeatCustomers?.buckets ?? [];
    final atRisk = _insights?.repeatCustomers?.atRisk ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Customer Segmentation', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Smart groups based on booking frequency.', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        
        if (atRisk > 0)
          _buildSegmentCard(
            title: 'Slipping Away',
            count: atRisk,
            description: 'Clients who haven\'t visited in over 60 days.',
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            isDark: isDark,
          ),
        
        ...buckets.map((b) => _buildSegmentCard(
          title: b.label,
          count: b.count,
          description: b.label.toLowerCase().contains('loyal') ? 'Your most frequent visitors. Reward them!' : 'Customers looking for a reason to return.',
          icon: Icons.group,
          color: AppTheme.accentColor,
          isDark: isDark,
        )),
      ],
    );
  }

  Widget _buildSegmentCard({required String title, required int count, required String description, required IconData icon, required Color color, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                      child: Text('$count clients', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: AppTheme.accentColor, size: 20),
            onPressed: () => _sendCampaign(title),
            tooltip: 'Send Campaign',
          ),
        ],
      ),
    );
  }

  Widget _buildServiceBasedTargeting(bool isDark, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Service-Based Targeting', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Filter CRM to find clients due for a specific service.', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Service', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedServiceFilter,
                          items: ['Hair Coloring', 'Facial', 'Keratin Treatment', 'Hair Spa'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) => setState(() => _selectedServiceFilter = val!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Timeframe', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedTimeframe,
                          items: ['Last 3 months', 'Last 6 months', 'Last 1 year'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) => setState(() => _selectedTimeframe = val!),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Finds clients who got $_selectedServiceFilter in the $_selectedTimeframe but haven\'t booked it again.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _sendCampaign('Service Targeting'),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Find & Message'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHighValueTargeting(bool isDark) {
    final vips = _insights?.repeatCustomers?.top ?? [];
    if (vips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('High-Value VIPs', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Your top 20% spenders.', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              ...vips.take(5).map((vip) => ListTile(
                leading: CircleAvatar(backgroundColor: const Color(0xFFFDE68A), child: Text(vip.name.substring(0, 1), style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold))),
                title: Text(vip.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${vip.visits} visits', style: const TextStyle(fontSize: 12)),
                trailing: Text('₹${vip.spend.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              )),
              const Divider(height: 1),
              TextButton.icon(
                onPressed: () => _sendCampaign('VIPs'),
                icon: const Icon(Icons.stars, color: Color(0xFFD97706)),
                label: const Text('Send VIP Offer via WhatsApp', style: TextStyle(color: Color(0xFFD97706))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
