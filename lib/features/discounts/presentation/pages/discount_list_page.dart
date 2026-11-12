import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_details_providers.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_toggle_providers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/orange_switch.dart';
import 'package:orange_one/shared/widgets/product_action_surface.dart';
import 'package:orange_one/shared/widgets/product_navbar.dart';
import 'package:orange_one/shared/widgets/product_scaffold.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

/// Query parameters of the discount routes.
Map<String, String> discountRouteQuery(
  DiscountScope scope, {
  int? discountId,
}) => {
  'barcode': scope.barcode,
  'product_id': '${scope.productId}',
  'discount_id': ?discountId?.toString(),
};

/// Shows a confirmed outcome (a form or action result) as a snack bar.
void showDiscountResult(BuildContext context, String? message) {
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The discounts of one product: regular price, count and the list with
/// edit pencils and pause/resume switches; Create Discount stays at the
/// bottom.
class DiscountListPage extends ConsumerWidget {
  const new({
    required this.scope,
    this.productCard,
    this.navTrailing,
    super.key,
  });

  final DiscountScope scope;

  /// The shared product name card, composed by the app.
  final Widget? productCard;

  /// The navigation bar's trailing action (the cloud sync status), composed
  /// by the app.
  final Widget? navTrailing;

  Future<void> _open(BuildContext context, String route, {int? id}) async {
    final message = await context.pushNamed<String>(
      route,
      queryParameters: discountRouteQuery(scope, discountId: id),
    );
    if (context.mounted) showDiscountResult(context, message);
  }

  /// Confirms, then pauses or resumes [discount] once; success is shown
  /// only after the server confirmed it.
  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    Discount discount,
  ) async {
    final l10n = context.l10n;
    final controller = ref.read(
      discountToggleControllerProvider(scope).notifier,
    );
    if (!controller.canToggle(discount)) return;
    final action = DiscountToggleController.actionFor(discount);
    final pause = action == DiscountAction.pause;
    final confirmed = await DiscountConfirmDialog.show(
      context,
      title: pause
          ? l10n.discountConfirmPauseTitle
          : l10n.discountConfirmResumeTitle,
      message: pause
          ? l10n.discountConfirmPauseBody
          : l10n.discountConfirmResumeBody,
    );
    if (!confirmed || !context.mounted) return;
    await controller.toggle(discount);
    if (!context.mounted) return;
    if (ref.read(discountToggleControllerProvider(scope)).completed != action) {
      return;
    }
    showDiscountResult(
      context,
      pause ? l10n.discountPausedDone : l10n.discountResumedDone,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final access = ref.watch(discountAccessProvider(scope.manageAllowed));
    final provider = productDiscountsControllerProvider(scope.productId);
    final state = ref.watch(provider);
    final list = state.hasError ? null : state.value;
    // At the limit only an unresolved create of this product can still be
    // confirmed (its replay may hold the last slot); fresh creates stay
    // blocked, and the form allows nothing else.
    final pending = ref.watch(pendingDiscountCreateProvider(scope.productId));
    final recover = list != null && list.limitReached && pending != null;
    final canCreate =
        access.canWrite && list != null && (!list.limitReached || recover);
    return ProductScaffold(
      appBar: ProductNavbar(
        title: l10n.discountsPageTitle,
        trailing: navTrailing ?? const SizedBox(width: 48),
        onBack: () => context.canPop()
            ? context.pop()
            : context.goNamed(
                'productDetails',
                queryParameters: {'barcode': scope.barcode},
              ),
      ),
      bottomNavigationBar: access.manage
          ? ProductActionSurface(
              child: FilledButton(
                key: const Key('discount-list-create'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: canCreate
                    ? () => _open(context, 'productDiscountForm')
                    : null,
                child: Text(
                  recover
                      ? l10n.discountPendingRecover
                      : l10n.discountCreateTitle,
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.read(provider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (productCard != null) SliverToBoxAdapter(child: productCard),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: state.when(
                  skipLoadingOnRefresh: true,
                  loading: () => Skeleton(
                    label: l10n.discountLoading,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 160),
                              SizedBox(height: 16),
                              SkeletonTiles(count: 2, height: 72),
                            ],
                          ),
                        ),
                        SizedBox(height: 24),
                        SkeletonBox(width: 180, height: 20),
                        SizedBox(height: 12),
                        SkeletonListTile(),
                        SizedBox(height: 12),
                        SkeletonListTile(),
                        SizedBox(height: 12),
                        SkeletonListTile(),
                      ],
                    ),
                  ),
                  error: (error, stack) => Column(
                    children: [
                      DiscountNotice(
                        error: !access.offline,
                        message: access.offline
                            ? l10n.discountOffline
                            : error is AppFailure &&
                                  error.code != 'DISCOUNTS_UNAVAILABLE'
                            ? error.message
                            : l10n.discountLoadFailed,
                      ),
                      TextButton(
                        onPressed: () => ref.read(provider.notifier).refresh(),
                        child: Text(l10n.commonTryAgain),
                      ),
                    ],
                  ),
                  data: (list) => _content(context, ref, access, list),
                ),
              ),
            ),
          ],
        ),
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
    final toggle = ref.watch(discountToggleControllerProvider(scope));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiscountPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DiscountHeading(title: l10n.discountsOverviewTitle),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: l10n.discountsRegularPrice,
                      value: list.regularPrice.display,
                      background: const Color(0xFFF1F3F4),
                      color: OrangeTheme.ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Figure(
                      label: l10n.discountsTotal,
                      value: '${list.counts.total}',
                      background: OrangeTheme.pale,
                      color: OrangeTheme.dark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (access.offline)
          DiscountNotice(message: l10n.discountOffline)
        else if (!access.manage)
          DiscountNotice(message: l10n.discountReadOnly)
        else if (list.limitReached &&
            ref.watch(pendingDiscountCreateProvider(scope.productId)) != null)
          DiscountNotice(
            key: const Key('discount-list-pending'),
            message: l10n.discountPendingAtLimit,
          )
        else if (list.limitReached)
          DiscountNotice(message: l10n.discountLimitReached),
        const SizedBox(height: 24),
        Row(
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
            Text(
              l10n.discountsCount(list.discounts.length),
              style: const TextStyle(color: OrangeTheme.secondary),
            ),
          ],
        ),
        if (toggle.problem != null)
          DiscountNotice(
            key: const Key('discount-toggle-problem'),
            error: toggle.problem != DiscountActionProblem.changed,
            message: switch (toggle.problem!) {
              DiscountActionProblem.notAllowed =>
                access.offline ? l10n.discountOffline : l10n.discountReadOnly,
              DiscountActionProblem.changed => l10n.discountChanged,
              DiscountActionProblem.uncertain => l10n.discountUncertain,
              DiscountActionProblem.refused =>
                toggle.serverMessage ?? l10n.discountLoadFailed,
            },
          ),
        const SizedBox(height: 12),
        if (list.discounts.isEmpty)
          Text(
            l10n.discountsNone,
            style: const TextStyle(color: OrangeTheme.secondary),
          ),
        for (final discount in list.discounts) ...[
          DiscountListTile(
            key: Key('discount-${discount.id}'),
            discount: discount,
            subtitle: DiscountText.schedule(l10n, locale, discount.schedule),
            onTap: () =>
                _open(context, 'productDiscountDetail', id: discount.id),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EditPencilButton(
                  key: Key('discount-edit-${discount.id}'),
                  tooltip: l10n.discountEditTitle,
                  onPressed:
                      access.canWrite &&
                          discount.editable &&
                          toggle.busyId == null
                      ? () => _open(
                          context,
                          'productDiscountForm',
                          id: discount.id,
                        )
                      : null,
                ),
                if (access.manage)
                  OrangeSwitch(
                    key: Key('discount-toggle-${discount.id}'),
                    // On: the discount is not paused (Active, Scheduled or
                    // Expired as its status pill says).
                    value: !discount.paused,
                    label: discount.paused
                        ? l10n.discountResume
                        : l10n.discountPause,
                    onChanged:
                        access.canWrite &&
                            !discount.archived &&
                            toggle.busyId == null
                        ? (_) => _toggle(context, ref, discount)
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.background,
    required this.color,
  });
  final String label;
  final String value;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: OrangeTheme.secondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
