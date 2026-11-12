import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Paints one continuous gradient behind product navigation and the name card.
/// White content panels and action surfaces cover the remaining page.
class ProductScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
      extendBody: floatingBottomBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar == null || floatingBottomBar
          ? bottomNavigationBar
          : ColoredBox(color: Colors.white, child: bottomNavigationBar),
    ),
  );
}
