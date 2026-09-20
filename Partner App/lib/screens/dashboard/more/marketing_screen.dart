import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/campaign_api.dart';
import '../../../theme/app_theme.dart';
import 'new_campaign_screen.dart';

/// The salon's marketing home: what is left of the allowance, and what has been
/// sent.
///
/// The allowance sits at the top rather than buried in a menu because it is the
/// thing that decides whether the button below it will work, and finding that
/// out by pressing it is a bad way to learn.
class MarketingScreen extends StatefulWidget {
  final String salonId;

  const MarketingScreen({Key? key, required this.salonId}) : super(key: key);

  @override
  State<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen> {
  CampaignOptions? _options;
  List<Campaign> _campaigns = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        CampaignApi.options(widget.salonId),
        CampaignApi.list(widget.salonId),
      ]);

      if (!mounted) return;
      setState(() {
        _options = results[0] as CampaignOptions;
        _campaigns = results[1] as List<Campaign>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your marketing. Pull down to try again.';
        _loading = false;
      });
    }
  }

  Future<void> _startNew() async {
    final options = _options;
    if (options == null) return;

    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewCampaignScreen(salonId: widget.salonId, options: options),
      ),
    );

    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final entitlement = _options?.entitlement;

    return Scaffold(
      backgroundColor: dark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: Text('WhatsApp Marketing',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 18)),
        elevation: 0,
      ),
      floatingActionButton: (entitlement?.canSend ?? false)
          ? FloatingActionButton.extended(
              onPressed: _startNew,
              backgroundColor: AppTheme.accentColor,
              icon: const Icon(Icons.campaign_outlined, color: Colors.white),
              label: Text('New campaign',
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (_error != null) _banner(_error!, AppTheme.lightDanger),
                  if (entitlement != null) _allowanceCard(entitlement, dark),
                  const SizedBox(height: 20),
                  Text('Your campaigns',
                      style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: dark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading)),
                  const SizedBox(height: 10),
                  if (_campaigns.isEmpty)
                    _emptyState(dark)
                  else
                    ..._campaigns.map((campaign) => _campaignCard(campaign, dark)),
                ],
              ),
      ),
    );
  }

  /// The month's allowance.
  ///
  /// Both counters are shown only when both actually bind. A plan capped by
  /// messages alone should not display a campaign meter reading "unlimited" —
  /// that is noise dressed up as information.
  Widget _allowanceCard(Entitlement entitlement, bool dark) {
    if (!entitlement.hasPlan) {
      return _banner(
        entitlement.reason ?? 'Marketing needs an active subscription.',
        AppTheme.lightWarning,
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('${entitlement.planName ?? "Your"} plan',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (!entitlement.campaignsUncapped)
                Expanded(
                  child: _meter(
                    'Campaigns left',
                    entitlement.campaignsRemaining,
                    entitlement.campaignLimit,
                  ),
                ),
              if (!entitlement.messagesUncapped)
                Expanded(
                  child: _meter(
                    'Messages left',
                    entitlement.messagesRemaining,
                    entitlement.messageLimit,
                  ),
                ),
              if (entitlement.campaignsUncapped && entitlement.messagesUncapped)
                Expanded(
                  child: Text('Unlimited campaigns this cycle',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14)),
                ),
            ],
          ),
          if (entitlement.cycleEnd != null) ...[
            const SizedBox(height: 10),
            Text('Resets on ${_prettyDate(entitlement.cycleEnd!)}',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
          ],
          // Not a blocker, so it is phrased as timing rather than refusal.
          if (entitlement.quietHoursNow) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.bedtime_outlined, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Quiet hours — anything you send now goes out at ${entitlement.quietEnd}:00.',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _meter(String label, int? remaining, int limit) {
    final used = limit - (remaining ?? limit);
    final fraction = limit > 0 ? (remaining ?? limit) / limit : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${remaining ?? limit}',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        Text('$used of $limit used',
            style: GoogleFonts.outfit(color: Colors.white60, fontSize: 10.5)),
      ],
    );
  }

  Widget _campaignCard(Campaign campaign, bool dark) {
    final (statusLabel, statusColor) = _status(campaign.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(campaign.name,
                    style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: dark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: GoogleFonts.outfit(
                        fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ],
          ),
          if (campaign.template != null) ...[
            const SizedBox(height: 2),
            Text(campaign.template!,
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Sent', campaign.sentCount),
              _stat('Delivered', campaign.deliveredCount),
              _stat('Read', campaign.readCount),
              if (campaign.skippedCount > 0) _stat('Skipped', campaign.skippedCount),
            ],
          ),
          if (campaign.failureReason != null) ...[
            const SizedBox(height: 10),
            Text(campaign.failureReason!,
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightWarning)),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, int value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(label,
                style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextBody)),
          ],
        ),
      );

  Widget _emptyState(bool dark) => Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: dark ? AppTheme.darkBorder : AppTheme.lightBorder, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.campaign_outlined, size: 40, color: AppTheme.lightTextLight),
            const SizedBox(height: 12),
            Text('No campaigns yet',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Send your customers an offer, remind your regulars it is time to come back, '
              'or win back the ones you have not seen in a while.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody, height: 1.5),
            ),
          ],
        ),
      );

  Widget _banner(String text, Color colour) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colour.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 13, color: colour, height: 1.4)),
      );

  (String, Color) _status(String status) => switch (status) {
        'sent' => ('Sent', AppTheme.lightSuccess),
        'sending' => ('Sending', AppTheme.accentColor),
        'scheduled' => ('Scheduled', AppTheme.lightWarning),
        'failed' => ('Failed', AppTheme.lightDanger),
        'cancelled' => ('Cancelled', AppTheme.lightTextBody),
        _ => ('Draft', AppTheme.lightTextBody),
      };

  String _prettyDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}';
  }
}
