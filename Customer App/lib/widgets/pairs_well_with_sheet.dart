import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';

/// Offered right after a customer adds a service the salon has linked
/// add-ons to: "Pairs well with your Haircut". Each can be added in one tap
/// without leaving the sheet; nothing is added unless they tap.
///
/// [onAdd] adds one service and says whether it worked.
Future<void> showPairsWellWithSheet(
  BuildContext context, {
  required String baseName,
  required String? salonName,
  required List<Map<String, dynamic>> services,
  required Future<bool> Function(String serviceId) onAdd,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => PairsWellWithSheet(
      baseName: baseName,
      salonName: salonName,
      services: services,
      onAdd: onAdd,
    ),
  );
}

class PairsWellWithSheet extends StatefulWidget {
  final String baseName;
  final String? salonName;
  final List<Map<String, dynamic>> services;
  final Future<bool> Function(String serviceId) onAdd;

  const PairsWellWithSheet({
    super.key,
    required this.baseName,
    required this.salonName,
    required this.services,
    required this.onAdd,
  });

  @override
  State<PairsWellWithSheet> createState() => _PairsWellWithSheetState();
}

class _PairsWellWithSheetState extends State<PairsWellWithSheet> {
  final Set<String> _adding = {};
  final Set<String> _added = {};

  Future<void> _add(String id) async {
    if (_adding.contains(id) || _added.contains(id)) return;
    setState(() => _adding.add(id));
    final ok = await widget.onAdd(id);
    if (!mounted) return;
    setState(() {
      _adding.remove(id);
      if (ok) _added.add(id);
    });
    if (ok) AppHaptics.lightImpact();
  }

  static double _price(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colors.accentSoft, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.accentColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pairs well with your ${widget.baseName}',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary),
                    ),
                    Text(
                      widget.salonName == null ? 'Recommended by the salon' : 'Recommended by ${widget.salonName}',
                      style: GoogleFonts.outfit(fontSize: 13, color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.services.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = widget.services[i];
                final id = s['id'].toString();
                final added = _added.contains(id);
                final adding = _adding.contains(id);
                final duration = s['duration_minutes'];

                return AnimatedContainer(
                  key: ValueKey('pairs_well_row_$id'),
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: added ? colors.successBg : colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: added ? colors.success.withValues(alpha: 0.4) : colors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['name']?.toString() ?? 'Service',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (duration != null) '$duration min',
                                '₹${_price(s['discounted_price'] ?? s['price']).toStringAsFixed(0)}',
                              ].join('  ·  '),
                              style: GoogleFonts.outfit(fontSize: 13, color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 36,
                        child: added
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded, color: colors.success, size: 20),
                                  const SizedBox(width: 4),
                                  Text('Added', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: colors.success)),
                                ],
                              )
                            : FilledButton(
                                key: ValueKey('pairs_well_add_$id'),
                                onPressed: adding ? null : () => _add(id),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.accentColor,
                                  padding: const EdgeInsets.symmetric(horizontal: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: adding
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text('Add', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: const ValueKey('pairs_well_done'),
              onPressed: () => Navigator.pop(context),
              child: Text(
                _added.isEmpty ? 'No thanks' : 'Done',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
