import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class PriceContextRow extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.barcode = false,
    super.key,
  });
  final String label;
  final String value;
  final bool barcode;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFDADCE0)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (barcode)
          SvgPicture.asset(
            'assets/icons/product_barcode.svg',
            colorFilter: const ColorFilter.mode(
              OrangeTheme.scannerAccent,
              BlendMode.srcIn,
            ),
            width: 20,
            height: 20,
          )
        else
          const Icon(
            Icons.payments_outlined,
            color: OrangeTheme.scannerAccent,
            size: 20,
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: OrangeTheme.secondary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}
