import 'package:flutter/material.dart';
import 'package:orange_one/features/demo/domain/entities/demo_barcodes.dart';
import 'package:orange_one/l10n/l10n.dart';

/// Two sample barcodes for the scanner, so the demo needs no camera: one of an
/// existing product and one that no product uses, which leads to product
/// creation. A tap runs the normal lookup through [onSelected].
class DemoSampleBarcodes extends StatelessWidget {
  const new({required this.onSelected, super.key});
  final void Function(String barcode) onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final samples = [
      (
        DemoBarcodes.existingProduct,
        l10n.demoExistingProductBarcode(DemoBarcodes.existingProduct),
      ),
      (
        DemoBarcodes.newProduct,
        l10n.demoNewProductBarcode(DemoBarcodes.newProduct),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.demoSampleBarcodesTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            key: const Key('demo-sample-barcodes'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (barcode, label) in samples)
                ActionChip(
                  key: Key('demo-barcode-$barcode'),
                  label: Text(label),
                  onPressed: () => onSelected(barcode),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
