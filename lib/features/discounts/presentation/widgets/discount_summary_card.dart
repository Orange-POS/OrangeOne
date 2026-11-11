import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

/// The discount card on Product Details: "Discount Overview" (count and
/// up to four discounts) or "Create New Discounts" without discounts.
/// Hidden entirely when the shop or the user has no discount access.
class DiscountSummaryCard extends ConsumerWidget {
  const new({
    required this.productId,
    required this.manageAllowed,
    required this.onOpen,
    required this.onCreate,
    super.key,
  });

  final int productId;

  /// The product's own `discount_manage`.
  final bool manageAllowed;
  final VoidCallback onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(discountAccessProvider(manageAllowed));
    if (!access.visible || !access.read) return const SizedBox.shrink();
    final l10n = context.l10n;
    final state = ref.watch(productDiscountsControllerProvider(productId));
    return Padding(
      key: const Key('discount-summary'),
      padding: const EdgeInsets.only(top: 16),
      child: state.when(
        skipLoadingOnRefresh: true,
        loading: () => DiscountPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DiscountHeading(title: l10n.discountsOverviewTitle),
              const SizedBox(height: 16),
              Skeleton(
                label: l10n.discountLoading,
                child: const SkeletonTiles(count: 2, height: 72),
              ),
            ],
          ),
        ),
        error: (error, stack) => DiscountPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DiscountHeading(title: l10n.discountsOverviewTitle),
              DiscountNotice(
                message: access.offline
                    ? l10n.discountOffline
                    : l10n.discountLoadFailed,
              ),
              if (!access.offline)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('discount-summary-retry'),
                    onPressed: () => ref
                        .read(
                          productDiscountsControllerProvider(productId)
                              .notifier,
                        )
                        .refresh(),
                    child: Text(l10n.commonTryAgain),
                  ),
                ),
            ],
          ),
        ),
        data: (list) => list.counts.total == 0 && list.discounts.isEmpty
            ? _empty(context, access)
            : _overview(context, access, list),
      ),
    );
  }

  Widget _empty(BuildContext context, DiscountAccess access) {
    final l10n = context.l10n;
    if (!access.manage) {
      return DiscountPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiscountHeading(title: l10n.discountsOverviewTitle),
            const SizedBox(height: 12),
            Text(
              l10n.discountsNone,
              style: const TextStyle(color: OrangeTheme.secondary),
            ),
          ],
        ),
      );
    }
    return DiscountPanel(
      child: Column(
        children: [
          DiscountHeading(
            title: l10n.discountsCreateNewTitle,
            trailing: DiscountAddButton(
              key: const Key('discount-create-new'),
              tooltip: l10n.discountCreateTitle,
              onPressed: access.canWrite ? onCreate : null,
            ),
          ),
          if (access.offline) DiscountNotice(message: l10n.discountOffline),
        ],
      ),
    );
  }

  Widget _overview(
    BuildContext context,
    DiscountAccess access,
    ProductDiscounts list,
  ) {
    final l10n = context.l10n;
    final shown = list.discounts.take(4).toList();
    return DiscountPanel(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiscountHeading(
            title: l10n.discountsOverviewTitle,
            trailing: EditPencilButton(
              key: const Key('discount-open'),
              tooltip: l10n.discountsOpen,
              onPressed: onOpen,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OrangeTheme.pale,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.discountsTotal,
                  style: const TextStyle(color: OrangeTheme.secondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${list.counts.total}',
                  key: const Key('discount-total'),
                  style: const TextStyle(
                    color: OrangeTheme.dark,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Two cards per row (no LayoutBuilder: Product Details sizes its
          // panel with intrinsic dimensions).
          for (var row = 0; row < shown.length; row += 2) ...[
            if (row > 0) const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _MiniCard(discount: shown[row])),
                  const SizedBox(width: 12),
                  Expanded(
                    child: row + 1 < shown.length
                        ? _MiniCard(discount: shown[row + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
          if (access.offline) DiscountNotice(message: l10n.discountOffline),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const new({required this.discount});
  final Discount discount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Row(
        children: [
          const DiscountTagIcon(size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DiscountText.title(l10n, discount),
                  style: const TextStyle(
                    color: OrangeTheme.ink,
                    fontSize: 15,
                    height: 20 / 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DiscountText.typeLong(l10n, discount.type),
                  style: const TextStyle(
                    color: OrangeTheme.secondary,
                    fontSize: 13,
                    height: 18 / 13,
                  ),
                ),
                if (discount.status != DiscountStatus.active)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: DiscountStatusPill(status: discount.status),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
