import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import 'app_card.dart';

/// Placeholder blocks shown while content loads.
///
/// Shaped to match the content they replace — a `StatTile` placeholder is the
/// same size as a real tile — so the layout does not jump when data arrives.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.height = 14,
    this.width,
    this.radius = AppRadius.sm,
    this.shape = BoxShape.rectangle,
  });

  final double height;
  final double? width;
  final double radius;
  final BoxShape shape;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppColors.divider,
              AppColors.neutralSoft,
              _controller.value,
            ),
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.circle
                ? null
                : BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Skeleton for a `StatTile`.
class StatTileSkeleton extends StatelessWidget {
  const StatTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SkeletonBox(height: 36, width: 36, radius: AppRadius.sm),
          const SizedBox(height: AppSpacing.md),
          const SkeletonBox(height: 24, width: 60),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(height: 12, width: 44),
        ],
      ),
    );
  }
}

/// Skeleton for a list row card.
class ListCardSkeleton extends StatelessWidget {
  const ListCardSkeleton({super.key, this.hasTrailing = true});

  final bool hasTrailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 40, width: 40, radius: AppRadius.md),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(height: 13, width: 160),
                const SizedBox(height: AppSpacing.sm),
                const SkeletonBox(height: 11),
                const SizedBox(height: AppSpacing.xs),
                const SkeletonBox(height: 11, width: 90),
              ],
            ),
          ),
          if (hasTrailing) ...[
            const SizedBox(width: AppSpacing.md),
            const SkeletonBox(height: 22, width: 64, radius: AppRadius.pill),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for a service or plan tile.
class TileSkeleton extends StatelessWidget {
  const TileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonBox(height: 44, width: 44, radius: AppRadius.md),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(height: 14, width: 130),
                    const SizedBox(height: AppSpacing.sm),
                    const SkeletonBox(height: 11, width: 80),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SkeletonBox(height: 12),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(height: 12, width: 200),
        ],
      ),
    );
  }
}

/// A ready-made skeleton list for list screens.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 4,
    this.itemBuilder,
    this.spacing = AppSpacing.md,
  });

  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: spacing),
      itemBuilder: (context, index) =>
          itemBuilder?.call(context, index) ?? const ListCardSkeleton(),
    );
  }
}

/// A skeleton grid for dashboard tiles.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.itemCount = 4, this.crossAxisCount = 2});

  final int itemCount;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        mainAxisExtent: 128,
      ),
      itemBuilder: (context, index) => const StatTileSkeleton(),
    );
  }
}

/// Shimmer sweep overlay, used by [SkeletonBox] consumers that want a moving
/// highlight rather than a pulse.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final progress = _controller.value;
            return LinearGradient(
              begin: Alignment(-1.6 + progress * 3.2, 0),
              end: Alignment(-0.6 + progress * 3.2, 0),
              colors: const [
                AppColors.surfaceMuted,
                Colors.white,
                AppColors.surfaceMuted,
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Bottom padding that clears the bottom nav bar and the system gesture area.
class BottomNavSpacer extends StatelessWidget {
  const BottomNavSpacer({super.key, this.extra = 0});

  final double extra;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62 + MediaQuery.paddingOf(context).bottom + AppSpacing.xl + extra,
    );
  }
}
