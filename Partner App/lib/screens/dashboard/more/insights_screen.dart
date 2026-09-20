import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/insights_api.dart';
import '../../../theme/app_theme.dart';

/// What the salon's own bookings say about it.
///
/// Ordered by what an owner can act on, not by what is easiest to compute:
/// the headline numbers, then who is slipping away, then when the chairs are
/// empty, then what to package or trade up. Locked sections sit in place rather
/// than being hidden, so the difference the Growth plan makes is visible from
/// the plan below it.
class InsightsScreen extends StatefulWidget {
  final String salonId;

  const InsightsScreen({super.key, required this.salonId});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  SalonInsights? _insights;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final insights = await InsightsApi.fetch(widget.salonId);
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your insights. Pull down to try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final insights = _insights;

    return Scaffold(
      backgroundColor: dark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: Text('Business Insights',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 18)),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null)
                    Text(_error!, style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
                  if (insights != null) ...[
                    _overview(insights, dark),
                    const SizedBox(height: 18),
                    if (insights.repeatCustomers != null)
                      _repeatCard(insights.repeatCustomers!, dark),
                    if (insights.peakHours != null) _peakCard(insights.peakHours!, dark),
                    if (insights.areas.isNotEmpty) _areasCard(insights.areas, dark),
                    if (insights.services.isNotEmpty) _servicesCard(insights.services, dark),
                    if (insights.crossSell.isNotEmpty) _crossSellCard(insights.crossSell, dark),
                    if (insights.upsell.isNotEmpty) _upsellCard(insights.upsell, dark),
                    if (insights.recommendedCombos.isNotEmpty)
                      _combosCard(insights.recommendedCombos, dark),
                    if (insights.campaigns.campaigns > 0) _campaignCard(insights.campaigns, dark),
                    if (insights.locked.isNotEmpty) _lockedCard(insights.locked, dark),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _overview(SalonInsights insights, bool dark) {
    final o = insights.overview;

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
          Text('Last 6 months',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              _headline('${o.customers}', 'Customers'),
              _headline('${o.repeatRate.toStringAsFixed(0)}%', 'Come back'),
              _headline('₹${o.averageBill.toStringAsFixed(0)}', 'Average bill'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${o.returningCustomers} of your ${o.customers} customers have been back more than once, '
            'averaging ${o.averageVisits.toStringAsFixed(1)} visits each.',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _headline(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 3),
            Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11.5)),
          ],
        ),
      );

  Widget _repeatCard(RepeatCustomers repeat, bool dark) {
    final total = repeat.buckets.fold<int>(0, (sum, b) => sum + b.count);

    return _card(
      dark,
      'Your customers',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...repeat.buckets.map((bucket) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(bucket.label,
                          style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.lightTextBody)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? bucket.count / total : 0,
                          minHeight: 7,
                          backgroundColor:
                              dark ? AppTheme.darkBorder : AppTheme.lightBorder,
                          valueColor: const AlwaysStoppedAnimation(AppTheme.accentColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${bucket.count}',
                        style: GoogleFonts.outfit(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
          // The number that justifies a reactivation campaign.
          if (repeat.atRisk > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightWarningBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${repeat.atRisk} regulars have not been in for over ${repeat.atRiskAfterDays} days. '
                'A win-back campaign is aimed exactly at them.',
                style: GoogleFonts.outfit(
                    fontSize: 12.5, color: AppTheme.lightWarning, height: 1.45),
              ),
            ),
          ],
          if (repeat.top.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Your best customers',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...repeat.top.take(5).map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(c.name, style: GoogleFonts.outfit(fontSize: 13))),
                      Text('${c.visits} visits · ₹${c.spend.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                              fontSize: 12, color: AppTheme.lightTextBody)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  /// A bar per trading hour. The quiet ones are the point — a busy Saturday
  /// fills itself and needs no offer.
  Widget _peakCard(PeakHours peak, bool dark) {
    final busiest = peak.byHour.fold<int>(1, (max, h) => h.bookings > max ? h.bookings : max);

    return _card(
      dark,
      'When you are busy',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: peak.byHour.map((hour) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: (hour.bookings / busiest * 78).clamp(2, 78).toDouble(),
                          decoration: BoxDecoration(
                            color: hour.bookings == 0
                                ? (dark ? AppTheme.darkBorder : AppTheme.lightBorder)
                                : AppTheme.accentColor
                                    .withValues(alpha: 0.35 + (hour.bookings / busiest) * 0.65),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Every third hour, or the labels collide.
                        Text(hour.hour % 3 == 0 ? '${hour.hour}' : '',
                            style: GoogleFonts.outfit(
                                fontSize: 9, color: AppTheme.lightTextLight)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (peak.busiest != null)
            _line('Busiest hour', peak.busiest!),
          if (peak.quietest != null)
            _line('Quietest open hour', peak.quietest!),
          if (peak.quietestDay != null)
            _line('Quietest day', peak.quietestDay!),
        ],
      ),
    );
  }

  Widget _areasCard(List<AreaStat> areas, bool dark) => _card(
        dark,
        'Where your customers are',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...areas.take(6).map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 14, color: AppTheme.accentColor),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.area, style: GoogleFonts.outfit(fontSize: 13))),
                      Text('${a.customers}',
                          style: GoogleFonts.outfit(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            Text('Only customers with an account and a saved area appear here.',
                style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextLight)),
          ],
        ),
      );

  Widget _servicesCard(List<ServiceStat> services, bool dark) => _card(
        dark,
        'What sells',
        Column(
          children: services.take(6).map((s) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(s.name, style: GoogleFonts.outfit(fontSize: 13))),
                  Text('${s.bookings} × ',
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: AppTheme.lightTextBody)),
                  Text('₹${s.revenue.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }).toList(),
        ),
      );

  Widget _crossSellCard(List<PairStat> pairs, bool dark) => _card(
        dark,
        'Booked together',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: pairs.take(6).map((p) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(p.services.join('  +  '),
                        style: GoogleFonts.outfit(fontSize: 13)),
                  ),
                  if (p.alreadyACombo)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.lightSuccessBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Combo',
                          style: GoogleFonts.outfit(
                              fontSize: 10, color: AppTheme.lightSuccess)),
                    ),
                  const SizedBox(width: 8),
                  Text('${p.bookedTogether}×',
                      style: GoogleFonts.outfit(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }).toList(),
        ),
      );

  Widget _upsellCard(List<UpsellTip> tips, bool dark) => _card(
        dark,
        'Worth suggesting',
        Column(
          children: tips.map((t) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: dark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading),
                        children: [
                          TextSpan(text: t.from),
                          const TextSpan(text: '  →  '),
                          TextSpan(
                              text: t.to,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  Text('+₹${t.uplift.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.lightSuccess)),
                ],
              ),
            );
          }).toList(),
        ),
      );

  Widget _combosCard(List<String> suggestions, bool dark) => _card(
        dark,
        'Combos worth creating',
        Column(
          children: suggestions.map((s) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 15, color: AppTheme.accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s,
                        style: GoogleFonts.outfit(fontSize: 12.5, height: 1.45)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );

  Widget _campaignCard(CampaignStats stats, bool dark) => _card(
        dark,
        'Your marketing',
        Column(
          children: [
            Row(
              children: [
                _mini('${stats.campaigns}', 'Campaigns'),
                _mini('${stats.sent}', 'Sent'),
                _mini('${stats.delivered}', 'Delivered'),
                _mini(stats.readRate == null ? '—' : '${stats.readRate!.toStringAsFixed(0)}%',
                    'Read'),
              ],
            ),
          ],
        ),
      );

  Widget _mini(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(label,
                style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextBody)),
          ],
        ),
      );

  Widget _lockedCard(List<LockedSection> locked, bool dark) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    size: 18, color: AppTheme.accentColor),
                const SizedBox(width: 8),
                Text('With the Growth plan',
                    style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentColor)),
              ],
            ),
            const SizedBox(height: 10),
            ...locked.map((section) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section.name,
                          style: GoogleFonts.outfit(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(section.reason,
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppTheme.lightTextBody,
                              height: 1.4)),
                    ],
                  ),
                )),
          ],
        ),
      );

  Widget _card(bool dark, String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: GoogleFonts.outfit(
                        fontSize: 12.5, color: AppTheme.lightTextBody))),
            Text(value,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
