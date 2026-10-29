import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/product_sync_indicator.dart';

/// The cloud icon in the top-right of a product screen: the sync status of
/// the product, in place of the former pencil action.
class ProductSyncNavButton extends StatelessWidget {
  const new({required this.barcode, super.key});
  final String barcode;

  /// Status text with the localized time of the last server verification.
  static String _time(BuildContext context, String status, DateTime time) {
    final material = MaterialLocalizations.of(context);
    final local = time.toLocal();
    return context.l10n.syncLastVerified(
      status,
      '${material.formatCompactDate(local)} '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .2),
      ),
      alignment: Alignment.center,
      child: ProductSyncIndicator(
        barcode: barcode,
        labels: ProductSyncLabels(
          pending: l10n.syncPending,
          online: l10n.syncOnline,
          offline: l10n.syncOffline,
          failed: l10n.syncFailed,
          lastVerified: (status, time) => _time(context, status, time),
        ),
        onlineIcon: SvgPicture.asset(
          'assets/icons/product_detail_online.svg',
          width: 24,
          height: 24,
        ),
      ),
    );
  }
}
