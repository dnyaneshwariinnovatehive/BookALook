import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSuccessBg : AppTheme.lightSuccessBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkSuccess.withOpacity(0.3) : AppTheme.lightSuccess.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer, size: 18, color: AppTheme.lightSuccess),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appliedCombos.length == 1
                      ? 'Package applied — you save ₹${totalSaving.toStringAsFixed(0)}'
                      : '${appliedCombos.length} packages applied — you save ₹${totalSaving.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.lightSuccess,
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
                        color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading),
                  ),
                  Text(
                    names,
                    style: GoogleFonts.outfit(fontSize: 12, color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody),
                  ),
                  Row(
                    children: [
                      Text(
                        '₹${_toDouble(combo['list_total']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '₹${_toDouble(combo['combo_total']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess),
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
        color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentColor.withOpacity(isDark ? 0.4 : 0.3)),
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
                      color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You already have ${(offer['services_in_cart'] as List?)?.join(', ') ?? ''}. '
            'Adding the rest costs ₹${extra.toStringAsFixed(0)} more.',
            style: GoogleFonts.outfit(fontSize: 12, color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody, height: 1.4),
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
                                    color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight,
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
                  foregroundColor: Colors.white,
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

/// "Often booked with a Haircut here."
class SuggestionStrip extends StatelessWidget {
  final List<dynamic> suggestions;
  final void Function(String serviceId)? onAdd;

  const SuggestionStrip({Key? key, required this.suggestions, this.onAdd}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textHeading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final textBody = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final textLight = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    // The wording has to be honest about where the suggestion came from.
    final fromHistory = suggestions.any((s) => s['reason'] == 'bought_together');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fromHistory ? 'Often booked together here' : 'You might also like',
          style: GoogleFonts.outfit(
              fontSize: 16, fontWeight: FontWeight.bold, color: textHeading),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final service = suggestions[index] as Map<String, dynamic>;
              final percent = service['together_percent'] ?? 0;

              return Container(
                width: 180,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['name'] ?? 'Service',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textHeading),
                    ),
                    const SizedBox(height: 2),
                    if (service['reason'] == 'bought_together' && percent > 0)
                      Text('with $percent% of these bookings',
                          style: GoogleFonts.outfit(
                              fontSize: 11, color: textLight)),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('₹${_toDouble(service['price']).toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentColor)),
                        SizedBox(
                          height: 32,
                          child: OutlinedButton(
                            onPressed:
                                onAdd == null ? null : () => onAdd!(service['id'].toString()),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              foregroundColor: AppTheme.accentColor,
                              backgroundColor: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text('ADD',
                                style: GoogleFonts.outfit(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
