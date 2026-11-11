import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_merge.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';

/// [saving] and [archiving] are the two writes of the form; while one runs,
/// every other action and leaving the form are blocked.
enum DiscountFormPhase { editing, saving, archiving, saved, archived }

/// What stops or stopped saving, beyond field errors.
enum DiscountFormProblem {
  /// Offline, missing permission or not offered by the shop.
  notAllowed,

  /// The product already has the maximum number of discounts.
  limitReached,

  /// The discount was changed elsewhere (`VERSION_CONFLICT`). The form keeps
  /// the entered values and shows the server's values
  /// ([DiscountFormState.conflict]); nothing is sent until the user resolves
  /// it.
  changed,

  /// Sent without a confirmed answer. Saving the same values again repeats
  /// the identical request (same `Idempotency-Key`), so it is applied once.
  uncertain,

  /// A create whose answer was lost did reach the server: the form now
  /// edits that discount (with the user's changes) instead of creating a
  /// second one. Nothing was sent.
  createdMeanwhile,

  /// The server refused it (a rule about the whole discount).
  refused,
}

/// An unresolved `VERSION_CONFLICT`: the latest server version and the
/// user's choices for parts both sides changed.
class DiscountFormConflict {
  const new({required this.latest, this.keepMine = const {}});

  /// The latest server version; its version guards the next save once the
  /// conflict is resolved.
  final Discount latest;

  /// Decided parts (`true` = keep the user's value).
  final Map<DiscountPart, bool> keepMine;
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
    this.conflict,
  });

  /// The product's current list price, for validation and the preview.
  final DiscountMoney regularPrice;
  final DiscountDraft draft;

  /// The stored discount (edit mode) the draft is based on. Its version is
  /// sent as `If-Match`.
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

  /// The discount the server confirmed (saved or archived).
  final Discount? saved;
  final bool limitReached;

  /// Set while a concurrent change waits for the user's resolution.
  final DiscountFormConflict? conflict;

  bool get editing => original != null;
  bool get busy =>
      phase == DiscountFormPhase.saving || phase == DiscountFormPhase.archiving;

  /// Client checks of the current draft.
  Map<String, DiscountIssue> get issues => draft.validate(regularPrice.cents);

  /// Client issues first; server issues for inputs left unchanged since.
  Map<String, DiscountIssue> get visibleIssues => {...serverIssues, ...issues};

  DraftPreview? get preview => draft.preview(regularPrice.cents);

  /// The merge of the user's draft with the latest server version, while a
  /// conflict is open.
  DiscountMerge? get merge {
    final open = conflict;
    final base = original;
    if (open == null || base == null) return null;
    return DiscountMerge(
      base: DiscountDraft.fromDiscount(base),
      mine: draft,
      theirs: DiscountDraft.fromDiscount(open.latest),
    );
  }

  /// Every part both sides changed is decided.
  bool get conflictDecided {
    final current = merge;
    final open = conflict;
    return current != null &&
        open != null &&
        current.conflicting.every(open.keepMine.containsKey);
  }

  bool get canSubmit =>
      phase == DiscountFormPhase.editing &&
      conflict == null &&
      issues.isEmpty &&
      !(limitReached && !editing) &&
      (original?.editable ?? true);

  /// Archive is possible for a stored, not archived discount while nothing
  /// else runs and no conflict is open.
  bool get canArchive =>
      phase == DiscountFormPhase.editing &&
      conflict == null &&
      original != null &&
      !original!.archived;

  DiscountFormState copy({
    DiscountMoney? regularPrice,
    DiscountDraft? draft,
    Discount? original,
    DiscountFormPhase? phase,
    Map<String, DiscountIssue>? serverIssues,
    Map<String, String>? serverMessages,
    DiscountFormProblem? problem,
    String? problemMessage,
    String? ruleCode,
    Discount? saved,
    bool? limitReached,
    DiscountFormConflict? conflict,
    bool keepProblem = false,
    bool keepConflict = true,
  }) => DiscountFormState(
    regularPrice: regularPrice ?? this.regularPrice,
    draft: draft ?? this.draft,
    original: original ?? this.original,
    phase: phase ?? this.phase,
    serverIssues: serverIssues ?? this.serverIssues,
    serverMessages: serverMessages ?? this.serverMessages,
    problem: problem ?? (keepProblem ? this.problem : null),
    problemMessage:
        problemMessage ?? (keepProblem ? this.problemMessage : null),
    ruleCode: ruleCode ?? (keepProblem ? this.ruleCode : null),
    saved: saved,
    limitReached: limitReached ?? this.limitReached,
    conflict: conflict ?? (keepConflict ? this.conflict : null),
  );
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
/// again and its answer is authoritative. Save and Archive are the form's
/// two writes: one at a time, each confirmed by the page and sent once.
class DiscountFormController extends AsyncNotifier<DiscountFormState> {
  new(this.args);
  final DiscountFormArgs args;
  int _generation = 0;

  /// Discounts that existed when the create form opened.
  Set<int> _knownIds = const {};

  /// A create sent without a confirmed answer: it may exist on the server.
  DiscountDraft? _unconfirmedCreate;

  @override
  Future<DiscountFormState> build() async {
    _generation++;
    final access = ref.read(discountAccessProvider(args.scope.manageAllowed));
    if (!access.read || !access.manage) throw discountUnavailable;
    final repository = ref.watch(discountRepositoryProvider);
    final id = args.discountId;
    if (id == null) {
      final list = await repository.list(args.scope.productId);
      _knownIds = {for (final discount in list.discounts) discount.id};
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

  /// Replaces the draft. Server errors of inputs that changed are dropped;
  /// an open conflict and an unsure outcome stay visible.
  void change(DiscountDraft Function(DiscountDraft draft) update) {
    final current = _editable;
    if (current == null) return;
    final draft = update(current.draft);
    final before = DiscountInputSnapshot(current.draft);
    final after = DiscountInputSnapshot(draft);
    final keep = switch (current.problem) {
      DiscountFormProblem.uncertain ||
      DiscountFormProblem.changed ||
      DiscountFormProblem.createdMeanwhile => true,
      _ => false,
    };
    state = AsyncData(
      current.copy(
        draft: draft,
        serverIssues: {
          for (final entry in current.serverIssues.entries)
            if (before.of(entry.key) == after.of(entry.key))
              entry.key: entry.value,
        },
        keepProblem: keep,
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
        current.copy(regularPrice: list.regularPrice, keepProblem: true),
      );
      ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    } on AppFailure {
      // The shown price stays; the server validates the save anyway.
    }
  }

  // --- Conflict resolution ------------------------------------------------

  /// Decides a part both sides changed (`true` keeps the user's value).
  void choose(DiscountPart part, {required bool keepMine}) {
    final current = _editable;
    final open = current?.conflict;
    if (current == null || open == null) return;
    state = AsyncData(
      current.copy(
        conflict: DiscountFormConflict(
          latest: open.latest,
          keepMine: {...open.keepMine, part: keepMine},
        ),
        keepProblem: true,
      ),
    );
  }

  /// Applies the merge once every conflicting part is decided: the draft
  /// becomes the latest server values plus the user's own changes, and the
  /// latest version guards the next save. Nothing is sent; the user reviews
  /// and saves again.
  void resolveConflict() {
    final current = _editable;
    final open = current?.conflict;
    final merge = current?.merge;
    if (current == null ||
        open == null ||
        merge == null ||
        !current.conflictDecided) {
      return;
    }
    state = AsyncData(
      DiscountFormState(
        regularPrice: open.latest.regularPrice,
        draft: merge.resolve(open.keepMine),
        original: open.latest,
        limitReached: current.limitReached,
      ),
    );
  }

  // --- Writes ------------------------------------------------------------

  /// Whether a confirmation may be shown now.
  bool get canConfirm {
    final current = _editable;
    return current != null && current.canSubmit && _writable;
  }

  /// Whether the archive confirmation may be shown now.
  bool get canArchive {
    final current = _editable;
    return current != null && current.canArchive && _writable;
  }

  static String _fingerprint(DiscountDraft draft) =>
      [for (final part in DiscountPart.values) draft.partKey(part)].join('|');

  /// Sends the confirmed draft once.
  ///
  /// After a create whose answer was lost, an identical retry repeats the
  /// same request (same `Idempotency-Key`, so the server applies it once).
  /// A changed draft is not sent until the product's discounts were read:
  /// if the lost create did reach the server, the form switches to editing
  /// that discount instead of creating a second one.
  Future<void> save() async {
    final current = _editable;
    if (current == null) return;
    if (!current.canSubmit || !_writable) {
      state = AsyncData(
        current.copy(
          problem: current.conflict != null
              ? DiscountFormProblem.changed
              : current.limitReached && !current.editing
              ? DiscountFormProblem.limitReached
              : DiscountFormProblem.notAllowed,
        ),
      );
      return;
    }
    final generation = ++_generation;
    final repository = ref.read(discountRepositoryProvider);
    state = AsyncData(
      current.copy(phase: DiscountFormPhase.saving, keepProblem: true),
    );
    try {
      final original = current.original;
      if (original == null) {
        final unconfirmed = _unconfirmedCreate;
        if (unconfirmed != null &&
            _fingerprint(unconfirmed) != _fingerprint(current.draft)) {
          final created = await _findUnconfirmedCreate(unconfirmed);
          if (!ref.mounted || generation != _generation) return;
          _unconfirmedCreate = null;
          if (created != null) {
            state = AsyncData(
              DiscountFormState(
                regularPrice: created.regularPrice,
                draft: current.draft,
                original: created,
                problem: DiscountFormProblem.createdMeanwhile,
              ),
            );
            ref.invalidate(
              productDiscountsControllerProvider(args.scope.productId),
            );
            return;
          }
        }
      }
      final saved = original == null
          ? await repository.create(args.scope.productId, current.draft)
          : await repository.update(original, current.draft);
      if (!ref.mounted || generation != _generation) return;
      _unconfirmedCreate = null;
      state = AsyncData(
        current.copy(phase: DiscountFormPhase.saved, saved: saved),
      );
      ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      if (current.original == null) {
        _unconfirmedCreate = _isUncertain(failure) ? current.draft : null;
      }
      await _failed(current, failure, generation);
    }
  }

  /// A discount the lost create made: new since the form opened and equal
  /// to what was sent. Throws when the list cannot be read (still unsure).
  Future<Discount?> _findUnconfirmedCreate(DiscountDraft sent) async {
    final list = await ref
        .read(discountRepositoryProvider)
        .list(args.scope.productId);
    final fingerprint = _fingerprint(sent);
    for (final discount in list.discounts) {
      if (!_knownIds.contains(discount.id) &&
          _fingerprint(DiscountDraft.fromDiscount(discount)) == fingerprint) {
        return discount;
      }
    }
    return null;
  }

  /// Archives the stored discount once (`DELETE /discounts/{id}` with its
  /// version). Save and leaving the form are blocked until it is answered;
  /// on failure the draft stays and the controls return.
  Future<void> archive() async {
    final current = _editable;
    if (current == null) return;
    if (!current.canArchive || !_writable) {
      state = AsyncData(current.copy(problem: DiscountFormProblem.notAllowed));
      return;
    }
    final generation = ++_generation;
    state = AsyncData(current.copy(phase: DiscountFormPhase.archiving));
    try {
      final archived = await ref
          .read(discountRepositoryProvider)
          .archive(current.original!);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        current.copy(phase: DiscountFormPhase.archived, saved: archived),
      );
      ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      await _failed(current, failure, generation);
    }
  }

  static bool _isUncertain(AppFailure failure) =>
      failure.code == null && failure.kind != FailureKind.cancelled;

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
        // The draft and its base stay; the server's values are shown and
        // nothing is sent until the user resolves the conflict.
        state = AsyncData(
          current.copy(
            phase: DiscountFormPhase.editing,
            problem: DiscountFormProblem.changed,
            conflict: DiscountFormConflict(latest: latest),
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
    final uncertain = _isUncertain(failure);
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
        conflict: current.conflict,
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
