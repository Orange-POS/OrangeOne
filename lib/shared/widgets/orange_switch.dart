import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// The design system's pill switch: on, a solid action-orange track with a
/// white oval thumb on the right; off, a light track with the thumb on the
/// left. A null [onChanged] shows it disabled (38 % opacity). The touch
/// target is at least 48 × 48.
class OrangeSwitch extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    required this.label,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Tooltip and accessibility label.
  final String label;

  static const _width = 62.0;
  static const _height = 28.0;
  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final border = value ? OrangeTheme.action : OrangeTheme.actionDisabled;
    return Tooltip(
      message: label,
      child: Semantics(
        toggled: value,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            height: 48,
            width: _width + 8,
            child: Center(
              child: Opacity(
                opacity: enabled ? 1 : .38,
                child: AnimatedContainer(
                  duration: _duration,
                  width: _width,
                  height: _height,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: value ? OrangeTheme.action : const Color(0xFFF1F3F4),
                    borderRadius: BorderRadius.circular(_height / 2),
                    border: Border.all(color: border, width: 2),
                  ),
                  child: AnimatedAlign(
                    duration: _duration,
                    curve: Curves.easeOut,
                    alignment: value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_height / 2),
                        boxShadow: value
                            ? null
                            : const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                      ),
                    ),
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
