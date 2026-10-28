import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Round orange action that returns to the barcode scanner.
class OpenScannerButton extends StatelessWidget {
  const new({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.detailsOpenScanner;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: OrangeTheme.action,
          elevation: 6,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            key: const Key('open-scanner-button'),
            onTap: onPressed,
            customBorder: const CircleBorder(),
            splashColor: OrangeTheme.actionPressed,
            child: SizedBox.square(
              dimension: 64,
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/box_scan.svg',
                  width: 32,
                  height: 32,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
