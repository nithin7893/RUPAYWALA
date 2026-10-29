import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';

/// The one card surface used everywhere: white, thin border, soft shadow,
/// 16px radius. Tap target only when it actually navigates somewhere.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.card,
    this.onTap,
    this.color,
    this.borderColor,
    this.margin,
    this.radius = AppRadius.lg,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          borderRadius: shape,
          border: Border.all(color: borderColor ?? AppColors.border),
          boxShadow: elevated ? AppElevation.card : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: shape,
          child: InkWell(
            onTap: onTap,
            borderRadius: shape,
            child: Padding(padding: padding ?? AppSpacing.card, child: child),
          ),
        ),
      ),
    );
  }
}

/// A card with a coloured icon tile and a title/subtitle on the left, used to
/// build lists without repeating the same Row in every screen.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.iconBackground,
    this.trailing,
    this.onTap,
    this.padding = AppSpacing.card,
    this.children = const [],
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackground;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                IconTile(
                  icon: icon!,
                  color: iconColor,
                  background: iconBackground,
                  size: 40,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppText.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint),
              ],
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ],
      ),
    );
  }
}

/// Rounded square icon background, the app's standard leading element.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color,
    this.background,
    this.size = 44,
    this.iconSize = 22,
    this.radius = AppRadius.md,
  });

  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

/// Circular avatar with initials, used across profile and member lists.
class AppAvatar extends StatelessWidget {
  const AppAvatar(
      {super.key, required this.initials, this.size = 48, this.color});

  final String initials;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.12),
        border: Border.all(color: tint.withValues(alpha: 0.24)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: tint,
        ),
      ),
    );
  }
}
