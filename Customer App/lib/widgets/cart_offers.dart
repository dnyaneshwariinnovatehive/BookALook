import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';

/// The three things a cart can tell a customer about packages, in one place so
/// the salon page and the cart page say exactly the same thing.
///
/// * [AppliedComboBanner] — the cart already qualifies for a package and has
///   been priced as one.
/// * [ComboOfferCard] — one or two services away from a package, with what
///   completing it would save.
/// * [SuggestionStrip] — what this salon's customers usually book alongside.
double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

/// "Combined into Grooming Pack — you saved ₹200."
class AppliedComboBanner extends StatelessWidget {
  final List<dynamic> appliedCombos;
  final double totalSaving;

  const AppliedComboBanner({
    Key? key,
    required this.appliedCombos,
    required this.totalSaving,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (appliedCombos.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.successBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer, size: 18, color: context.colors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appliedCombos.length == 1
                      ? 'Package applied — you save ₹${totalSaving.toStringAsFixed(0)}'
                      : '${appliedCombos.length} packages applied — you save ₹${totalSaving.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: context.colors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...appliedCombos.map((raw) {
            final combo = raw as Map<String, dynamic>;
            final names = (combo['service_names'] as List?)?.join(' + ') ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    combo['name'] ?? 'Package',
                    style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary),
                  ),
                  Text(
                    names,
                    style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textSecondary),
                  ),
                  Row(
                    children: [
                      Text(
                        '₹${_toDouble(combo['list_total']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: context.colors.textTertiary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '₹${_toDouble(combo['combo_total']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.colors.success),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// "Add a Beard Trim and a Head Massage to complete Grooming Pack — save ₹200."
class ComboOfferCard extends StatelessWidget {
  final Map<String, dynamic> offer;

  /// Adds one missing service. Null while a request is in flight.
  final void Function(String serviceId)? onAddService;

  /// Adds everything still missing in one go.
  final void Function(List<String> serviceIds)? onCompletePackage;

  const ComboOfferCard({
    Key? key,
    required this.offer,
    this.onAddService,
    this.onCompletePackage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final missing = (offer['missing_services'] as List?) ?? [];
    final saving = _toDouble(offer['saving']);
    final extra = _toDouble(offer['extra_to_pay']);
    final missingIds = missing.map<String>((s) => s['id'].toString()).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard, size: 18, color: AppTheme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Complete "${offer['name']}" and save ₹${saving.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You already have ${(offer['services_in_cart'] as List?)?.join(', ') ?? ''}. '
            'Adding the rest costs ₹${extra.toStringAsFixed(0)} more.',
            style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),

          ...missing.map((raw) {
            final service = raw as Map<String, dynamic>;
            final listPrice = _toDouble(service['price']);
            final comboPrice = _toDouble(service['combo_price']);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(service['name'] ?? 'Service',
                            style: GoogleFonts.outfit(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            if (comboPrice < listPrice) ...[
                              Text('₹${listPrice.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    color: context.colors.textTertiary,
                                    decoration: TextDecoration.lineThrough,
                                  )),
                              const SizedBox(width: 5),
                            ],
                            Text('₹${comboPrice.toStringAsFixed(0)} in this package',
                                style: GoogleFonts.outfit(
                                    fontSize: 11.5, color: AppTheme.accentColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onAddService == null
                        ? null
                        : () => onAddService!(service['id'].toString()),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text('Add',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                  ),
                ],
              ),
            );
          }),

          if (missing.length > 1) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onCompletePackage == null
                    ? null
                    : () => onCompletePackage!(missingIds),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: context.colors.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text('Add all ${missing.length} and save ₹${saving.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Add-ons for the cart, the salon's own picks first.
///
/// The wording is honest about where each came from: the owner's
/// recommendation ("Salon's pick", "Goes with your Haircut"), this salon's
/// booking history ("with 40% of these bookings"), or simply the same
/// category.
class SuggestionStrip extends StatelessWidget {
  final List<dynamic> suggestions;
  final void Function(String serviceId)? onAdd;
  final String? salonName;

  const SuggestionStrip({Key? key, required this.suggestions, this.onAdd, this.salonName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final hasPicks = suggestions.any((s) => s['reason'] == 'salon_pick');
    final fromHistory = suggestions.any((s) => s['reason'] == 'bought_together');

    final title = hasPicks
        ? 'Recommended for your visit'
        : fromHistory
            ? 'Often booked together here'
            : 'You might also like';
    final subtitle = hasPicks
        ? (salonName == null ? 'Picked by the salon' : 'Picked by $salonName')
        : null;

    return Column(
      key: const ValueKey('cart_suggestion_strip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle, style: GoogleFonts.outfit(fontSize: 12.5, color: colors.textTertiary)),
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _SuggestionCard(
              service: suggestions[index] as Map<String, dynamic>,
              onAdd: onAdd,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final void Function(String serviceId)? onAdd;

  const _SuggestionCard({required this.service, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPick = service['reason'] == 'salon_pick';
    final percent = (service['together_percent'] as num?)?.toInt() ?? 0;
    final duration = (service['duration_minutes'] as num?)?.toInt();
    final pairedWith = service['paired_with']?.toString();

    // One short line on why this card is here.
    final String? why = isPick && pairedWith != null && pairedWith.isNotEmpty
        ? 'Goes with your $pairedWith'
        : service['reason'] == 'bought_together' && percent > 0
            ? 'With $percent% of these bookings'
            : null;

    return Container(
      key: ValueKey('cart_suggestion_${service['id']}'),
      width: 208,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPick ? AppTheme.accentColor.withValues(alpha: 0.35) : colors.border,
          width: isPick ? 1.4 : 1.2,
        ),
        boxShadow: [
          BoxShadow(color: colors.dropShadow, blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPick)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: colors.accentSoft, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 13, color: AppTheme.accentColor),
                  const SizedBox(width: 3),
                  Text("Salon's pick",
                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.accentColor)),
                ],
              ),
            ),
          Text(
            service['name'] ?? 'Service',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w700, color: colors.textPrimary, height: 1.2),
          ),
          if (why != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(why,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 11.5, color: colors.textTertiary)),
            ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('₹${_toDouble(service['price']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                    if (duration != null && duration > 0)
                      Text('$duration min', style: GoogleFonts.outfit(fontSize: 11.5, color: colors.textTertiary)),
                  ],
                ),
              ),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: onAdd == null ? null : () => onAdd!(service['id'].toString()),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 16),
                      const SizedBox(width: 2),
                      Text('Add', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
