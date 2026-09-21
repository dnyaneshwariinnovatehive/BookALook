import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/insights_api.dart';
import '../../../theme/app_theme.dart';
import '../services/add_combo_screen.dart';
import 'marketing_screen.dart';

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

  const InsightsScreen({super.key, required this.salonId});

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
        _error = e is InsightsUnavailable
            ? e.message
            : 'Could not reach the server. Check your connection and pull down to try again.';
        _loading = false;
      });
    }
  }

  void _openMarketing() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MarketingScreen(salonId: widget.salonId)),
      );

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

      if (insights.repeatCustomers != null) ...[
        _heading('Your customers', 'Who comes back, and who has drifted away'),
        _customersCard(insights.repeatCustomers!, dark),
      ],

      if (insights.peakHours != null) ...[
        _heading('When you are busy', 'Your quiet times are where the easy wins are'),
        _busyCard(insights.peakHours!, dark),
      ],

      if (insights.services.isNotEmpty) ...[
        _heading('What sells', 'Your most booked services'),
        _servicesCard(insights.services, dark),
      ],

      if (insights.crossSell.isNotEmpty) ...[
        _heading('Often booked together', 'Pairs your customers already choose themselves'),
        _pairsCard(insights.crossSell, dark),
      ],

      if (insights.areas.isNotEmpty) ...[
        _heading('Where your customers live', 'Useful when you want to reach one neighbourhood'),
        _areasCard(insights.areas, dark),
      ],

      if (insights.campaigns.campaigns > 0) ...[
        _heading('Your WhatsApp campaigns', 'How your messages have performed'),
        _marketingCard(insights.campaigns, dark),
      ],

      if (insights.locked.isNotEmpty) ...[
        const SizedBox(height: 4),
        _lockedCard(insights.locked, dark),
      ],
    ];
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
    final repeat = insights.repeatCustomers;

    // Lapsed regulars first: people who already liked the place enough to come
    // back repeatedly are the cheapest customers to recover.
    if (repeat != null && repeat.atRisk > 0) {
      actions.add(_Action(
        icon: Icons.person_search_outlined,
        colour: AppTheme.lightWarning,
        title: 'Win back ${repeat.atRisk} regular${repeat.atRisk == 1 ? '' : 's'}',
        detail:
            'They used to come in often but have not visited in over ${repeat.atRiskAfterDays} days. '
            'A short WhatsApp offer is usually enough to bring them back.',
        cta: 'Send a win-back offer',
        onTap: _openMarketing,
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

    // Defended on both sides: the server now excludes closing days, and this
    // refuses to advise an offer for a day with no bookings even if one
    // reaches here.
    final quietDay = insights.peakHours?.quietestDay;
    final quietDayBookings = insights.peakHours?.byDay
        .where((d) => d.day == quietDay)
        .fold<int>(0, (sum, d) => sum + d.bookings);

    if (quietDay != null && (quietDayBookings ?? 0) > 0) {
      actions.add(_Action(
        icon: Icons.event_available_outlined,
        colour: const Color(0xFF00897B),
        title: 'Fill up your quiet ${quietDay}s',
        detail:
            '$quietDay is your slowest day. An offer just for that day fills chairs that '
            'would otherwise sit empty.',
        cta: 'Send an offer',
        onTap: _openMarketing,
      ));
    }

    if (insights.upsell.isNotEmpty) {
      final tip = insights.upsell.first;
      actions.add(_Action(
        icon: Icons.trending_up,
        colour: AppTheme.lightSuccess,
        title: 'Suggest ${tip.to} to ${tip.from} customers',
        detail:
            'Customers who book ${tip.from} often take ${tip.to} too — it has happened '
            '${tip.evidence} times. That is ₹${_inr(tip.uplift)} more on the bill each time.',
      ));
    }

    // Only worth raising when first-timers are actually a large share.
    final once = repeat?.buckets
        .where((b) => b.label.toLowerCase().contains('once'))
        .fold<int>(0, (sum, b) => sum + b.count);

    if (once != null && once > 0 && once >= insights.overview.customers * 0.3) {
      actions.add(_Action(
        icon: Icons.waving_hand_outlined,
        colour: const Color(0xFF5E35B1),
        title: '$once customers came only once',
        detail:
            'A reminder a few weeks after a first visit is what turns a one-off into a regular.',
        cta: 'Send a reminder',
        onTap: _openMarketing,
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

  Widget _areasCard(List<AreaStat> areas, bool dark) => _card(
        dark,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...areas.take(6).map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          size: 15, color: AppTheme.accentColor),
                      const SizedBox(width: 9),
                      Expanded(
                          child: Text(a.area,
                              style: GoogleFonts.outfit(fontSize: 13.5))),
                      Text(
                          '${a.customers} customer${a.customers == 1 ? '' : 's'}',
                          style: GoogleFonts.outfit(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Text('Walk-in customers are not counted here — only customers with the app.',
                style: GoogleFonts.outfit(
                    fontSize: 11.5, color: AppTheme.lightTextLight, height: 1.4)),
          ],
        ),
      );

  Widget _marketingCard(CampaignStats stats, bool dark) => _card(
        dark,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _mini('${stats.campaigns}', 'Campaigns'),
                _mini('${stats.sent}', 'Messages'),
                _mini('${stats.delivered}', 'Delivered'),
                _mini(stats.readRate == null
                    ? '—'
                    : '${stats.readRate!.toStringAsFixed(0)}%', 'Opened'),
              ],
            ),
            if (stats.readRate != null) ...[
              const SizedBox(height: 12),
              Text(
                stats.readRate! >= 60
                    ? 'Most people are reading your messages — that is a good sign.'
                    : 'Fewer than half are being opened. Shorter messages with a clear offer usually do better.',
                style: GoogleFonts.outfit(
                    fontSize: 12.5, color: AppTheme.lightTextBody, height: 1.45),
              ),
            ],
          ],
        ),
      );

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
                Text('You are not seeing everything',
                    style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentColor)),
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
