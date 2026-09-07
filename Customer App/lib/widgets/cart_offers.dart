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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightSuccessBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightSuccess.withOpacity(0.35)),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.lightTextHeading),
                  ),
                  Text(
                    names,
                    style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody),
                  ),
                  Row(
                    children: [
                      Text(
                        '₹${_toDouble(combo['list_total']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.lightTextLight,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '₹${_toDouble(combo['combo_total']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.lightSuccess),
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightAccentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
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
                      color: AppTheme.lightTextHeading),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You already have ${(offer['services_in_cart'] as List?)?.join(', ') ?? ''}. '
            'Adding the rest costs ₹${extra.toStringAsFixed(0)} more.',
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody, height: 1.4),
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
                                    color: AppTheme.lightTextLight,
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

    // The wording has to be honest about where the suggestion came from.
    final fromHistory = suggestions.any((s) => s['reason'] == 'bought_together');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fromHistory ? 'Often booked together here' : 'You might also like',
          style: GoogleFonts.outfit(
              fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final service = suggestions[index] as Map<String, dynamic>;
              final percent = service['together_percent'] ?? 0;

              return Container(
                width: 168,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lightSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.lightBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['name'] ?? 'Service',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.lightTextHeading),
                    ),
                    const SizedBox(height: 2),
                    if (service['reason'] == 'bought_together' && percent > 0)
                      Text('with $percent% of these bookings',
                          style: GoogleFonts.outfit(
                              fontSize: 10.5, color: AppTheme.lightTextLight)),
                    const Spacer(),
                    Text('₹${_toDouble(service['price']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.lightTextHeading)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 30,
                      child: OutlinedButton(
                        onPressed:
                            onAdd == null ? null : () => onAdd!(service['id'].toString()),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: AppTheme.accentColor,
                          side: BorderSide(color: AppTheme.accentColor.withOpacity(0.5)),
                        ),
                        child: Text('Add',
                            style: GoogleFonts.outfit(
                                fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ),
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
