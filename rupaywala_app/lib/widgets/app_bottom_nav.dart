import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// A single destination in the role bottom bar.
class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badgeCount;
}

/// The role bottom navigation bar.
///
/// Labels are always visible — the design brief rules out icon-only tabs — and
/// the active item is marked with colour, weight and a filled icon together so
/// the current position never relies on colour alone.
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

  /// Optional live badge counts keyed by item label, e.g. pending requests.
  final Map<String, int>? badgeProvider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: kFastAnimation,
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.primarySoft
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Icon(
                                isActive ? item.activeIcon : item.icon,
                                size: AppIcon.md,
                                color: isActive
                                    ? AppColors.primary
                                    : AppColors.textHint,
                              ),
                            ),
                            if (badge > 0)
                              Positioned(
                                right: 2,
                                top: -3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.pill),
                                    border: Border.all(
                                      color: AppColors.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    badge > 9 ? '9+' : '$badge',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
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
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive
                                ? AppColors.primary
                                : AppColors.textHint,
                          ),
                        ),
                      ],
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
