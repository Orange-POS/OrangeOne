import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/l10n/l10n.dart';

/// Sample barcodes for the scanner, so the demo needs no camera. A tap runs
/// the normal lookup through [onSelected].
class DemoSampleBarcodes extends ConsumerWidget {
  const new({required this.onSelected, super.key});
  final void Function(String barcode) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barcodes = ref.watch(demoCatalogProvider).sampleBarcodes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.demoSampleBarcodesTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView(
              key: const Key('demo-sample-barcodes'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final barcode in barcodes)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ActionChip(
                      key: Key('demo-barcode-$barcode'),
                      label: Text(barcode),
                      onPressed: () => onSelected(barcode),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
