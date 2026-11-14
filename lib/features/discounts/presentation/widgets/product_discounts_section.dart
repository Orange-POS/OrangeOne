import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_navigation.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';
import 'package:orange_one/shared/widgets/tag_icon.dart';

/// The "Product Discounts" section of Product Details: every discount of the
/// product with its value, type, schedule and status, an edit pencil, and
/// the compact "Create New Discounts" card. A card opens the edit form when
/// the discount can be changed, otherwise its read-only details. Pause and
/// resume are on the edit form. Hidden entirely without discount access.
class ProductDiscountsSection extends ConsumerWidget {
  const new({required this.scope, super.key});

  final DiscountScope scope;

  /// Opens a discount screen and shows its confirmed result on return. The
  /// screens refresh the product's discounts after every confirmed write.
  Future<void> _open(BuildContext context, String route, {int? id}) async {
    final message = await context.pushNamed<String>(
      route,
      queryParameters: discountRouteQuery(scope, discountId: id),
    );
    if (context.mounted) showDiscountResult(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(discountAccessProvider(scope.manageAllowed));
    if (!access.visible || !access.read) return const SizedBox.shrink();
    final l10n = context.l10n;
    final provider = productDiscountsControllerProvider(scope.productId);
    final state = ref.watch(provider);
    return Padding(
      key: const Key('product-discounts'),
      padding: const EdgeInsets.only(top: 24),
      child: state.when(
        skipLoadingOnRefresh: true,
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(count: null),
            const SizedBox(height: 12),
            Skeleton(
              label: l10n.discountLoading,
              child: const Column(
                children: [
                  SkeletonListTile(),
                  SizedBox(height: 12),
                  SkeletonListTile(),
                ],
              ),
            ),
          ],
        ),
        error: (error, stack) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(count: null),
            DiscountNotice(
              error: !access.offline,
              message: access.offline
                  ? l10n.discountOffline
                  : l10n.discountLoadFailed,
            ),
            if (!access.offline)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('product-discounts-retry'),
                  onPressed: () => ref.read(provider.notifier).refresh(),
                  child: Text(l10n.commonTryAgain),
                ),
              ),
          ],
        ),
        data: (list) => _content(context, ref, access, list),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    DiscountAccess access,
    ProductDiscounts list,
  ) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    // At the limit only an unresolved create of this product can still be
    // confirmed (its replay may hold the last slot); fresh creates stay
    // blocked, and the form allows nothing else.
    final pending = ref.watch(pendingDiscountCreateProvider(scope.productId));
    final recover = list.limitReached && pending != null;
    final canCreate = access.canWrite && (!list.limitReached || recover);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(count: list.discounts.length),
        if (access.offline)
          DiscountNotice(message: l10n.discountOffline)
        else if (!access.manage)
          DiscountNotice(message: l10n.discountReadOnly)
        else if (recover)
          DiscountNotice(
            key: const Key('product-discounts-pending'),
            message: l10n.discountPendingAtLimit,
          )
        else if (list.limitReached)
          DiscountNotice(message: l10n.discountLimitReached),
        const SizedBox(height: 12),
        if (list.discounts.isEmpty && !access.manage)
          Text(
            l10n.discountsNone,
            style: const TextStyle(color: OrangeTheme.secondary),
          ),
        for (final discount in list.discounts) ...[
          _tile(context, access, discount, locale),
          const SizedBox(height: 12),
        ],
        if (access.manage)
          DiscountCreateCard(
            key: const Key('product-discounts-create'),
            title: recover
                ? l10n.discountPendingRecover
                : l10n.discountsCreateNewTitle,
            tooltip: l10n.discountCreateTitle,
            onPressed: canCreate
                ? () => _open(context, 'productDiscountForm')
                : null,
          ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    DiscountAccess access,
    Discount discount,
    String locale,
  ) {
    final l10n = context.l10n;
    final canEdit = access.canWrite && discount.editable;
    return DiscountListTile(
      key: Key('discount-${discount.id}'),
      discount: discount,
      subtitle: DiscountText.schedule(l10n, locale, discount.schedule),
      // Straight to the edit form when permitted; otherwise the read-only
      // details, so every term stays visible.
      onTap: () => _open(
        context,
        canEdit ? 'productDiscountForm' : 'productDiscountDetail',
        id: discount.id,
      ),
      trailing: EditPencilButton(
        key: Key('discount-edit-${discount.id}'),
        tooltip: l10n.discountEditTitle,
        onPressed: canEdit
            ? () => _open(context, 'productDiscountForm', id: discount.id)
            : null,
      ),
    );
  }
}

/// "Product Discounts" with the number of discounts (unknown while loading).
class _Header extends StatelessWidget {
  const new({required this.count});
  final int? count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              l10n.discountsListTitle,
              style: const TextStyle(
                color: OrangeTheme.ink,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (count case final count?)
          Text(
            l10n.discountsCount(count),
            key: const Key('product-discounts-count'),
            style: const TextStyle(color: OrangeTheme.secondary),
          ),
      ],
    );
  }
}

/// The compact "Create New Discounts" card: the outlined tag, the section
/// label, the title and an orange plus. Disabled: gray plus, no action.
class DiscountCreateCard extends StatelessWidget {
  const new({
    required this.title,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      excludeSemantics: true,
      child: DiscountPanel(
        onTap: onPressed,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              const TagIcon(size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.discountsSectionLabel,
                      style: const TextStyle(
                        color: OrangeTheme.secondary,
                        fontSize: 12,
                        height: 16 / 12,
                        letterSpacing: .4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        color: OrangeTheme.ink,
                        fontSize: 18,
                        height: 24 / 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: tooltip,
                child: Icon(
                  Icons.add_circle_outline,
                  size: 28,
                  color: enabled
                      ? OrangeTheme.action
                      : OrangeTheme.actionDisabledLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
