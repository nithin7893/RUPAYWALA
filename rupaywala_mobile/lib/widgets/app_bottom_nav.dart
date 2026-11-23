import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A single destination in the role bottom bar.
class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badgeCount = 0,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badgeCount;

  /// The one action that matters most in this role. It is rendered as a filled
  /// circle in the middle of the bar — customer "Request", for example — so the
  /// primary task is reachable from any tab without adding a floating button
  /// that would cover list content.
  final bool isPrimary;
}

/// The role bottom navigation bar.
///
/// Labels are always visible — the design brief rules out icon-only tabs — and
/// the active item is marked with colour, weight and a filled icon together so
/// the current position never relies on colour alone. Height grows with the
/// user's text scale instead of clipping the labels.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.badgeProvider,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Optional live badge counts keyed by item label, e.g. unread messages.
  final Map<String, int>? badgeProvider;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(0.9, 2.2);
    final height = (62 + (scale - 1) * 18).clamp(62.0, 86.0);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isActive = index == currentIndex;
              final badge = badgeProvider?[item.label] ?? item.badgeCount;

              return Expanded(
                child: Semantics(
                  selected: isActive,
                  button: true,
                  label: item.label,
                  child: InkWell(
                    onTap: () => onTap(index),
                    splashColor: AppColors.primarySoft,
                    highlightColor: AppColors.primarySoft,
                    child: _NavItemBody(
                      item: item,
                      isActive: isActive,
                      badge: badge,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItemBody extends StatelessWidget {
  const _NavItemBody({
    required this.item,
    required this.isActive,
    required this.badge,
  });

  final AppNavItem item;
  final bool isActive;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final iconColor = item.isPrimary
        ? Colors.white
        : (isActive ? AppColors.primary : AppColors.textSecondary);
    final labelColor = item.isPrimary
        ? AppColors.primary
        : (isActive ? AppColors.primary : AppColors.textSecondary);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: kFastAnimation,
              curve: Curves.easeOut,
              width: item.isPrimary ? 44 : null,
              height: item.isPrimary ? 34 : null,
              padding: item.isPrimary
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: 3,
                    ),
              decoration: BoxDecoration(
                color: item.isPrimary
                    ? (isActive
                        ? AppColors.primaryDark
                        : AppColors.primary)
                    : (isActive ? AppColors.primarySoft : Colors.transparent),
                borderRadius: BorderRadius.circular(
                  item.isPrimary ? AppRadius.md : AppRadius.pill,
                ),
                boxShadow: item.isPrimary
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isActive && !item.isPrimary ? item.activeIcon : item.icon,
                size: item.isPrimary ? AppIcon.md : AppIcon.md,
                color: iconColor,
              ),
            ),
            if (badge > 0)
              Positioned(
                right: item.isPrimary ? -4 : 0,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 9.5,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 11,
              height: 1.2,
              letterSpacing: -0.1,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: labelColor,
            ),
          ),
        ),
      ],
    );
  }
}
