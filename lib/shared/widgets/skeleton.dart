import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// The app's loading state: gray placeholder blocks in the shape of the
/// content that is on its way, with one soft shimmer sweeping across them.
///
/// Wrap a loading area once in [Skeleton] and build its shape from
/// [SkeletonBox], [SkeletonLines] and the presets below. The area is a
/// single accessibility node announcing [label]; the blocks themselves are
/// hidden from screen readers. With reduced motion (the platform's
/// "remove animations" setting) the blocks stay still.
class Skeleton extends StatefulWidget {
  const new({
    required this.label,
    required this.child,
    this.onDark = false,
    super.key,
  });

  /// What is loading, for screen readers ("Loading product details"). Null
  /// when a visible text beside the placeholder already says it.
  final String? label;
  final Widget child;

  /// Translucent white blocks for the orange gradient and the camera.
  final bool onDark;

  static const _period = Duration(milliseconds: 1400);

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Skeleton._period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.onDark
        ? OrangeTheme.skeletonOnDarkBase
        : OrangeTheme.skeletonBase;
    final highlight = widget.onDark
        ? OrangeTheme.skeletonOnDarkHighlight
        : OrangeTheme.skeletonHighlight;
    return Semantics(
      label: widget.label,
      liveRegion: widget.label != null,
      container: widget.label != null,
      child: ExcludeSemantics(
        child: _SkeletonScope(
          base: base,
          child: AnimatedBuilder(
            animation: _controller,
            child: widget.child,
            // The sweep runs over the blocks only (srcATop): a band of
            // [highlight] moving from left to right.
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                colors: [base, highlight, base],
                stops: const [.35, .5, .65],
                transform: _SlideGradient(_controller.value),
              ).createShader(bounds),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves the gradient from one bound's width left of the area to one width
/// right of it.
class _SlideGradient extends GradientTransform {
  const new(this.progress);
  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
}

class _SkeletonScope extends InheritedWidget {
  const new({required this.base, required super.child});
  final Color base;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>()?.base ??
      OrangeTheme.skeletonBase;

  @override
  bool updateShouldNotify(_SkeletonScope old) => old.base != base;
}

/// One placeholder block. Without [width] it fills the available width.
class SkeletonBox extends StatelessWidget {
  const new({this.width, this.height = 16, this.radius = 8, super.key});

  /// A round block (avatar, icon).
  const new circle({required double size, super.key})
    : width = size,
      height = size,
      radius = size / 2;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width ?? double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: _SkeletonScope.of(context),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Lines of text: full width, the last one shorter.
class SkeletonLines extends StatelessWidget {
  const new({
    this.count = 2,
    this.height = 14,
    this.spacing = 10,
    this.lastWidthFactor = .6,
    super.key,
  });

  final int count;
  final double height;
  final double spacing;
  final double lastWidthFactor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        FractionallySizedBox(
          widthFactor: i == count - 1 && count > 1 ? lastWidthFactor : 1,
          child: SkeletonBox(height: height, radius: height / 2),
        ),
      ],
    ],
  );
}

/// A bordered card of placeholders, like the app's content cards. It has no
/// fill of its own: the shimmer paints every opaque pixel inside
/// [Skeleton], so the white comes from the surface behind.
class SkeletonCard extends StatelessWidget {
  const new({
    this.child = const SkeletonLines(),
    this.padding = const EdgeInsets.all(16),
    this.radius = 12,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _SkeletonScope.of(context)),
    ),
    child: child,
  );
}

/// A list row: square icon tile, two lines, an optional trailing block.
class SkeletonListTile extends StatelessWidget {
  const new({this.leading = 48, this.trailing = true, super.key});

  final double leading;
  final bool trailing;

  @override
  Widget build(BuildContext context) => SkeletonCard(
    child: Row(
      children: [
        SkeletonBox(width: leading, height: leading, radius: 12),
        const SizedBox(width: 16),
        const Expanded(child: SkeletonLines(count: 3, height: 12)),
        if (trailing) ...[
          const SizedBox(width: 16),
          const SkeletonBox(width: 44, height: 24, radius: 12),
        ],
      ],
    ),
  );
}

/// A one-line info card: icon, label and a value on the right (the Price
/// card of the product screens).
class SkeletonInfoRow extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const SkeletonCard(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    child: Row(
      children: [
        SkeletonBox(width: 24, height: 24, radius: 6),
        SizedBox(width: 12),
        SkeletonBox(width: 96, height: 14),
        Spacer(),
        SkeletonBox(width: 80, height: 14),
      ],
    ),
  );
}

/// A row of [count] equal tiles (type selectors, overview figures).
class SkeletonTiles extends StatelessWidget {
  const new({this.count = 3, this.height = 62, super.key});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(child: SkeletonBox(height: height, radius: 12)),
      ],
    ],
  );
}

/// A form: [fields] label-and-input pairs.
class SkeletonForm extends StatelessWidget {
  const new({this.fields = 3, super.key});
  final int fields;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < fields; i++) ...[
        if (i > 0) const SizedBox(height: 20),
        // A short label; Align keeps it from stretching.
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SkeletonBox(width: 120, height: 14),
        ),
        const SizedBox(height: 10),
        const SkeletonBox(height: 52, radius: 12),
      ],
    ],
  );
}
