import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// One destination in [CollaboratorPillNavBar].
class CollaboratorNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Pending items, shown as a count on the icon. `null` hides the badge.
  /// `0` also hides it — an empty list is not news.
  final int? badge;

  const CollaboratorNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge,
  });

  CollaboratorNavItem copyWith({int? badge, bool clearBadge = false}) =>
      CollaboratorNavItem(
        label: label,
        icon: icon,
        activeIcon: activeIcon,
        badge: clearBadge ? null : (badge ?? this.badge),
      );
}

/// The collaborator's bottom navigation, as a floating pill.
///
/// This replaces the bare `BottomNavigationBar` the shell used to have, which
/// was the only unstyled navigation in the app — the admin shell has had a
/// pill since [dashboard_screen.dart] and the service provider a shadowed bar,
/// so signing in as a collaborator landed you somewhere that looked like a
/// different product.
///
/// It is hand-built rather than a `BottomNavigationBar` in a `Container` for
/// one reason: a badge. `BottomNavigationBarItem` has nowhere to put one, and
/// the count of salons waiting is the single most useful thing on this screen —
/// without it a collaborator has to open Assigned to find out they have work.
class CollaboratorPillNavBar extends StatelessWidget {
  final List<CollaboratorNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CollaboratorPillNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavButton(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final CollaboratorNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final colour = selected ? AppTheme.accentColor : palette.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: item.badge != null && item.badge! > 0
          ? '${item.label}, ${item.badge} waiting'
          : item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        splashColor: AppTheme.accentColor.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 26,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Outlined icon when idle, filled when active. The old bar
                    // used the filled glyph in both states, so the only cue for
                    // "where am I" was the label's colour.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        selected ? item.activeIcon : item.icon,
                        key: ValueKey(selected),
                        size: 22,
                        color: colour,
                      ),
                    ),
                    if (item.badge != null && item.badge! > 0)
                      Positioned(
                        right: -10,
                        top: -3,
                        child: _Badge(count: item.badge!),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    // Anything past 99 is "more than you will get to today"; showing the exact
    // number would overflow the pill.
    final label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: context.colors.danger,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.surface, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
