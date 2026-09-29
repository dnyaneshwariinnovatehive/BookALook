import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/phone_screen.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';

/// The horizontally scrolling services of one category inside a salon card.
///
/// A customer browsing a category has already decided they want that service, so
/// this is where they act on it: the price and an add button for each service the
/// salon offers in that category, without opening the salon. Tapping the card
/// around the strip still opens the salon, so browsing is never a dead end.
class CategoryServiceStrip extends StatefulWidget {
  final String salonId;
  final List<Map<String, dynamic>> services;
  final String? categoryName;

  const CategoryServiceStrip({
    super.key,
    required this.salonId,
    required this.services,
    this.categoryName,
  });

  @override
  State<CategoryServiceStrip> createState() => _CategoryServiceStripState();
}

class _CategoryServiceStripState extends State<CategoryServiceStrip> {
  final CartService _cartService = CartService();

  /// service id -> quantity the customer has added from this strip.
  final Map<String, int> _added = {};
  final Set<String> _adding = {};

  /// How many services to show before the "see all" affordance. Enough to fill
  /// the width of a card on the largest common phone, so the scroll gesture
  /// reads as deliberate rather than as an accident of layout.
  static const int _previewCount = 6;

  List<Map<String, dynamic>> get _visible =>
      widget.services.length > _previewCount
      ? widget.services.take(_previewCount).toList()
      : widget.services;

  bool get _hasMore => widget.services.length > _previewCount;

  Future<void> _addService(Map<String, dynamic> service) async {
    final serviceId = service['id'].toString();
    if (_adding.contains(serviceId)) return;

    // Booking needs an account, so an anonymous customer is asked to sign in at
    // the moment they try to act, not before they have chosen anything.
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true || !mounted) return;
    }

    setState(() => _adding.add(serviceId));

    try {
      await _cartService.addItem(widget.salonId, serviceId);
      if (!mounted) return;
      AppHaptics.lightImpact();
      setState(() {
        _added[serviceId] = (_added[serviceId] ?? 0) + 1;
      });
      _toast('${service['name'] ?? 'Service'} added to cart');
    } on CartConflictException catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _confirmReplace(e, service);
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _adding.remove(serviceId));
    }
  }

  /// The cart holds one salon at a time, so a service from a second salon is a
  /// question rather than an error. Same wording as the salon page so the rule
  /// is not learned twice.
  void _confirmReplace(CartConflictException e, Map<String, dynamic> service) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Replace cart items?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Your cart contains items from ${e.otherSalonName}. '
          'Do you want to discard that selection and add items from this salon?',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(ctx);
            },
            child: Text('Cancel', style: GoogleFonts.outfit(color: bodyColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              AppHaptics.lightImpact();
              Navigator.pop(ctx);
              try {
                await _cartService.clearGlobalCart();
              } catch (_) {
                if (!mounted) return;
                _toast('Could not clear your cart.');
                return;
              }
              if (!mounted) return;
              await _addService(service);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
            ),
            child: Text(
              'Replace',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headingColor = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);

    if (widget.services.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              widget.categoryName == null
                  ? 'Services'
                  : '${widget.categoryName} services',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: bodyColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${widget.services.length}',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentColor,
              ),
            ),
            const Spacer(),
            if (_hasMore)
              Text(
                '+${widget.services.length - _previewCount} more',
                style: GoogleFonts.outfit(fontSize: 11, color: bodyColor),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: _visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final service = _visible[index];
              return _buildChip(
                service,
                isDark: isDark,
                headingColor: headingColor,
                bodyColor: bodyColor,
                borderColor: borderColor,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChip(
    Map<String, dynamic> service, {
    required bool isDark,
    required Color headingColor,
    required Color bodyColor,
    required Color borderColor,
  }) {
    final serviceId = service['id'].toString();
    final isAdding = _adding.contains(serviceId);
    final quantity = _added[serviceId] ?? 0;
    final price = (service['price'] as num?)?.toDouble() ?? 0;

    // Zero trained staff means it cannot be booked, so the salon page greys
    // these out and so must the strip — an enabled button here would only
    // produce a dead end at checkout.
    final isBookable = (service['provider_count'] as num?)?.toInt() != 0;

    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : const Color(0xFFFAF9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  service['name'] ?? 'Service',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: headingColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isBookable ? '₹${price.toStringAsFixed(0)}' : 'Unavailable',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isBookable ? AppTheme.accentColor : bodyColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _buildButton(
            isBookable: isBookable,
            isAdding: isAdding,
            quantity: quantity,
            onPressed: () => _addService(service),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required bool isBookable,
    required bool isAdding,
    required int quantity,
    required VoidCallback onPressed,
  }) {
    // An added service turns into a counter rather than a button that can be
    // pressed again: the cart already holds it, and the number is what tells
    // the customer that.
    final label = isAdding
        ? ''
        : quantity > 0
        ? '$quantity'
        : '+';

    return GestureDetector(
      onTap: isBookable && !isAdding ? onPressed : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isBookable ? AppTheme.accentColor : const Color(0xFFCFCBD8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: isAdding
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
