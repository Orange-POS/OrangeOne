import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';

enum DiscountFormPhase { editing, saving, saved }

/// What stops or stopped saving, beyond field errors.
enum DiscountFormProblem {
  /// Offline, missing permission or not offered by the shop.
  notAllowed,

  /// The product already has the maximum number of discounts.
  limitReached,

  /// The discount was changed elsewhere (`VERSION_CONFLICT`); the form keeps
  /// the entered values over the latest version, nothing was written.
  changed,

  /// Sent without a confirmed answer. Saving the same values again repeats
  /// the identical request (same `Idempotency-Key`), so it is applied once.
  uncertain,

  /// The server refused it (a rule about the whole discount).
  refused,
}

class DiscountFormState {
  const new({
    required this.regularPrice,
    required this.draft,
    this.original,
    this.phase = DiscountFormPhase.editing,
    this.serverIssues = const {},
    this.serverMessages = const {},
    this.problem,
    this.problemMessage,
    this.ruleCode,
    this.saved,
    this.limitReached = false,
  });

  /// The product's current list price, for validation and the preview.
  final DiscountMoney regularPrice;
  final DiscountDraft draft;

  /// The stored discount (edit mode), fresh from the server.
  final Discount? original;
  final DiscountFormPhase phase;

  /// Server field errors by input ([DiscountField.inputOf]).
  final Map<String, DiscountIssue> serverIssues;

  /// Server texts for detail codes the app has no own text for.
  final Map<String, String> serverMessages;
  final DiscountFormProblem? problem;

  /// The server's display-safe text for [problem], when it sent one.
  final String? problemMessage;

  /// The code of a refused rule about the whole discount
  /// (`PRODUCT_NOT_DISCOUNTABLE`, `DISCOUNT_ARCHIVED`, …), translated by the
  /// page when known.
  final String? ruleCode;

  /// The discount the server confirmed.
  final Discount? saved;
  final bool limitReached;

  bool get editing => original != null;
  bool get busy => phase == DiscountFormPhase.saving;

  /// Client checks of the current draft.
  Map<String, DiscountIssue> get issues => draft.validate(regularPrice.cents);

  /// Client issues first; server issues for inputs left unchanged since.
  Map<String, DiscountIssue> get visibleIssues => {...serverIssues, ...issues};

  DraftPreview? get preview => draft.preview(regularPrice.cents);

  bool get canSubmit =>
      phase == DiscountFormPhase.editing &&
      issues.isEmpty &&
      !(limitReached && !editing) &&
      (original?.editable ?? true);
}

typedef DiscountFormArgs = ({DiscountScope scope, int? discountId});

final AsyncNotifierProviderFamily<
  DiscountFormController,
  DiscountFormState,
  DiscountFormArgs
>
discountFormControllerProvider = AsyncNotifierProvider.autoDispose
    .family<DiscountFormController, DiscountFormState, DiscountFormArgs>(
      DiscountFormController.new,
      name: 'discountFormControllerProvider',
      retry: (count, error) => null,
    );

/// The shared Create/Edit Discount form. Saving needs the Feature Resolver's
/// manage access, a connection and a valid draft; the server validates
/// again and its answer is authoritative.
class DiscountFormController extends AsyncNotifier<DiscountFormState> {
  new(this.args);
  final DiscountFormArgs args;
  int _generation = 0;

  @override
  Future<DiscountFormState> build() async {
    _generation++;
    final access = ref.read(discountAccessProvider(args.scope.manageAllowed));
    if (!access.read || !access.manage) throw discountUnavailable;
    final repository = ref.watch(discountRepositoryProvider);
    final id = args.discountId;
    if (id == null) {
      final list = await repository.list(args.scope.productId);
      return DiscountFormState(
        regularPrice: list.regularPrice,
        draft: const DiscountDraft(),
        limitReached: list.limitReached,
      );
    }
    // A fresh read: its version guards the update (If-Match).
    final discount = await repository.get(id);
    if (discount.productId != args.scope.productId) throw invalidResponse;
    return DiscountFormState(
      regularPrice: discount.regularPrice,
      draft: DiscountDraft.fromDiscount(discount),
      original: discount,
    );
  }

  DiscountFormState? get _editable {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        current.phase != DiscountFormPhase.editing) {
      return null;
    }
    return current;
  }

  /// Replaces the draft. Server errors of inputs that changed are dropped.
  void change(DiscountDraft Function(DiscountDraft draft) update) {
    final current = _editable;
    if (current == null) return;
    final draft = update(current.draft);
    final before = DiscountInputSnapshot(current.draft);
    final after = DiscountInputSnapshot(draft);
    state = AsyncData(
      DiscountFormState(
        regularPrice: current.regularPrice,
        draft: draft,
        original: current.original,
        limitReached: current.limitReached,
        serverIssues: {
          for (final entry in current.serverIssues.entries)
            if (before.of(entry.key) == after.of(entry.key))
              entry.key: entry.value,
        },
        serverMessages: current.serverMessages,
        problem: current.problem == DiscountFormProblem.uncertain
            ? DiscountFormProblem.uncertain
            : null,
      ),
    );
  }

  bool get _writable =>
      ref.read(discountAccessProvider(args.scope.manageAllowed)).canWrite;

  /// A new schedule starts today at 09:00 without an end.
  static DiscountSchedule _defaultSchedule(DateTime now) => DiscountSchedule(
    startDate: LocalDate(now.year, now.month, now.day),
    startTime: const TimeOfDayValue(9, 0),
  );

  /// Sets the start (or, with [end], the end) [date] and/or [time] of the
  /// schedule. Without a schedule one is started (today 09:00); an end that
  /// is not set yet starts from the start values.
  void setSchedulePart({
    required bool end,
    LocalDate? date,
    TimeOfDayValue? time,
  }) {
    change((draft) {
      final old = draft.schedule ?? _defaultSchedule(DateTime.now());
      return draft.withSchedule(
        end
            ? DiscountSchedule(
                startDate: old.startDate,
                startTime: old.startTime,
                endDate: date ?? old.endDate ?? old.startDate,
                endTime: time ?? old.endTime ?? old.startTime,
                timezone: old.timezone,
              )
            : DiscountSchedule(
                startDate: date ?? old.startDate,
                startTime: time ?? old.startTime,
                endDate: old.endDate,
                endTime: old.endTime,
                timezone: old.timezone,
              ),
      );
    });
  }

  /// "No End Date": removes the end, or starts one at the start values.
  void setNoEndDate({required bool noEnd}) {
    change((draft) {
      final schedule = draft.schedule;
      if (schedule == null) return draft;
      return draft.withSchedule(
        DiscountSchedule(
          startDate: schedule.startDate,
          startTime: schedule.startTime,
          endDate: noEnd ? null : schedule.startDate,
          endTime: noEnd ? null : schedule.startTime,
          timezone: schedule.timezone,
        ),
      );
    });
  }

  /// Removes the date & time limits.
  void clearSchedule() => change((draft) => draft.withSchedule(null));

  /// Reads the product's regular price again after it was changed on the
  /// price screen. The draft, the stored version (If-Match) and all
  /// messages stay; only validation and the preview follow the new price.
  Future<void> refreshRegularPrice() async {
    if (_editable == null) return;
    final generation = _generation;
    try {
      final list = await ref
          .read(discountRepositoryProvider)
          .list(args.scope.productId);
      final current = _editable;
      if (!ref.mounted || generation != _generation || current == null) {
        return;
      }
      state = AsyncData(
        DiscountFormState(
          regularPrice: list.regularPrice,
          draft: current.draft,
          original: current.original,
          serverIssues: current.serverIssues,
          serverMessages: current.serverMessages,
          problem: current.problem,
          problemMessage: current.problemMessage,
          ruleCode: current.ruleCode,
          limitReached: current.limitReached,
        ),
      );
      ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    } on AppFailure {
      // The shown price stays; the server validates the save anyway.
    }
  }

  /// Whether a confirmation may be shown now.
  bool get canConfirm {
    final current = _editable;
    return current != null && current.canSubmit && _writable;
  }

  /// Sends the confirmed draft once.
  Future<void> save() async {
    final current = _editable;
    if (current == null) return;
    if (!current.canSubmit || !_writable) {
      state = AsyncData(
        _with(
          current,
          problem: current.limitReached && !current.editing
              ? DiscountFormProblem.limitReached
              : DiscountFormProblem.notAllowed,
        ),
      );
      return;
    }
    final generation = ++_generation;
    final repository = ref.read(discountRepositoryProvider);
    state = AsyncData(_with(current, phase: DiscountFormPhase.saving));
    try {
      final original = current.original;
      final saved = original == null
          ? await repository.create(args.scope.productId, current.draft)
          : await repository.update(original, current.draft);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        _with(current, phase: DiscountFormPhase.saved, saved: saved),
      );
      ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      await _failed(current, failure, generation);
    }
  }

  Future<void> _failed(
    DiscountFormState current,
    AppFailure failure,
    int generation,
  ) async {
    if (failure.code == 'VERSION_CONFLICT' && current.original != null) {
      try {
        final latest = await ref
            .read(discountRepositoryProvider)
            .get(current.original!.id);
        if (!ref.mounted || generation != _generation) return;
        state = AsyncData(
          DiscountFormState(
            regularPrice: latest.regularPrice,
            draft: current.draft,
            original: latest,
            problem: DiscountFormProblem.changed,
          ),
        );
        return;
      } on AppFailure {
        if (!ref.mounted || generation != _generation) return;
      }
    }
    final issues = <String, DiscountIssue>{};
    final messages = <String, String>{};
    String? ruleCode;
    String? ruleMessage;
    for (final error in failure.fieldErrors) {
      if (error.field.isEmpty) {
        ruleCode ??= error.code;
        ruleMessage ??= error.message;
        continue;
      }
      final input = DiscountField.inputOf(error.field);
      final issue = DiscountIssue.fromServerCode(error.code);
      if (issue != null) {
        issues[input] = issue;
      } else if (error.message != null) {
        messages[input] = error.message!;
      }
    }
    final uncertain =
        failure.code == null && failure.kind != FailureKind.cancelled;
    final limit = failure.fieldErrors.any(
      (error) => error.code == 'DISCOUNT_LIMIT_REACHED',
    );
    state = AsyncData(
      DiscountFormState(
        regularPrice: current.regularPrice,
        draft: current.draft,
        original: current.original,
        limitReached: current.limitReached || limit,
        serverIssues: issues,
        serverMessages: messages,
        problem: uncertain
            ? DiscountFormProblem.uncertain
            : limit
            ? DiscountFormProblem.limitReached
            : failure.code == 'VERSION_CONFLICT'
            ? DiscountFormProblem.changed
            : issues.isEmpty && messages.isEmpty
            ? DiscountFormProblem.refused
            : null,
        problemMessage: uncertain ? null : ruleMessage ?? failure.message,
        ruleCode: uncertain ? null : ruleCode,
      ),
    );
  }

  DiscountFormState _with(
    DiscountFormState current, {
    DiscountFormPhase? phase,
    DiscountFormProblem? problem,
    Discount? saved,
  }) => DiscountFormState(
    regularPrice: current.regularPrice,
    draft: current.draft,
    original: current.original,
    phase: phase ?? current.phase,
    serverIssues: current.serverIssues,
    serverMessages: current.serverMessages,
    problem: problem,
    saved: saved,
    limitReached: current.limitReached,
  );
}

/// The input values of a draft, to tell which server errors are stale.
class DiscountInputSnapshot {
  const new(this.draft);
  final DiscountDraft draft;

  Object? of(String input) => switch (input) {
    DiscountField.type => draft.type,
    DiscountField.fixedPrice => draft.fixedPrice,
    DiscountField.percent => draft.percent,
    DiscountField.bundleQuantity => draft.bundleQuantity,
    DiscountField.bundlePrice => draft.bundlePrice,
    DiscountField.startDate =>
      '${draft.schedule?.startDate.iso} ${draft.schedule?.startTime.formatted}',
    DiscountField.endDate =>
      '${draft.schedule?.endDate?.iso} ${draft.schedule?.endTime?.formatted}',
    DiscountField.weekdays => draft.repeat.weekdays.map((d) => d.name).join(),
    DiscountField.annualDate =>
      '${draft.repeat.annualDate?.month}-${draft.repeat.annualDate?.day}',
    DiscountField.minimumQuantity => draft.minimumQuantity,
    _ => null,
  };
}
