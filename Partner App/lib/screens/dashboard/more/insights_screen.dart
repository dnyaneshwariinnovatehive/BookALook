import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/insights_api.dart';
import '../../../theme/app_theme.dart';
import '../services/add_combo_screen.dart';
import 'upgrade_plan_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the salon's own bookings say about it.
///
/// Written for a salon owner between customers, not for an analyst. That drives
/// every decision here:
///
///  - Findings come before figures. "Twelve of your regulars have stopped
///    coming in" is worth more than a repeat-rate percentage, and it is the
///    first thing on the screen after the headline.
///  - Every finding that can be acted on carries the button that acts on it.
///    An insight that leaves the owner to work out what to do with it is only
///    half delivered.
///  - No number appears without saying whether it is good. A bare "93.8%"
///    means nothing to someone who has never seen another salon's figure.
///  - Money reads the way it is written in India — ₹1,45,950, not ₹145,950.
///
/// The data contract is unchanged; this is a rearrangement of the same API
/// response.
class InsightsScreen extends StatefulWidget {
  final String salonId;

  /// Loads the insights for a history window; defaults to the API.
  /// Injectable for tests.
  final Future<SalonInsights> Function(int days)? load;

  const InsightsScreen({super.key, required this.salonId, this.load});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

/// One thing the owner could do today, and the button that starts it.
class _Action {
  final IconData icon;
  final Color colour;
  final String title;
  final String detail;
  final String? cta;
  final VoidCallback? onTap;

  const _Action({
    required this.icon,
    required this.colour,
    required this.title,
    required this.detail,
    this.cta,
    this.onTap,
  });
}

class _InsightsScreenState extends State<InsightsScreen> {
  SalonInsights? _insights;
  bool _loading = true;
  String? _error;

  /// History window for the period comparison. Only Growth can change it.
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final insights = await (widget.load ?? (days) => InsightsApi.fetch(widget.salonId, days: days))(_days);
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is InsightsUnavailable
            ? e.message
            : 'Could not reach the server. Check your connection and pull down to try again.';
        _loading = false;
      });
    }
  }

  /// Open the combo form with the suggested pair already ticked.
  ///
  /// Reloads on the way back so a pair that has just been packaged stops being
  /// offered as a suggestion — the screen would otherwise keep recommending
  /// work the owner has already done.
  Future<void> _openNewCombo({
    List<String>? serviceIds,
    String? name,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddComboScreen(
          salonId: widget.salonId,
          preselectedServiceIds: serviceIds,
          suggestedName: name,
        ),
      ),
    );

    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final insights = _insights;

    return Scaffold(
      backgroundColor: dark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: Text('Your Business',
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
                  if (_error != null) _errorCard(),
                  if (insights != null) ..._sections(insights, dark),
                ],
              ),
      ),
    );
  }

  List<Widget> _sections(SalonInsights insights, bool dark) {
    final actions = _actionsFor(insights);

    return [
      _headline(insights, dark),
      const SizedBox(height: 20),

      // The centre of the screen. Everything below it is the evidence.
      if (actions.isNotEmpty) ...[
        _heading('Do this next', 'Based on what your bookings show'),
        ...actions.map((action) => _actionCard(action, dark)),
        const SizedBox(height: 10),
      ],

      // Growth: this period against the one before.
      _heading('This period vs the last', 'Revenue, visits and customers compared'),
      if (insights.period != null)
        _periodCard(insights, insights.period!, dark)
      else if (insights.isLocked('period'))
        _lockedTile(insights, 'period', dark),

      // ------------------------------------------------ know your salon
      _heading('Last 30 days', 'Revenue by week and how each provider did'),
      _basicAnalyticsCard(insights, dark),

      if (insights.retentionFunnel != null) ...[
        _heading('Do customers come back?', 'What share of first-timers return'),
        _retentionFunnelCard(insights.retentionFunnel!, dark),
      ],

      if (insights.services.isNotEmpty) ...[
        _heading('What sells', 'Your most booked services'),
        _servicesCard(insights.services, dark),
      ],

      if (insights.upsell.isNotEmpty) ...[
        _heading('Upsell tips', 'Trade-ups your customers already make'),
        _upsellCard(insights.upsell, dark),
      ],
      if (insights.isLocked('upsell_advanced')) _lockedTile(insights, 'upsell_advanced', dark),

      if (insights.crossSell.isNotEmpty) ...[
        _heading('Often booked together', 'Pairs your customers already choose themselves'),
        _pairsCard(insights.crossSell, dark),
      ],
      if (insights.isLocked('cross_sell_advanced')) _lockedTile(insights, 'cross_sell_advanced', dark),

      // ------------------------------------------------ grow your revenue
      ..._growthSection(insights, dark, 'peak_hours', 'When you are busy', 'Your quiet times are where the easy wins are',
          insights.peakHours == null ? null : _busyCard(insights.peakHours!, dark)),
      ..._growthSection(insights, dark, 'repeat_customers', 'Your customers', 'Who comes back, and who has drifted away',
          insights.repeatCustomers == null ? null : _customersCard(insights.repeatCustomers!, dark)),
      ..._growthSection(insights, dark, 'win_back', 'Win them back', 'Regulars who stopped coming. A quick call often brings them back',
          insights.winBack.isEmpty ? null : _winBackCard(insights.winBack, dark)),
      ..._growthSection(insights, dark, 'visit_gap', 'Average bill & visit gap', 'What a visit is worth and how often customers return',
          insights.visitGap == null ? null : _visitGapCard(insights.visitGap!, dark)),
      ..._growthSection(insights, dark, 'gender_mix', 'Customer mix', 'Who each service is booked for',
          insights.genderMix == null || insights.genderMix!.overall.total == 0 ? null : _genderCard(insights.genderMix!, dark)),
      ..._growthSection(insights, dark, 'staff_deep_dive', 'Staff deep-dive', 'Last 90 days, per provider',
          insights.staffDeepDive.isEmpty ? null : _staffDeepCard(insights.staffDeepDive, dark)),
      ..._growthSection(insights, dark, 'areas', 'Where your customers live', 'Useful when you want to reach one neighbourhood',
          insights.areas.isEmpty ? null : _areasCard(insights.areas, dark)),
      ..._growthSection(insights, dark, 'upsell_links', 'Your upsell links', 'How often the add-ons you set up are actually taken',
          insights.upsellLinks.isEmpty ? null : _upsellLinksCard(insights.upsellLinks, dark)),
      ..._growthSection(insights, dark, 'slow_services', 'Services losing bookings', 'Last 30 days against the 30 before',
          insights.slowServices.isEmpty ? null : _slowServicesCard(insights.slowServices, dark)),
      // Quiet-hour ideas and combos already sit in "Do this next"; here they
      // only show as locked, so Starter sees what Growth adds.
      if (insights.isLocked('quiet_hour_offers')) _lockedTile(insights, 'quiet_hour_offers', dark),
      if (insights.isLocked('recommended_combos')) _lockedTile(insights, 'recommended_combos', dark),

      if (insights.locked.isNotEmpty) ...[
        const SizedBox(height: 4),
        _lockedCard(insights.locked, dark),
      ],
    ];
  }

  /// A Growth section: its card when the plan includes it and there is data,
  /// a locked tile when the plan does not, and nothing when there is simply
  /// nothing to show yet.
  List<Widget> _growthSection(
    SalonInsights insights,
    bool dark,
    String key,
    String title,
    String subtitle,
    Widget? card,
  ) {
    if (card != null) return [_heading(title, subtitle), card];
    if (insights.isLocked(key)) return [_lockedTile(insights, key, dark)];
    return const [];
  }

  Future<void> _openUpgrade() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UpgradePlanScreen(salonId: widget.salonId)),
    );
    if (mounted) _load();
  }

  // ---------------------------------------------------------------- headline

  /// Three numbers, each with a plain sentence saying whether it is good.
  Widget _headline(SalonInsights insights, bool dark) {
    final o = insights.overview;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR LAST 6 MONTHS',
              style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bigNumber('${o.customers}', 'customers served'),
              _bigNumber('₹${_inr(o.revenue)}', 'earned'),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 14),
          _verdictRow(
            Icons.autorenew,
            '${o.repeatRate.toStringAsFixed(0)} out of every 100 customers came back',
            _repeatVerdict(o.repeatRate),
          ),
          const SizedBox(height: 10),
          _verdictRow(
            Icons.receipt_long_outlined,
            'Average bill ₹${_inr(o.averageBill)}',
            'Across ${o.totalVisits} visits',
          ),
        ],
      ),
    );
  }

  Widget _bigNumber(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1)),
            ),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12.5)),
          ],
        ),
      );

  Widget _verdictRow(IconData icon, String fact, String verdict) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fact,
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(verdict,
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      );

  /// A percentage means nothing on its own to someone who has never seen
  /// another salon's.
  String _repeatVerdict(double rate) {
    if (rate >= 60) return 'That is strong — your regulars are what keep the chairs full';
    if (rate >= 40) return 'That is healthy for a salon';
    if (rate >= 25) return 'There is room here — winning back a few is cheaper than finding new ones';
    return 'Most customers are not returning. This is the biggest thing to work on';
  }

  // ----------------------------------------------------------------- actions

  /// Findings turned into things to do, most valuable first.
  List<_Action> _actionsFor(SalonInsights insights) {
    final actions = <_Action>[];

    // Salons do not send WhatsApp marketing themselves, so every action here is
    // something the owner does in the app or on the phone.
    if (insights.slowServices.isNotEmpty) {
      final slow = insights.slowServices.first;
      actions.add(_Action(
        icon: Icons.trending_down_rounded,
        colour: AppTheme.lightWarning,
        title: slow.kind == 'unbooked'
            ? '${slow.name} is not being booked'
            : '${slow.name} is losing bookings',
        detail: slow.suggestion,
      ));
    }

    if (insights.winBack.isNotEmpty) {
      final count = insights.winBack.length;
      actions.add(_Action(
        icon: Icons.phone_callback_outlined,
        colour: AppTheme.lightSuccess,
        title: '$count regular${count == 1 ? ' has' : 's have'} stopped coming',
        detail: 'They are listed under "Win them back" with their numbers. A friendly call is often all it takes.',
      ));
    }

    if (insights.quietHourOffers.isNotEmpty) {
      final quiet = insights.quietHourOffers.first;
      actions.add(_Action(
        icon: Icons.lightbulb_outline_rounded,
        colour: AppTheme.accentColor,
        title: 'Fill ${quiet.label}',
        detail: quiet.suggestion,
      ));
    }

    if (insights.recommendedCombos.isNotEmpty) {
      final combo = insights.recommendedCombos.first;

      actions.add(_Action(
        icon: Icons.auto_awesome_outlined,
        colour: AppTheme.accentColor,
        // Naming the pair in the title means the button is self-explanatory
        // before it is pressed.
        title: combo.isActionable
            ? 'Make a combo of ${combo.comboName}'
            : 'Turn a popular pair into a combo',
        detail: combo.suggestion,
        cta: combo.isActionable ? 'Create this combo' : null,
        onTap: combo.isActionable
            ? () => _openNewCombo(serviceIds: combo.serviceIds, name: combo.comboName)
            : null,
      ));
    }

    return actions;
  }

  Widget _actionCard(_Action action, bool dark) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: action.colour.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(action.icon, size: 19, color: action.colour),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(action.title,
                            style: GoogleFonts.outfit(
                                fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
                        const SizedBox(height: 5),
                        Text(action.detail,
                            style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                color: AppTheme.lightTextBody,
                                height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (action.cta != null)
              InkWell(
                onTap: action.onTap,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(15)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: dark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(action.cta!,
                          style: GoogleFonts.outfit(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: action.colour)),
                      const SizedBox(width: 5),
                      Icon(Icons.arrow_forward, size: 15, color: action.colour),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  // --------------------------------------------------------------- customers

  Widget _customersCard(RepeatCustomers repeat, bool dark) {
    final total = repeat.buckets.fold<int>(0, (sum, b) => sum + b.count);

    return _card(
      dark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...repeat.buckets.map((bucket) {
            final share = total > 0 ? bucket.count / total : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_friendlyBucket(bucket.label),
                            style: GoogleFonts.outfit(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                      Text('${bucket.count}',
                          style: GoogleFonts.outfit(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 8,
                      backgroundColor: dark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.accentColor),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (repeat.top.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Your best customers',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Worth remembering by name',
                style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextLight)),
            const SizedBox(height: 10),
            ...repeat.top.take(5).map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppTheme.lightAccentSoft,
                        child: Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentColor),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(c.name,
                            style: GoogleFonts.outfit(fontSize: 13.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${c.visits} visits',
                          style: GoogleFonts.outfit(
                              fontSize: 12, color: AppTheme.lightTextBody)),
                      const SizedBox(width: 10),
                      Text('₹${_inr(c.spend)}',
                          style: GoogleFonts.outfit(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  /// The API labels these for a report; an owner reads them on a phone.
  String _friendlyBucket(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('once')) return 'Came once and never returned';
    if (lower.contains('occasional')) return 'Come now and then';
    if (lower.contains('regular')) return 'Your regulars';
    return label;
  }

  // ------------------------------------------------------------------- busy

  /// Days first. Which day to run an offer on is a decision an owner actually
  /// makes; which hour is mostly a staffing question.
  Widget _busyCard(PeakHours peak, bool dark) {
    final busiestDay =
        peak.byDay.fold<int>(1, (max, d) => d.bookings > max ? d.bookings : max);

    return _card(
      dark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...peak.byDay.map((day) {
            final share = day.bookings / busiestDay;
            final isQuietest = day.day == peak.quietestDay;
            final isClosed = peak.closedDays.contains(day.day);

            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(day.day.substring(0, 3),
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: isQuietest ? FontWeight.w700 : FontWeight.w500,
                            color: isClosed
                                ? AppTheme.lightTextLight
                                : isQuietest
                                    ? AppTheme.lightWarning
                                    : (dark
                                        ? AppTheme.darkTextHeading
                                        : AppTheme.lightTextHeading))),
                  ),
                  Expanded(
                    child: isClosed
                        // An empty bar reads as a terrible day. It is a day the
                        // salon does not open.
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text('No bookings — closed?',
                                style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    color: AppTheme.lightTextLight,
                                    fontStyle: FontStyle.italic)),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: share.clamp(0.0, 1.0),
                              minHeight: 9,
                              backgroundColor:
                                  dark ? AppTheme.darkBorder : AppTheme.lightBorder,
                              valueColor: AlwaysStoppedAnimation(
                                  isQuietest ? AppTheme.lightWarning : AppTheme.accentColor),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(isClosed ? '—' : '${day.bookings}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isClosed ? AppTheme.lightTextLight : null)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          if (peak.busiest != null || peak.quietest != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark ? AppTheme.darkBg : AppTheme.lightBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (peak.busiest != null)
                    Expanded(
                      child: _miniFact('Busiest hour', peak.busiest!, Icons.local_fire_department_outlined),
                    ),
                  if (peak.quietest != null)
                    Expanded(
                      child: _miniFact('Quietest hour', peak.quietest!, Icons.bedtime_outlined),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniFact(String label, String value, IconData icon) => Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.lightTextBody),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextBody)),
              Text(value,
                  style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      );

  // --------------------------------------------------------------- services

  Widget _servicesCard(List<ServiceStat> services, bool dark) {
    final most = services.fold<int>(1, (max, s) => s.bookings > max ? s.bookings : max);

    return _card(
      dark,
      Column(
        children: services.take(6).map((s) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.name,
                          style: GoogleFonts.outfit(
                              fontSize: 13.5, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('₹${_inr(s.revenue)}',
                        style: GoogleFonts.outfit(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (s.bookings / most).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor:
                              dark ? AppTheme.darkBorder : AppTheme.lightBorder,
                          valueColor:
                              const AlwaysStoppedAnimation(AppTheme.accentColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${s.bookings} booked',
                        style: GoogleFonts.outfit(
                            fontSize: 11.5, color: AppTheme.lightTextBody)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Each pair the salon does not already sell as a package gets the button
  /// that creates it, with both services ticked. The pairs already packaged
  /// say so and offer nothing — there is nothing left to do with them.
  Widget _pairsCard(List<PairStat> pairs, bool dark) {
    final shown = pairs.take(6).toList();

    return _card(
      dark,
      Column(
        children: List.generate(shown.length, (index) {
          final p = shown[index];
          final last = index == shown.length - 1;

          return Container(
            padding: EdgeInsets.only(bottom: last ? 0 : 12, top: index == 0 ? 0 : 12),
            decoration: BoxDecoration(
              border: last
                  ? null
                  : Border(
                      bottom: BorderSide(
                          color: dark ? AppTheme.darkBorder : AppTheme.lightBorder)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.services.join('  +  '),
                          style: GoogleFonts.outfit(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35)),
                      const SizedBox(height: 3),
                      Text(
                        p.alreadyACombo
                            ? 'Already sold as a combo'
                            : 'Booked together ${p.bookedTogether} times',
                        style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            color: p.alreadyACombo
                                ? AppTheme.lightSuccess
                                : AppTheme.lightTextBody),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (p.alreadyACombo)
                  const Icon(Icons.check_circle,
                      size: 19, color: AppTheme.lightSuccess)
                else if (p.canBecomeCombo)
                  TextButton(
                    onPressed: () =>
                        _openNewCombo(serviceIds: p.serviceIds, name: p.comboName),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      backgroundColor:
                          dark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('Make combo',
                        style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentColor)),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _areasCard(List<AreaStat> areas, bool dark) {
    if (areas.isEmpty) return const SizedBox.shrink();
    final maxCust = areas.fold<int>(1, (max, a) => a.customers > max ? a.customers : max);

    return _card(
      dark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...areas.take(6).map((a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place, size: 14, color: AppTheme.accentColor),
                        const SizedBox(width: 6),
                        Expanded(child: Text(a.area, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold))),
                        Text('${a.customers} customer${a.customers == 1 ? '' : 's'}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (a.customers / maxCust).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: dark ? AppTheme.darkBorder : AppTheme.lightBorder,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
          Text('Walk-in customers are not counted here — only customers with the app.',
              style: GoogleFonts.outfit(
                  fontSize: 11.5, color: AppTheme.lightTextLight, height: 1.4)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- growth cards

  /// This period against the one before, with the window picker.
  Widget _periodCard(SalonInsights insights, PeriodComparison period, bool dark) => _card(
        dark,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: insights.periods.map((days) {
                final selected = days == _days;
                return ChoiceChip(
                  key: ValueKey('insights_period_$days'),
                  label: Text(days == 365 ? '1 year' : '$days days'),
                  selected: selected,
                  onSelected: selected
                      ? null
                      : (_) {
                          setState(() => _days = days);
                          _load();
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _changeTile('Revenue', '₹${_inr(period.revenue.current)}', period.revenue),
                _changeTile('Visits', '${period.visits.current.round()}', period.visits),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _changeTile('Customers', '${period.customers.current.round()}', period.customers),
                _changeTile('Average bill', '₹${_inr(period.averageBill.current)}', period.averageBill),
              ],
            ),
          ],
        ),
      );

  Widget _changeTile(String label, String value, PeriodMetric metric) {
    final change = metric.changePercent;
    final up = (change ?? 0) >= 0;
    final colour = change == null
        ? AppTheme.lightTextLight
        : (up ? AppTheme.lightSuccess : AppTheme.lightDanger);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody)),
          Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
          Row(
            children: [
              if (change != null)
                Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: colour),
              Flexible(
                child: Text(
                  change == null ? 'Nothing to compare yet' : '${change.abs().toStringAsFixed(0)}% vs before',
                  style: GoogleFonts.outfit(fontSize: 11.5, color: colour, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Upsell tips. The rupee figure is only there on the full version.
  Widget _upsellCard(List<UpsellTip> tips, bool dark) => _card(
        dark,
        Column(
          children: tips.map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up_rounded, size: 18, color: AppTheme.accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${t.from}  →  ${t.to}',
                              style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          Text('${t.evidence} customers have booked both',
                              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody)),
                        ],
                      ),
                    ),
                    if (t.uplift > 0)
                      Text('+₹${_inr(t.uplift)}',
                          style: GoogleFonts.outfit(
                              fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.lightSuccess)),
                  ],
                ),
              )).toList(),
        ),
      );

  Widget _winBackCard(List<WinBackCustomer> customers, bool dark) => _card(
        dark,
        Column(
          children: customers.take(10).map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          Text('${c.visits} visits · ₹${_inr(c.spend)} · last came ${c.daysSince} days ago',
                              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Call ${c.name}',
                      icon: const Icon(Icons.call_rounded, color: AppTheme.lightSuccess),
                      onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.phone)),
                    ),
                  ],
                ),
              )).toList(),
        ),
      );

  Widget _visitGapCard(VisitGap gap, bool dark) => _card(
        dark,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _mini('₹${_inr(gap.averageBill)}', 'Average bill'),
                _mini('₹${_inr(gap.highestBill)}', 'Highest bill'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              gap.averageGapDays == null
                  ? 'Not enough repeat visits yet to tell how often customers come back.'
                  : 'Customers who return come back about every ${gap.averageGapDays} days '
                      '(half of them within ${gap.medianGapDays}).',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.lightTextBody, height: 1.45),
            ),
          ],
        ),
      );

  Widget _genderCard(GenderMix mix, bool dark) {
    Widget bar(GenderSplit split) {
      final total = split.total == 0 ? 1 : split.total;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(split.name, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  if (split.male > 0)
                    Expanded(flex: split.male, child: Container(height: 8, color: const Color(0xFF3B82F6))),
                  if (split.female > 0)
                    Expanded(flex: split.female, child: Container(height: 8, color: const Color(0xFFEC4899))),
                  if (split.unknown > 0)
                    Expanded(flex: split.unknown, child: Container(height: 8, color: AppTheme.lightBorder)),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Men ${(split.male / total * 100).round()}% · Women ${(split.female / total * 100).round()}%'
              '${split.unknown > 0 ? ' · Not recorded ${(split.unknown / total * 100).round()}%' : ''}',
              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody),
            ),
          ],
        ),
      );
    }

    return _card(
      dark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(GenderSplit(name: 'All services', male: mix.overall.male, female: mix.overall.female, unknown: mix.overall.unknown)),
          const Divider(height: 20),
          ...mix.services.take(6).map(bar),
        ],
      ),
    );
  }

  Widget _staffDeepCard(List<StaffDeepDive> staff, bool dark) => _card(
        dark,
        Column(
          children: staff.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.name,
                              style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                        Text('₹${_inr(s.revenue)}',
                            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.completed} done · avg ₹${_inr(s.averageBill)} · '
                      '${s.repeatRate.toStringAsFixed(0)}% came back · ${s.noShows} no-show${s.noShows == 1 ? '' : 's'}',
                      style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody),
                    ),
                  ],
                ),
              )).toList(),
        ),
      );

  Widget _upsellLinksCard(List<UpsellLinkStat> links, bool dark) => _card(
        dark,
        Column(
          children: links.take(8).map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l.service}  +  ${l.upsell}',
                              style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          Text(
                            l.bookings == 0
                                ? 'No bookings of ${l.service} yet'
                                : 'Added ${l.taken} of ${l.bookings} times · ₹${_inr(l.extraRevenue)} extra',
                            style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody),
                          ),
                        ],
                      ),
                    ),
                    Text(l.takeRate == null ? '—' : '${l.takeRate!.toStringAsFixed(0)}%',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
              )).toList(),
        ),
      );

  Widget _slowServicesCard(List<SlowService> services, bool dark) => _card(
        dark,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: services.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(s.kind == 'unbooked' ? Icons.block_rounded : Icons.trending_down_rounded,
                        size: 18, color: AppTheme.lightWarning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.kind == 'unbooked'
                                ? '${s.name} · no bookings in 60 days'
                                : '${s.name} · ${s.previous30Days} → ${s.last30Days} bookings',
                            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          Text(s.suggestion,
                              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              )).toList(),
        ),
      );

  /// One Growth section the plan does not include, drawn greyed out with the
  /// reason it is worth having.
  Widget _lockedTile(SalonInsights insights, String key, bool dark) {
    final section = insights.locked.firstWhere(
      (l) => l.key == key,
      orElse: () => LockedSection(key: key, name: 'Growth feature', reason: ''),
    );

    return InkWell(
      key: ValueKey('locked_$key'),
      onTap: _openUpgrade,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 20, color: AppTheme.lightTextLight),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.name,
                      style: GoogleFonts.outfit(
                          fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.lightTextBody)),
                  if (section.reason.isNotEmpty)
                    Text(section.reason,
                        style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextLight, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('Growth',
                style: GoogleFonts.outfit(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.accentColor)),
          ],
        ),
      ),
    );
  }

  Widget _mini(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700)),
            Text(label,
                style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextBody)),
          ],
        ),
      );

  Widget _lockedCard(List<LockedSection> locked, bool dark) => Container(
        padding: const EdgeInsets.all(18),
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
                    size: 19, color: AppTheme.accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('You are not seeing everything',
                      style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentColor)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('The Growth plan adds:',
                style: GoogleFonts.outfit(
                    fontSize: 12.5, color: AppTheme.lightTextBody)),
            const SizedBox(height: 10),
            ...locked.map((section) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 15, color: AppTheme.accentColor),
                      const SizedBox(width: 9),
                      Expanded(
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
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const ValueKey('insights_upgrade'),
                onPressed: _openUpgrade,
                child: const Text('Upgrade to Growth'),
              ),
            ),
          ],
        ),
      );

  // ----------------------------------------------------------------- shared

  Widget _heading(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: GoogleFonts.outfit(
                    fontSize: 12.5, color: AppTheme.lightTextBody, height: 1.4)),
          ],
        ),
      );

  Widget _card(bool dark, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkSurface : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: child,
      );

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.lightDangerBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Insights are not available',
                style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.lightDanger)),
            const SizedBox(height: 6),
            Text(_error!,
                style: GoogleFonts.outfit(
                    fontSize: 13, color: AppTheme.lightDanger, height: 1.45)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                backgroundColor: AppTheme.lightDanger,
              ),
              child: Text('Try again',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _basicAnalyticsCard(SalonInsights insights, bool dark) {
    final analytics = insights.basicAnalytics;
    final trend = analytics?.revenueTrend;
    final weeks = trend?.weeks ?? [];
    final staff = analytics?.staffPerformance ?? [];

    final maxRevenue = weeks.fold<double>(
      1.0,
      (max, w) => w.revenue > max ? w.revenue : max,
    );

    return _card(
      dark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text('30-Day Revenue Trend',
                    style: GoogleFonts.outfit(
                        fontSize: 14.5, fontWeight: FontWeight.bold)),
              ),
              if (trend != null)
                Text(
                  '₹${_inr(trend.totalRevenue)} · ${trend.totalBookings} booked',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (weeks.isEmpty || (trend != null && trend.totalBookings == 0)) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? AppTheme.darkBg : AppTheme.lightBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(Icons.bar_chart, size: 28, color: AppTheme.lightTextLight),
                  const SizedBox(height: 6),
                  Text('No completed bookings in the last 30 days',
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.lightTextBody)),
                  const SizedBox(height: 2),
                  Text('Revenue by week will be charted here automatically',
                      style: GoogleFonts.outfit(
                          fontSize: 11.5, color: AppTheme.lightTextLight)),
                ],
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: weeks.map((w) {
                final height = maxRevenue > 0
                    ? ((w.revenue / maxRevenue) * 72.0).clamp(6.0, 72.0)
                    : 6.0;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          w.revenue > 0 ? '₹${_inr(w.revenue)}' : '₹0',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: w.revenue > 0
                                ? (dark
                                    ? AppTheme.darkTextHeading
                                    : AppTheme.lightTextHeading)
                                : AppTheme.lightTextLight,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: height,
                          width: double.infinity,
                          constraints: const BoxConstraints(maxWidth: 38),
                          decoration: BoxDecoration(
                            color: w.revenue > 0
                                ? AppTheme.accentColor
                                : (dark
                                    ? AppTheme.darkBorder
                                    : AppTheme.lightBorder),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          w.label,
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: dark
                                ? AppTheme.darkTextHeading
                                : AppTheme.lightTextHeading,
                          ),
                        ),
                        Text(
                          '${w.bookings} bks',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: AppTheme.lightTextLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const Divider(height: 32),

          Text('Staff Performance (Bookings)',
              style: GoogleFonts.outfit(
                  fontSize: 14.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          if (staff.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark ? AppTheme.darkBg : AppTheme.lightBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined,
                      size: 20, color: AppTheme.lightTextLight),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No staff performance records yet',
                            style: GoogleFonts.outfit(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          'Add staff in Staff Management and assign them to services to track individual bookings & earnings.',
                          style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: AppTheme.lightTextLight,
                              height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...staff.map((s) => _staffRow(s.name, s.bookings, s.revenue)),
          ],
        ],
      ),
    );
  }

  Widget _staffRow(String name, int bookings, double revenue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500)),
          Text('$bookings bookings', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
          Text('₹${_inr(revenue)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _retentionFunnelCard(RetentionFunnel funnel, bool dark) {
    return _card(
      dark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _funnelStep(
            funnel.firstVisits.rate,
            '${funnel.firstVisits.count} First-time visitors',
            AppTheme.accentColor.withValues(alpha: 1.0),
          ),
          const SizedBox(height: 6),
          _funnelStep(
            funnel.secondVisits.rate,
            '${funnel.secondVisits.count} Returned for a 2nd visit',
            AppTheme.accentColor.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 6),
          _funnelStep(
            funnel.thirdVisits.rate,
            '${funnel.thirdVisits.count} Returned for a 3rd visit',
            AppTheme.accentColor.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 6),
          _funnelStep(
            funnel.regularVisits.rate,
            '${funnel.regularVisits.count} Became regulars (4+ visits)',
            AppTheme.accentColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: funnel.benchmarkIsGood
                  ? (dark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFF0FDF4))
                  : (dark ? const Color(0xFF78350F).withValues(alpha: 0.25) : const Color(0xFFFFFBEB)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: funnel.benchmarkIsGood
                    ? const Color(0xFF86EFAC).withValues(alpha: 0.5)
                    : const Color(0xFFFDE68A).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  funnel.benchmarkIsGood ? Icons.insights : Icons.lightbulb_outline,
                  color: funnel.benchmarkIsGood
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFD97706),
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    funnel.benchmarkMessage,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: funnel.benchmarkIsGood
                          ? (dark ? const Color(0xFF86EFAC) : const Color(0xFF15803D))
                          : (dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309)),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _funnelStep(double percentage, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 50,
          alignment: Alignment.centerRight,
          child: Text(
            '${percentage.toStringAsFixed(percentage.truncateToDouble() == percentage ? 0 : 1)}%',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (percentage / 100.0).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  /// Indian digit grouping: ₹1,45,950 rather than ₹145,950.
  ///
  /// The last three digits group together and everything before them goes in
  /// twos, which is how every price in the country is written.
  String _inr(num value) {
    final digits = value.round().abs().toString();
    final sign = value < 0 ? '-' : '';

    if (digits.length <= 3) return '$sign$digits';

    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];

    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);

    return '$sign${groups.join(',')},$last3';
  }
}
