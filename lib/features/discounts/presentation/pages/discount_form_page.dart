import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/preferences/time_format_controller.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_form_providers.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_conflict_panel.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_form_inputs.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_form_sections.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_pickers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/info_row_card.dart';
import 'package:orange_one/shared/widgets/product_action_surface.dart';
import 'package:orange_one/shared/widgets/product_navbar.dart';
import 'package:orange_one/shared/widgets/product_scaffold.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

/// The shared Create/Edit Discount form. Save → confirmation → one write;
/// on success it closes with the confirmed message, on failure it stays with
/// the entered values and field-level errors.
class DiscountFormPage extends ConsumerStatefulWidget {
  const new({
    required this.scope,
    this.discountId,
    this.productCard,
    this.navTrailing,
    this.onEditPrice,
    super.key,
  });

  final DiscountScope scope;

  /// Opens the product's price screen (composed by the app) and returns
  /// whether a new price was saved; null hides the Price card's pencil
  /// action (no `update_price`).
  final Future<bool> Function(BuildContext context)? onEditPrice;

  /// Null creates a new discount.
  final int? discountId;
  final Widget? productCard;

  /// The navigation bar's trailing action (the cloud sync status), composed
  /// by the app.
  final Widget? navTrailing;

  @override
  ConsumerState<DiscountFormPage> createState() => _DiscountFormPageState();
}

class _DiscountFormPageState extends ConsumerState<DiscountFormPage> {
  final _fixed = TextEditingController();
  final _percent = TextEditingController();
  final _bundleQuantity = TextEditingController();
  final _bundlePrice = TextEditingController();
  final _minimum = TextEditingController();
  bool _filled = false;
  bool _scheduleOpen = false;
  bool _minimumOpen = false;
  bool _confirming = false;

  DiscountFormArgs get _args =>
      (scope: widget.scope, discountId: widget.discountId);

  @override
  void dispose() {
    for (final controller in [
      _fixed,
      _percent,
      _bundleQuantity,
      _bundlePrice,
      _minimum,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fill(DiscountDraft draft) {
    _fixed.text = draft.fixedPrice;
    _percent.text = draft.percent;
    _bundleQuantity.text = draft.bundleQuantity;
    _bundlePrice.text = draft.bundlePrice;
    _minimum.text = draft.minimumQuantity;
    _scheduleOpen = draft.schedule != null;
    _minimumOpen = draft.minimumQuantity.isNotEmpty;
  }

  DiscountFormController get _controller =>
      ref.read(discountFormControllerProvider(_args).notifier);

  Future<void> _save(DiscountFormState state) async {
    if (_confirming || !_controller.canConfirm) return;
    final l10n = context.l10n;
    final preview = state.preview;
    final offer = preview == null
        ? DiscountText.typeLong(l10n, state.draft.type!)
        : DiscountText.previewHeadline(
            l10n,
            state.draft,
            preview,
            state.regularPrice.currency,
          )!;
    // An earlier create with other values is unresolved: Save replays that
    // request first, so the user confirms that original offer (which may
    // be created now), not the edited one.
    final replay = _controller.pendingReplay;
    final currency = state.regularPrice.currency;
    _confirming = true;
    FocusScope.of(context).unfocus();
    try {
      final confirmed = replay != null
          ? await DiscountConfirmDialog.show(
              context,
              title: l10n.discountReplayTitle,
              message: l10n.discountReplayBody(
                DiscountText.draftValue(l10n, replay.draft, currency),
                DiscountText.draftValue(l10n, state.draft, currency),
              ),
              confirmLabel: l10n.discountReplayConfirm(
                DiscountText.draftValue(l10n, replay.draft, currency),
              ),
            )
          : await DiscountConfirmDialog.show(
              context,
              title: state.editing
                  ? l10n.discountConfirmSaveTitle
                  : l10n.discountConfirmCreateTitle,
              message: l10n.discountConfirmChangeBody(offer),
            );
      // Cancelling sends nothing and keeps the edited draft.
      if (confirmed && mounted) await _controller.save();
    } finally {
      _confirming = false;
    }
  }

  /// The Price card's pencil: the product's own price screen, then the new
  /// regular price for validation and the preview (typed values stay).
  Future<void> _editPrice() async {
    final edit = widget.onEditPrice;
    if (edit == null || _confirming) return;
    FocusScope.of(context).unfocus();
    final changed = await edit(context);
    if (changed && mounted) await _controller.refreshRegularPrice();
  }

  /// Confirms, then archives through the form's own controller: Save,
  /// Archive and leaving the form share its busy state, so nothing overlaps
  /// while the archive is pending. A failure keeps the draft.
  Future<void> _archive() async {
    if (_confirming || !_controller.canArchive) return;
    final l10n = context.l10n;
    _confirming = true;
    FocusScope.of(context).unfocus();
    try {
      final confirmed = await DiscountConfirmDialog.show(
        context,
        title: l10n.discountConfirmArchiveTitle,
        message: l10n.discountConfirmArchiveBody,
      );
      if (confirmed && mounted) await _controller.archive();
    } finally {
      _confirming = false;
    }
  }

  Future<void> _pickDate(DiscountFormState state, {required bool end}) async {
    final l10n = context.l10n;
    final schedule = state.draft.schedule;
    final current = end
        ? schedule?.endDate ?? schedule?.startDate
        : schedule?.startDate;
    final now = DateTime.now();
    final initial = current == null
        ? DateTime(now.year, now.month, now.day)
        : DateTime(current.year, current.month, current.day);
    final picked = await DiscountDateSheet.show(
      context,
      caption: l10n.discountEditingField(
        end ? l10n.discountEndDate : l10n.discountStartDate,
      ),
      initial: initial,
      first: DateTime(now.year - 5),
      last: DateTime(now.year + 10, 12, 31),
    );
    if (picked == null || !mounted) return;
    _controller.setSchedulePart(
      end: end,
      date: LocalDate(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _pickTime(DiscountFormState state, {required bool end}) async {
    final l10n = context.l10n;
    final schedule = state.draft.schedule;
    final current = end
        ? schedule?.endTime ?? schedule?.startTime
        : schedule?.startTime;
    final picked = await DiscountTimeSheet.show(
      context,
      caption: l10n.discountEditingField(
        end ? l10n.discountEndTime : l10n.discountStartTime,
      ),
      initial: current ?? const TimeOfDayValue(9, 0),
    );
    if (picked == null || !mounted) return;
    _controller.setSchedulePart(end: end, time: picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final access = ref.watch(
      discountAccessProvider(widget.scope.manageAllowed),
    );
    final provider = discountFormControllerProvider(_args);
    final async = ref.watch(provider);
    final state = async.hasError ? null : async.value;
    ref.listen(provider, (previous, next) {
      final before = previous?.value;
      final value = next.value;
      if (value == null) return;
      if (value.phase == DiscountFormPhase.saved &&
          before?.phase != DiscountFormPhase.saved) {
        context.pop(value.editing ? l10n.discountSaved : l10n.discountCreated);
      } else if (value.phase == DiscountFormPhase.archived &&
          before?.phase != DiscountFormPhase.archived) {
        context.pop(l10n.discountArchivedDone);
      } else if (before?.conflict != null && value.conflict == null) {
        // The merged values replace what the inputs show.
        _fill(value.draft);
      }
    });
    if (state != null && !_filled) {
      _filled = true;
      _fill(state.draft);
    }
    final busy = state?.busy ?? false;
    final saving = state?.phase == DiscountFormPhase.saving;
    final editable =
        state != null &&
        !busy &&
        state.phase == DiscountFormPhase.editing &&
        (state.original?.editable ?? true);
    final canSave =
        state != null && state.canSubmit && access.canWrite && !busy;
    final canArchive = state != null && state.canArchive && access.canWrite;
    final editingStored = state?.editing ?? widget.discountId != null;
    return PopScope(
      canPop: !busy,
      child: ProductScaffold(
        appBar: ProductNavbar(
          title: editingStored
              ? l10n.discountEditTitle
              : l10n.discountCreateTitle,
          onBack: busy ? null : () => context.pop(),
          trailing: state?.original != null
              ? IconButton(
                  key: const Key('discount-form-archive'),
                  tooltip: l10n.discountArchive,
                  onPressed: canArchive ? _archive : null,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .2),
                    fixedSize: const Size(48, 48),
                  ),
                  icon: Opacity(
                    opacity: canArchive ? 1 : .5,
                    child: const DiscountSvgIcon(
                      'assets/icons/archive.svg',
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                )
              : widget.navTrailing ?? const SizedBox(width: 48),
        ),
        bottomNavigationBar: ProductActionSurface(
          child: FilledButton(
            key: const Key('discount-save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              // Saving stays orange; while archiving Save is plainly off.
              disabledBackgroundColor: saving ? OrangeTheme.action : null,
              disabledForegroundColor: saving ? Colors.white : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: canSave ? () => _save(state) : null,
            child: Text(
              saving
                  ? l10n.discountSaving
                  : state?.phase == DiscountFormPhase.archiving
                  ? l10n.discountArchiving
                  : editingStored
                  ? l10n.commonSaveChanges
                  : l10n.discountCreateTitle,
            ),
          ),
        ),
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (widget.productCard != null)
              SliverToBoxAdapter(child: widget.productCard),
            // The form is a plain box sliver: its cards animate their height,
            // and SliverFillRemaining sizes its child from intrinsic heights
            // that lag behind such animations (overflow stripes). A separate
            // white filler continues the panel to the bottom instead.
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: async.when(
                  skipLoadingOnRefresh: true,
                  loading: () => Skeleton(
                    label: l10n.discountLoading,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonInfoRow(),
                        SizedBox(height: 16),
                        SkeletonCard(child: SkeletonLines(count: 3)),
                        SizedBox(height: 20),
                        SkeletonBox(width: 160, height: 20),
                        SizedBox(height: 12),
                        SkeletonTiles(),
                        SizedBox(height: 20),
                        SkeletonForm(fields: 1),
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
                                  error.code == 'DISCOUNTS_UNAVAILABLE'
                            ? l10n.discountReadOnly
                            : error is AppFailure
                            ? error.message
                            : l10n.discountLoadFailed,
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(provider),
                        child: Text(l10n.commonTryAgain),
                      ),
                    ],
                  ),
                  data: (state) => _form(context, access, state, editable),
                ),
              ),
            ),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: ColoredBox(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  String? _issue(DiscountFormState state, String field) {
    final issue = state.visibleIssues[field];
    if (issue != null) {
      // A required value shows its error only once the user typed or saved.
      if (issue == DiscountIssue.required &&
          !state.serverIssues.containsKey(field)) {
        return null;
      }
      return DiscountText.issue(context.l10n, issue);
    }
    return state.serverMessages[field];
  }

  Widget _form(
    BuildContext context,
    DiscountAccess access,
    DiscountFormState state,
    bool editable,
  ) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final draft = state.draft;
    final currency = state.regularPrice.currency;
    final preview = state.preview;
    final schedule = draft.schedule;
    final typeIcon = draft.type == null ? null : discountTypeIcon(draft.type!);
    final merge = state.merge;
    final pendingProblem =
        state.problem == DiscountFormProblem.pendingCreate ||
        state.problem == DiscountFormProblem.pendingExpired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // An earlier create of this product is unresolved: said first.
        if (pendingProblem) ...[
          DiscountNotice(
            key: const Key('discount-pending'),
            error: state.problem == DiscountFormProblem.pendingExpired,
            message: state.problem == DiscountFormProblem.pendingExpired
                ? l10n.discountPendingExpired
                : l10n.discountPendingCreate,
          ),
          if (state.problem == DiscountFormProblem.pendingExpired)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                key: const Key('discount-pending-discard'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: editable
                    ? _controller.discardExpiredPendingCreate
                    : null,
                child: Text(l10n.discountPendingDiscard),
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (merge != null)
          DiscountConflictPanel(
            merge: merge,
            keepMine: state.conflict!.keepMine,
            currency: currency,
            onChoose: editable ? _controller.choose : null,
            onApply: editable && state.conflictDecided
                ? _controller.resolveConflict
                : null,
          ),
        InfoRowCard.price(
          label: l10n.discountsRegularPrice,
          value: state.regularPrice.display,
          valueKey: const Key('discount-regular-price'),
          action: widget.onEditPrice == null
              ? null
              : EditPencilButton(
                  key: const Key('discount-edit-price'),
                  tooltip: l10n.detailsUpdatePrice,
                  onPressed: editable && !access.offline ? _editPrice : null,
                ),
        ),
        const SizedBox(height: 16),
        DiscountPreviewCard(draft: draft, preview: preview, currency: currency),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            l10n.discountTypeHeading,
            style: const TextStyle(
              color: OrangeTheme.ink,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        DiscountTypeSelector(
          selected: draft.type,
          enabled: editable,
          onChanged: (type) =>
              _controller.change((draft) => draft.copyWith(type: type)),
        ),
        AnimatedSize(
          duration: DiscountSection.duration,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (draft.type == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.discountChooseType,
                    style: const TextStyle(color: OrangeTheme.secondary),
                  ),
                )
              else
                ...switch (draft.type!) {
                  DiscountType.fixedPrice => [
                    DiscountTextField(
                      fieldKey: 'discount-fixed-price',
                      label: l10n.discountDiscountedPrice,
                      controller: _fixed,
                      enabled: editable,
                      icon: typeIcon,
                      prefix: currency,
                      helper: l10n.discountAmountHelper(currency),
                      error: _issue(state, DiscountField.fixedPrice),
                      onChanged: (value) => _controller.change(
                        (draft) => draft.copyWith(fixedPrice: value),
                      ),
                    ),
                  ],
                  DiscountType.percentage => [
                    DiscountTextField(
                      fieldKey: 'discount-percent',
                      label: l10n.discountPercentageLabel,
                      controller: _percent,
                      enabled: editable,
                      icon: typeIcon,
                      error: _issue(state, DiscountField.percent),
                      onChanged: (value) => _controller.change(
                        (draft) => draft.copyWith(percent: value),
                      ),
                    ),
                    if (preview?.unitPriceCents != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.discountCalculatedPrice,
                                style: const TextStyle(
                                  color: OrangeTheme.secondary,
                                ),
                              ),
                            ),
                            Text(
                              DiscountText.money(
                                preview!.unitPriceCents!,
                                currency,
                              ),
                              style: const TextStyle(
                                color: OrangeTheme.action,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  DiscountType.collective => [
                    DiscountTextField(
                      fieldKey: 'discount-bundle-quantity',
                      label: l10n.discountBundleQuantity,
                      controller: _bundleQuantity,
                      enabled: editable,
                      icon: typeIcon,
                      integer: true,
                      error: _issue(state, DiscountField.bundleQuantity),
                      onChanged: (value) => _controller.change(
                        (draft) => draft.copyWith(bundleQuantity: value),
                      ),
                    ),
                    DiscountTextField(
                      fieldKey: 'discount-bundle-price',
                      label: l10n.discountBundleTotalPrice,
                      controller: _bundlePrice,
                      enabled: editable,
                      icon: typeIcon,
                      prefix: currency,
                      helper: preview?.bundleRegularCents == null
                          ? null
                          : l10n.discountRegularBundleTotal(
                              DiscountText.money(
                                preview!.bundleRegularCents!,
                                currency,
                              ),
                            ),
                      error: _issue(state, DiscountField.bundlePrice),
                      onChanged: (value) => _controller.change(
                        (draft) => draft.copyWith(bundlePrice: value),
                      ),
                    ),
                  ],
                },
            ],
          ),
        ),
        DiscountSection(
          sectionKey: 'discount-section-schedule',
          icon: 'assets/icons/discount_calendar.svg',
          title: l10n.discountDateTime,
          summary: DiscountText.scheduleShort(l10n, locale, schedule),
          expanded: _scheduleOpen,
          error:
              _issue(state, DiscountField.endDate) ??
              _issue(state, DiscountField.startDate),
          onToggle: editable
              ? () => setState(() => _scheduleOpen = !_scheduleOpen)
              : null,
          child: _scheduleFields(state, editable, locale),
        ),
        DiscountSection(
          sectionKey: 'discount-section-minimum',
          icon: 'assets/icons/discount_basket.svg',
          title: l10n.discountMinimumQuantity,
          summary: draft.minimumQuantity.trim().isEmpty
              ? l10n.discountSetMinimum
              : DiscountText.minimum(l10n, draft.minimumQuantity),
          expanded: _minimumOpen,
          onToggle: editable
              ? () => setState(() => _minimumOpen = !_minimumOpen)
              : null,
          error: _minimumOpen
              ? null
              : _issue(state, DiscountField.minimumQuantity),
          child: DiscountTextField(
            fieldKey: 'discount-minimum',
            label: l10n.discountMinimumQuantity,
            controller: _minimum,
            enabled: editable,
            helper: l10n.discountMinimumHelper,
            error: _issue(state, DiscountField.minimumQuantity),
            onChanged: (value) => _controller.change(
              (draft) => draft.copyWith(minimumQuantity: value),
            ),
          ),
        ),
        DiscountSection(
          sectionKey: 'discount-section-repeat',
          icon: 'assets/icons/discount_repeat.svg',
          title: l10n.discountRepeatSchedule,
          summary: DiscountText.repeat(l10n, locale, draft.repeat),
          expanded: false,
          error:
              _issue(state, DiscountField.weekdays) ??
              _issue(state, DiscountField.annualDate),
          onToggle: editable
              ? () async {
                  final repeat = await DiscountRepeatSheet.show(
                    context,
                    draft.repeat,
                  );
                  if (repeat != null && mounted) {
                    _controller.change(
                      (draft) => draft.copyWith(repeat: repeat),
                    );
                  }
                }
              : null,
        ),
        if (state.original?.archived ?? false)
          DiscountNotice(message: l10n.discountArchivedNotice)
        else if (access.offline)
          DiscountNotice(message: l10n.discountOffline)
        else if (!access.manage)
          DiscountNotice(message: l10n.discountReadOnly)
        else if (state.limitReached && !state.editing)
          DiscountNotice(message: l10n.discountLimitReached),
        // The conflict panel and the pending notice at the top explain
        // those states already.
        if (state.problem != null && merge == null && !pendingProblem)
          DiscountNotice(
            key: const Key('discount-form-problem'),
            error: switch (state.problem!) {
              DiscountFormProblem.changed ||
              DiscountFormProblem.createdMeanwhile ||
              DiscountFormProblem.originalRefused => false,
              _ => true,
            },
            message: switch (state.problem!) {
              DiscountFormProblem.notAllowed =>
                access.offline ? l10n.discountOffline : l10n.discountReadOnly,
              DiscountFormProblem.limitReached => l10n.discountLimitReached,
              DiscountFormProblem.changed => l10n.discountChanged,
              DiscountFormProblem.uncertain => l10n.discountUncertain,
              DiscountFormProblem.createdMeanwhile =>
                l10n.discountCreatedMeanwhile,
              DiscountFormProblem.pendingCreate => l10n.discountPendingCreate,
              DiscountFormProblem.pendingExpired => l10n.discountPendingExpired,
              DiscountFormProblem.originalRefused =>
                l10n.discountOriginalRefused,
              DiscountFormProblem.refused =>
                DiscountText.rule(l10n, state.ruleCode) ??
                    state.problemMessage ??
                    l10n.discountLoadFailed,
            },
          ),
      ],
    );
  }

  Widget _scheduleFields(
    DiscountFormState state,
    bool editable,
    String locale,
  ) {
    final l10n = context.l10n;
    final schedule = state.draft.schedule;
    final timeFormat = ref.watch(timeFormatControllerProvider);
    // Without a schedule the start fields are empty; choosing a value sets
    // the schedule (today 09:00 for the other half).
    Widget pickerRow({
      required String dateLabel,
      required String timeLabel,
      required LocalDate? date,
      required TimeOfDayValue? time,
      required bool end,
    }) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: DiscountPickerField(
              fieldKey: end ? 'discount-end-date' : 'discount-start-date',
              label: dateLabel,
              value: date == null
                  ? l10n.discountSelectValue
                  : DiscountText.date(locale, date),
              onTap: editable ? () => _pickDate(state, end: end) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: DiscountPickerField(
              fieldKey: end ? 'discount-end-time' : 'discount-start-time',
              label: timeLabel,
              value: time == null
                  ? l10n.discountSelectValue
                  : DiscountText.time(locale, time, timeFormat),
              onTap: editable ? () => _pickTime(state, end: end) : null,
            ),
          ),
        ],
      ),
    );
    final hasEnd = schedule?.hasEnd ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pickerRow(
          dateLabel: l10n.discountStartDate,
          timeLabel: l10n.discountStartTime,
          date: schedule?.startDate,
          time: schedule?.startTime,
          end: false,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('discount-no-end'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: !hasEnd,
          title: Text(
            l10n.discountNoEndDate,
            style: const TextStyle(color: OrangeTheme.ink, fontSize: 16),
          ),
          onChanged: editable && schedule != null
              ? (noEnd) => _controller.setNoEndDate(noEnd: noEnd ?? false)
              : null,
        ),
        AnimatedSize(
          duration: DiscountSection.duration,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: hasEnd
              ? pickerRow(
                  dateLabel: l10n.discountEndDate,
                  timeLabel: l10n.discountEndTime,
                  date: schedule!.endDate,
                  time: schedule.endTime,
                  end: true,
                )
              : const SizedBox(width: double.infinity),
        ),
        if (schedule?.timezone != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.discountTimezone(schedule!.timezone!),
              style: const TextStyle(
                color: OrangeTheme.secondary,
                fontSize: 12,
              ),
            ),
          ),
        if (schedule != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('discount-schedule-clear'),
              onPressed: editable ? _controller.clearSchedule : null,
              child: Text(l10n.discountClearDateTime),
            ),
          ),
      ],
    );
  }
}
