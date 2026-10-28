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
    super.key,
  });

  final PreferredSizeWidget appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar == null
          ? null
          : ColoredBox(color: Colors.white, child: bottomNavigationBar),
    ),
  );
}
