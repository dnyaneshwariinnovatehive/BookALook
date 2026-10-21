import 'package:flutter/material.dart';
import '../models/service_models.dart';
import '../theme/app_theme.dart';

class UnassignedServicesWarningBanner extends StatefulWidget {
  final List<UnassignedServiceItem> unassignedServices;
  final VoidCallback? onActionPressed;
  final String? actionLabel;
  final ValueChanged<UnassignedServiceItem>? onServicePressed;
  final EdgeInsetsGeometry? margin;

  const UnassignedServicesWarningBanner({
    super.key,
    required this.unassignedServices,
    this.onActionPressed,
    this.actionLabel,
    this.onServicePressed,
    this.margin,
  });

  @override
  State<UnassignedServicesWarningBanner> createState() => _UnassignedServicesWarningBannerState();
}

class _UnassignedServicesWarningBannerState extends State<UnassignedServicesWarningBanner> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.unassignedServices.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final warningColor = isDark ? AppTheme.darkWarning : AppTheme.lightWarning;
    final warningBg = isDark ? AppTheme.darkWarningBg : AppTheme.lightWarningBg;
    final textColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final subtextColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    final total = widget.unassignedServices.length;
    final displayedServices = _isExpanded || total <= 3
        ? widget.unassignedServices
        : widget.unassignedServices.take(3).toList();
    final remainingCount = total - displayedServices.length;

    return Container(
      margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: warningColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Icon, Title & Optional Action
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: warningColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: warningColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total Service${total > 1 ? 's' : ''} Not Assigned to Staff',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: warningColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'These services cannot be booked by customers until assigned to at least one staff member or service provider.',
                      style: TextStyle(
                        fontSize: 12,
                        color: subtextColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Chips of affected services
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...displayedServices.map((service) {
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: widget.onServicePressed != null
                      ? () => widget.onServicePressed!(service)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: warningColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cut,
                          size: 12,
                          color: warningColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          service.name,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        if (widget.onServicePressed != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 9,
                            color: subtextColor.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              if (remainingCount > 0)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _isExpanded = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: warningColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: warningColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '+$remainingCount more',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: warningColor,
                      ),
                    ),
                  ),
                ),
              if (_isExpanded && total > 3)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _isExpanded = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: warningColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Show less',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: warningColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          if (widget.onActionPressed != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onActionPressed,
                style: TextButton.styleFrom(
                  foregroundColor: warningColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.arrow_forward, size: 14),
                label: Text(
                  widget.actionLabel ?? 'Assign to Staff',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
