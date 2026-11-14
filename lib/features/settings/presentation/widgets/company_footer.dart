import 'package:flutter/material.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// The company signature at the end of Settings: the supplied logo and the
/// company name, which is a proper name and is not translated.
class CompanyFooter extends StatelessWidget {
  const new({super.key});

  // The supplied design's red for "IT".
  static const _highlight = Color(0xFFFF383C);

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('company-footer'),
    label: 'Swiss Alps IT Services',
    excludeSemantics: true,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/branding/company_logo.png', height: 20),
        const SizedBox(width: 14),
        const Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Swiss Alps '),
                TextSpan(
                  text: 'IT',
                  style: TextStyle(color: _highlight),
                ),
                TextSpan(text: ' Services'),
              ],
            ),
            style: TextStyle(
              color: OrangeTheme.secondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}
