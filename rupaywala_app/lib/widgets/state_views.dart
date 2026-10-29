import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import 'app_button.dart';

/// Shown whenever a list legitimately has nothing in it yet, with the one
/// action that would change that.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    String? message,
    String? subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  }) : message = message ?? subtitle ?? '';

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: compact ? AppSpacing.xxl : AppSpacing.xxxl * 1.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 26 : 32,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.cardTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                size: AppButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when loading fails. Always offers a retry, because every failure in
/// this app is either transient or resolvable by the user.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
    this.icon = Icons.cloud_off_outlined,
  });

  final String message;
  final String title;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.errorSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, textAlign: TextAlign.center, style: AppText.cardTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center, style: AppText.caption),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full screen busy indicator with an optional label, used while a whole page
/// resolves for the first time.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, String? label, String? message})
      : label = label ?? message;

  final String? label;
  String? get message => label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (label != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(label!, style: AppText.caption),
          ],
        ],
      ),
    );
  }
}

/// Non-blocking offline notice. Every screen stays interactive underneath.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.isOffline,
    this.onRetry,
    this.endpoint,
  });

  final bool isOffline;
  final VoidCallback? onRetry;
  final String? endpoint;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: kFastAnimation,
      curve: Curves.easeOut,
      child: isOffline
          ? Container(
              width: double.infinity,
              color: AppColors.warningSoft,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cannot reach the server',
                          style: AppText.title.copyWith(
                            fontSize: 13,
                            color: AppColors.warning,
                          ),
                        ),
                        if (endpoint != null)
                          Text(
                            endpoint!,
                            style: AppText.caption.copyWith(
                              fontSize: 11.5,
                              color: AppColors.warning.withValues(alpha: 0.8),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.warning,
                      ),
                      child: const Text('Retry'),
                    ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Inline, dismissible-feel alert used inside forms (payment, validation).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.info_outline_rounded,
    this.tone = InfoTone.info,
    this.action,
  });

  final String message;
  final String? title;
  final IconData icon;
  final InfoTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      InfoTone.info => (AppColors.infoSoft, AppColors.info),
      InfoTone.success => (AppColors.successSoft, AppColors.success),
      InfoTone.warning => (AppColors.warningSoft, AppColors.warning),
      InfoTone.error => (AppColors.errorSoft, AppColors.error),
    };

    return Container(
      width: double.infinity,
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: AppText.title.copyWith(
                      fontSize: 14,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: AppText.caption.copyWith(
                    color: foreground.withValues(alpha: 0.92),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum InfoTone { info, success, warning, error }
