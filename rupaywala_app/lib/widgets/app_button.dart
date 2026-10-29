import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';

/// The single button used across the app.
///
/// Five variants map to the five intents in the design brief — primary,
/// secondary, ghost, success and danger — so screens never invent their own.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    AppButtonVariant variant = AppButtonVariant.primary,
    AppButtonVariant? type,
    this.size = AppButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
    this.badge,
  }) : variant = type ?? variant;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;

  /// When true the button stretches to the full available width, which is what
  /// every form action wants.
  final bool expand;

  /// Optional count rendered before the label, e.g. pending approvals.
  final int? badge;

  bool get _enabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(variant, enabled: _enabled);

    final textStyle =
        size == AppButtonSize.small ? AppText.buttonSmall : AppText.button;

    final content = isLoading
        ? SizedBox(
            height: size == AppButtonSize.small ? 16 : 20,
            width: size == AppButtonSize.small ? 16 : 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(palette.foreground),
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (badge != null && badge! > 0) ...[
                _CountBadge(count: badge!, enabled: _enabled),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (icon != null) ...[
                Icon(icon,
                    size: size == AppButtonSize.small ? 16 : 19,
                    color: palette.foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.copyWith(color: palette.foreground),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  trailingIcon,
                  size: size == AppButtonSize.small ? 16 : 19,
                  color: palette.foreground,
                ),
              ],
            ],
          );

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: palette.border,
          ),
          child: Container(
            height: _height,
            padding: EdgeInsets.symmetric(
              horizontal:
                  size == AppButtonSize.small ? AppSpacing.lg : AppSpacing.xl,
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }

  double get _height => switch (size) {
        AppButtonSize.small => 40,
        AppButtonSize.medium => kMinTouchTarget,
        AppButtonSize.large => 54,
      };
}

class _Palette {
  const _Palette({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final BoxBorder? border;

  static _Palette of(AppButtonVariant variant, {required bool enabled}) {
    final disabledBg = AppColors.disabled;
    final disabledFg = AppColors.textHint;
    return switch (variant) {
      AppButtonVariant.primary => _Palette(
          background: enabled ? AppColors.primary : disabledBg,
          foreground: enabled ? Colors.white : Colors.white,
        ),
      AppButtonVariant.secondary => _Palette(
          background: AppColors.surface,
          foreground: enabled ? AppColors.primary : disabledFg,
          border: Border.all(color: AppColors.border, width: 1.4),
        ),
      AppButtonVariant.ghost => _Palette(
          background: Colors.transparent,
          foreground: enabled ? AppColors.primary : disabledFg,
        ),
      AppButtonVariant.success => _Palette(
          background: enabled ? AppColors.success : disabledBg,
          foreground: Colors.white,
        ),
      AppButtonVariant.danger => _Palette(
          background: enabled ? AppColors.error : disabledBg,
          foreground: Colors.white,
        ),
    };
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.enabled});

  final int count;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: enabled
            ? Colors.white.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppText.overline.copyWith(color: Colors.white),
      ),
    );
  }
}
