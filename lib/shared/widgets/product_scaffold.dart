import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Paints one continuous gradient behind product navigation and the name card.
/// White content panels and action surfaces cover the remaining page.
class ProductScaffold extends StatefulWidget {
  const new({
    required this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.floatingBottomBar = false,
    super.key,
  });

  final PreferredSizeWidget appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// The bottom bar floats over the content with a transparent backing
  /// (the scan dock's notch shows the content behind it). The body extends
  /// behind the bar; its bottom inset includes the bar's height. Off for the
  /// sticky action surfaces, which keep their white backing.
  final bool floatingBottomBar;

  @override
  State<ProductScaffold> createState() => _ProductScaffoldState();
}

class _ProductScaffoldState extends State<ProductScaffold> {
  /// The box the gradient fills; [ProductGradientBackdrop] aligns to it.
  final GlobalKey _gradientBox = GlobalKey();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: _gradientBox,
    decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
    child: _ProductGradientScope(
      gradientBox: _gradientBox,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: widget.appBar,
        body: widget.body,
        extendBody: widget.floatingBottomBar,
        floatingActionButton: widget.floatingActionButton,
        floatingActionButtonLocation: widget.floatingActionButtonLocation,
        bottomNavigationBar:
            widget.bottomNavigationBar == null || widget.floatingBottomBar
            ? widget.bottomNavigationBar
            : ColoredBox(
                color: Colors.white,
                child: widget.bottomNavigationBar,
              ),
      ),
    ),
  );
}

class _ProductGradientScope extends InheritedWidget {
  const new({required this.gradientBox, required super.child});
  final GlobalKey gradientBox;

  @override
  bool updateShouldNotify(_ProductGradientScope oldWidget) =>
      oldWidget.gradientBox != gradientBox;
}

/// The scaffold's own gradient behind a pinned header, aligned to the
/// [ProductScaffold] it is in, so the gradient continues without a seam
/// while content scrolls underneath. Paints nothing outside a
/// [ProductScaffold].
class ProductGradientBackdrop extends LeafRenderObjectWidget {
  const new({super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGradientBackdrop(_gradientBox(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGradientBackdrop).gradientBox = _gradientBox(
        context,
      );

  static GlobalKey? _gradientBox(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ProductGradientScope>()
      ?.gradientBox;
}

class _RenderGradientBackdrop extends RenderBox {
  new(this.gradientBox);
  GlobalKey? gradientBox;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final box = gradientBox?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // Where the scaffold's gradient box starts, relative to this box.
    final origin = -localToGlobal(Offset.zero, ancestor: box);
    final shader = OrangeTheme.gradient.createShader(
      (offset + origin) & box.size,
    );
    context.canvas.drawRect(offset & size, Paint()..shader = shader);
  }
}
