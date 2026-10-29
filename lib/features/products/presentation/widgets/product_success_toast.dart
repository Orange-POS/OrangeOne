import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';

/// The success toast of a finished product form: the existing success notice
/// design, shown above the Open Scanner button of Product Details.
class ProductSuccessToast extends ConsumerStatefulWidget {
  const new({required this.barcode, this.duration = _visible, super.key});
  final String barcode;
  final Duration duration;

  static const _visible = Duration(seconds: 5);

  @override
  ConsumerState<ProductSuccessToast> createState() =>
      _ProductSuccessToastState();
}

class _ProductSuccessToastState extends ConsumerState<ProductSuccessToast> {
  Timer? _timer;

  void _arm(ProductSuccess? success) {
    _timer?.cancel();
    if (success == null || success.barcode != widget.barcode) return;
    _timer = Timer(widget.duration, () {
      if (mounted && ref.read(productSuccessProvider) == success) {
        ref.read(productSuccessProvider.notifier).dismiss();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _arm(ref.read(productSuccessProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(productSuccessProvider, (previous, next) => _arm(next));
    final success = ref.watch(productSuccessProvider);
    if (success == null || success.barcode != widget.barcode) {
      return const SizedBox.shrink();
    }
    return PriceUpdateNotice(
      key: const Key('product-success-toast'),
      success: true,
      title: success.title,
      message: success.message,
    );
  }
}
