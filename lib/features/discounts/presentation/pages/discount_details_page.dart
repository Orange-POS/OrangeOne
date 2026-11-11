import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/discounts/presentation/discount_text.dart';
import 'package:orange_one/features/discounts/presentation/pages/discount_list_page.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_details_providers.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/product_action_surface.dart';
import 'package:orange_one/shared/widgets/product_navbar.dart';
import 'package:orange_one/shared/widgets/product_scaffold.dart';

/// One discount: regular price, value, server preview, schedule, repeat,
/// minimum quantity and status, with the permitted Edit, Pause/Resume and
/// Archive actions. Every action is confirmed and sent once.
class DiscountDetailsPage extends ConsumerWidget {
  const new({
    required this.scope,
    required this.discountId,
    this.productCard,
    this.navTrailing,
    super.key,
  });

  final DiscountScope scope;
  final int discountId;
  final Widget? productCard;

  /// The navigation bar's trailing action (the cloud sync status), composed
  /// by the app.
  final Widget? navTrailing;

  DiscountDetailsArgs get _args => (scope: scope, discountId: discountId);

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    DiscountAction action,
  ) async {
    final l10n = context.l10n;
    final controller = ref.read(
      discountDetailsControllerProvider(_args).notifier,
    );
    if (!controller.canRun(action)) return;
    final (title, body) = switch (action) {
      DiscountAction.pause => (
        l10n.discountConfirmPauseTitle,
        l10n.discountConfirmPauseBody,
      ),
      DiscountAction.resume => (
        l10n.discountConfirmResumeTitle,
        l10n.discountConfirmResumeBody,
      ),
      DiscountAction.archive => (
        l10n.discountConfirmArchiveTitle,
        l10n.discountConfirmArchiveBody,
      ),
    };
    final confirmed = await DiscountConfirmDialog.show(
      context,
      title: title,
      message: body,
    );
    if (!confirmed || !context.mounted) return;
    await controller.run(action);
    if (!context.mounted) return;
    final state = ref.read(discountDetailsControllerProvider(_args)).value;
    if (state?.completed != action) return;
    final message = switch (action) {
      DiscountAction.pause => l10n.discountPausedDone,
      DiscountAction.resume => l10n.discountResumedDone,
      DiscountAction.archive => l10n.discountArchivedDone,
    };
    if (action == DiscountAction.archive && context.canPop()) {
      context.pop(message);
    } else {
      showDiscountResult(context, message);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final message = await context.pushNamed<String>(
      'productDiscountForm',
      queryParameters: discountRouteQuery(scope, discountId: discountId),
    );
    if (!context.mounted) return;
    if (message != null) {
      ref.invalidate(discountDetailsControllerProvider(_args));
    }
    showDiscountResult(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final access = ref.watch(discountAccessProvider(scope.manageAllowed));
    final provider = discountDetailsControllerProvider(_args);
    final state = ref.watch(provider);
    final value = state.hasError ? null : state.value;
    final discount = value?.discount;
    final busy = value?.busy != null;
    final canWrite = access.canWrite && discount != null && !busy;
    return PopScope(
      canPop: !busy,
      child: ProductScaffold(
        appBar: ProductNavbar(
          title: l10n.discountPageTitle,
          trailing: navTrailing ?? const SizedBox(width: 48),
          onBack: busy
              ? null
              : () => context.canPop()
                    ? context.pop()
                    : context.goNamed(
                        'productDiscounts',
                        queryParameters: discountRouteQuery(scope),
                      ),
        ),
        bottomNavigationBar: access.manage && discount != null
            ? ProductActionSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _button(
                      key: 'discount-edit',
                      label: l10n.discountEditTitle,
                      onPressed: canWrite && discount.editable
                          ? () => _edit(context, ref)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: discount.paused
                              ? _button(
                                  key: 'discount-resume',
                                  label: l10n.discountResume,
                                  outlined: true,
                                  onPressed: canWrite && discount.canResume
                                      ? () => _run(
                                          context,
                                          ref,
                                          DiscountAction.resume,
                                        )
                                      : null,
                                )
                              : _button(
                                  key: 'discount-pause',
                                  label: l10n.discountPause,
                                  outlined: true,
                                  onPressed: canWrite && discount.canPause
                                      ? () => _run(
                                          context,
                                          ref,
                                          DiscountAction.pause,
                                        )
                                      : null,
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _button(
                            key: 'discount-archive',
                            label: l10n.discountArchive,
                            outlined: true,
                            onPressed: canWrite && !discount.archived
                                ? () =>
                                      _run(context, ref, DiscountAction.archive)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
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
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: state.when(
                    skipLoadingOnRefresh: true,
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: l10n.discountLoading,
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
                          onPressed: () =>
                              ref.read(provider.notifier).refresh(),
                          child: Text(l10n.commonTryAgain),
                        ),
                      ],
                    ),
                    data: (value) => _content(context, access, value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String key,
    required String label,
    required VoidCallback? onPressed,
    bool outlined = false,
  }) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 56)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final text = Text(label, textAlign: TextAlign.center);
    return outlined
        ? OutlinedButton(
            key: Key(key),
            style: style,
            onPressed: onPressed,
            child: text,
          )
        : FilledButton(
            key: Key(key),
            style: style,
            onPressed: onPressed,
            child: text,
          );
  }

  Widget _content(
    BuildContext context,
    DiscountAccess access,
    DiscountDetailsState value,
  ) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final discount = value.discount;
    final preview = discount.preview;
    final rows = <(String, String)>[
      (l10n.discountsRegularPrice, discount.regularPrice.display),
      (l10n.discountValueLabel, DiscountText.title(l10n, discount)),
      if (preview.unitPrice != null)
        (l10n.discountCalculatedPrice, preview.unitPrice!.display),
      if (preview.bundleRegularPrice != null)
        (
          l10n.discountBundleTotalPrice,
          l10n.discountRegularBundleTotal(preview.bundleRegularPrice!.display),
        ),
      (
        l10n.discountSavingsLabel,
        l10n.discountSavings(preview.savings.display, preview.savingsPercent),
      ),
      (
        l10n.discountSchedule,
        DiscountText.schedule(l10n, locale, discount.schedule),
      ),
      if (discount.schedule?.timezone != null)
        ('', l10n.discountTimezone(discount.schedule!.timezone!)),
      (
        l10n.discountRepeatSchedule,
        DiscountText.repeat(l10n, locale, discount.repeat),
      ),
      (
        l10n.discountMinimumQuantity,
        DiscountText.minimum(l10n, discount.minimumQuantity),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiscountListTile(discount: discount),
        const SizedBox(height: 12),
        DiscountPanel(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.discountStatusLabel,
                      style: const TextStyle(color: OrangeTheme.secondary),
                    ),
                  ),
                  DiscountStatusPill(status: discount.status),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  discount.appliesNow
                      ? l10n.discountAppliesNow
                      : l10n.discountNotNow,
                  key: const Key('discount-applies-now'),
                  style: const TextStyle(
                    color: OrangeTheme.secondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const Divider(height: 24),
              for (final (label, text) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(color: OrangeTheme.secondary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Text(
                          text,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: OrangeTheme.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        for (final warning in discount.warnings)
          DiscountNotice(message: warning.message),
        if (discount.archived)
          DiscountNotice(message: l10n.discountArchivedNotice)
        else if (access.offline)
          DiscountNotice(message: l10n.discountOffline)
        else if (!access.manage)
          DiscountNotice(message: l10n.discountReadOnly),
        if (value.problem != null)
          DiscountNotice(
            error: value.problem != DiscountActionProblem.changed,
            message: switch (value.problem!) {
              DiscountActionProblem.notAllowed =>
                access.offline ? l10n.discountOffline : l10n.discountReadOnly,
              DiscountActionProblem.changed => l10n.discountChanged,
              DiscountActionProblem.uncertain => l10n.discountUncertain,
              DiscountActionProblem.refused =>
                value.serverMessage ?? l10n.discountLoadFailed,
            },
          ),
      ],
    );
  }
}
