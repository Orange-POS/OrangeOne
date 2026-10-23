import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductNavbar extends StatelessWidget implements PreferredSizeWidget {
  const new({
    required this.title,
    required this.onBack,
    required this.onEdit,
    required this.editTooltip,
    this.trailing,
    this.backTooltip = 'Back',
    super.key,
  });
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onEdit;
  final String editTooltip;
  final Widget? trailing;
  final String backTooltip;
  @override
  Size get preferredSize => const Size.fromHeight(80);
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    minimum: const EdgeInsets.only(top: OrangeTheme.topSafeArea),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            tooltip: backTooltip,
            onPressed: onBack,
            style: _buttonStyle,
            icon: SvgPicture.asset(
              'assets/icons/arrow_left.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          trailing ??
              IconButton(
                tooltip: editTooltip,
                onPressed: onEdit,
                style: _buttonStyle,
                color: Colors.white,
                disabledColor: Colors.white38,
                icon: const Icon(Icons.edit_square),
              ),
        ],
      ),
    ),
  );
  ButtonStyle get _buttonStyle => IconButton.styleFrom(
    backgroundColor: Colors.white.withValues(alpha: .2),
    fixedSize: const Size(48, 48),
  );
}
