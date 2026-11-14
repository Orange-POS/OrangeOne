import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/idempotency_keys.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_merge.dart';
import 'package:orange_one/features/discounts/domain/entities/pending_discount_create.dart';
import 'package:orange_one/features/discounts/domain/repositories/discount_repository.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_details_providers.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';

/// [saving], [archiving] and [toggling] (pause or resume) are the writes of
/// the form; while one runs, every other action and leaving the form are
/// blocked.
enum DiscountFormPhase { editing, saving, archiving, toggling, saved, archived }

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

  /// An earlier create for this product (in this session, also from a form
  /// that was closed) has no confirmed answer. Saving first replays it
  /// exactly as sent; nothing else is created before its outcome is known.
  pendingCreate,

  /// The server refused the earlier create when it was retried: it never
  /// committed. Nothing else was sent; the edited draft is kept and is
  /// created only after its own confirmation.
  originalRefused,

  /// That earlier create can no longer be confirmed automatically (the
  /// server's idempotency record may have expired). Nothing is sent until
  /// the user checks the product's discounts and decides.
  pendingExpired,

  /// The server accepted that earlier create, but its result could not be
  /// read: it was most likely created. No other create is sent until the
  /// user checked the product's discounts and resolves it.
  pendingCommitted,

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
    this.toggled,
    this.limitReached = false,
    this.recoverable = false,
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

  /// The pause or resume the server just confirmed (the form stays open on
  /// the server's reply); null after any other change.
  final DiscountAction? toggled;
  final bool limitReached;

  /// An earlier create of this product is unresolved and can still be
  /// replayed. At the limit only that replay may be sent (its slot may
  /// already be taken by it); a fresh create stays blocked.
  final bool recoverable;

  /// Set while a concurrent change waits for the user's resolution.
  final DiscountFormConflict? conflict;

  bool get editing => original != null;
  bool get busy =>
      phase == DiscountFormPhase.saving ||
      phase == DiscountFormPhase.archiving ||
      phase == DiscountFormPhase.toggling;

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
      problem != DiscountFormProblem.pendingExpired &&
      problem != DiscountFormProblem.pendingCommitted &&
      issues.isEmpty &&
      !(limitReached && !editing && !recoverable) &&
      (original?.editable ?? true);

  /// Archive is possible for a stored, not archived discount while nothing
  /// else runs and no conflict is open.
  bool get canArchive =>
      phase == DiscountFormPhase.editing &&
      conflict == null &&
      original != null &&
      !original!.archived;

  /// Pause or resume of the stored discount, under the same conditions as
  /// archive and only when the server allows it ([Discount.canPause],
  /// [Discount.canResume]).
  bool get canToggle =>
      canArchive &&
      (original!.paused ? original!.canResume : original!.canPause);

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
    DiscountAction? toggled,
    bool? limitReached,
    bool? recoverable,
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
    toggled: toggled,
    limitReached: limitReached ?? this.limitReached,
    recoverable: recoverable ?? this.recoverable,
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

  @override
  Future<DiscountFormState> build() async {
    _generation++;
    final access = ref.read(discountAccessProvider(args.scope.manageAllowed));
    if (!access.read || !access.manage) throw discountUnavailable;
    final repository = ref.watch(discountRepositoryProvider);
    final id = args.discountId;
    if (id == null) {
      final list = await repository.list(args.scope.productId);
      // An unresolved create of this product (also from a form closed
      // since) comes back with its values, and its guard is restored.
      final pending = repository.pendingCreate(args.scope.productId);
      return DiscountFormState(
        regularPrice: list.regularPrice,
        draft: pending?.draft ?? const DiscountDraft(),
        limitReached: list.limitReached,
        recoverable: pending?.replayable ?? false,
        problem: _pendingProblem(pending),
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
      DiscountFormProblem.createdMeanwhile ||
      DiscountFormProblem.pendingCreate ||
      DiscountFormProblem.pendingExpired ||
      DiscountFormProblem.pendingCommitted ||
      DiscountFormProblem.originalRefused => true,
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

  /// The earlier create a Save would replay first, when its values differ
  /// from the current draft (a formatting-only change does not count). The
  /// page then confirms that original offer, not the edited one: if it
  /// never reached the server, the replay creates it.
  PendingDiscountCreate? get pendingReplay {
    final current = _editable;
    if (current == null || current.editing) return null;
    final pending = ref
        .read(discountRepositoryProvider)
        .pendingCreate(args.scope.productId);
    if (pending == null || !pending.replayable) return null;
    return _fingerprint(pending.draft) == _fingerprint(current.draft)
        ? null
        : pending;
  }

  /// Whether the archive confirmation may be shown now.
  bool get canArchive {
    final current = _editable;
    return current != null && current.canArchive && _writable;
  }

  /// Whether the pause/resume confirmation may be shown now.
  bool get canToggle {
    final current = _editable;
    return current != null && current.canToggle && _writable;
  }

  static String _fingerprint(DiscountDraft draft) =>
      [for (final part in DiscountPart.values) draft.partKey(part)].join('|');

  /// Whether the outcome of a write is still open after [failure]: no
  /// server decision about the write itself (transport failure,
  /// cancellation, authentication or rate limit).
  static bool _outcomeOpen(AppFailure failure) =>
      !IdempotencyKeys.settles(failure);

  /// Sends the confirmed draft once.
  ///
  /// A create whose answer was lost stays pending in the session (the
  /// repository keeps it exactly as sent, also after this form closes). Any
  /// next save of a new discount for the product first replays it unchanged
  /// (same payload, same `Idempotency-Key`): the server returns what it
  /// committed, or runs it now if it never did, so its outcome is known
  /// before anything else is written. A list read never decides it.
  /// - Same values (also "20" and "20.00"): the replay is the save.
  /// - Changed values: the page confirms the original offer first
  ///   ([pendingReplay]). If the replay created the discount, the form edits
  ///   it with the changes ([DiscountFormProblem.createdMeanwhile]); if the
  ///   server refused it ([DiscountFormProblem.originalRefused]), nothing
  ///   else is sent. Either way the edited terms need their own Save.
  /// - No answer again: it stays pending, unchanged.
  Future<void> save() async {
    final current = _editable;
    if (current == null) return;
    if (!current.canSubmit || !_writable) {
      state = AsyncData(
        current.copy(
          problem: current.conflict != null
              ? DiscountFormProblem.changed
              : current.problem == DiscountFormProblem.pendingExpired ||
                    current.problem == DiscountFormProblem.pendingCommitted
              ? current.problem
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
    final original = current.original;
    if (original != null) {
      try {
        final saved = await repository.update(original, current.draft);
        if (!ref.mounted || generation != _generation) return;
        _saved(current, saved);
      } on AppFailure catch (failure) {
        if (!ref.mounted || generation != _generation) return;
        await _failed(current, failure, generation);
      }
      return;
    }
    final productId = args.scope.productId;
    final pending = repository.pendingCreate(productId);
    if (pending == null) {
      await _create(current, repository, generation);
      return;
    }
    if (!pending.replayable) {
      state = AsyncData(
        current.copy(problem: _pendingProblem(pending), recoverable: false),
      );
      return;
    }
    final Discount confirmed;
    try {
      confirmed = await repository.resolvePendingCreate(productId);
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      if (_outcomeOpen(failure) ||
          failure.code == DiscountRefusal.pendingCreateExpired ||
          failure.code == DiscountRefusal.pendingCreateCommitted) {
        // Still unknown: the original request stays pending as sent.
        await _failed(current, failure, generation);
        return;
      }
      // The server refused the original request: it never committed.
      if (_fingerprint(pending.draft) == _fingerprint(current.draft)) {
        await _failed(current, failure, generation);
        return;
      }
      // The edited terms were not confirmed for themselves: they wait for
      // their own Save and confirmation.
      state = AsyncData(
        current.copy(
          phase: DiscountFormPhase.editing,
          problem: DiscountFormProblem.originalRefused,
          recoverable: false,
        ),
      );
      _pendingChanged();
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    if (_fingerprint(pending.draft) == _fingerprint(current.draft)) {
      _saved(current, confirmed);
      return;
    }
    // The original request created the discount: edit it with the changes
    // instead of creating a second one. Nothing else was sent.
    state = AsyncData(
      DiscountFormState(
        regularPrice: confirmed.regularPrice,
        draft: current.draft,
        original: confirmed,
        problem: DiscountFormProblem.createdMeanwhile,
      ),
    );
    ref.invalidate(productDiscountsControllerProvider(productId));
    _pendingChanged();
  }

  /// Creates [current]'s draft. An open outcome stays pending in the
  /// repository exactly as sent.
  Future<void> _create(
    DiscountFormState current,
    DiscountRepository repository,
    int generation,
  ) async {
    try {
      final saved = await repository.create(
        args.scope.productId,
        current.draft,
      );
      if (!ref.mounted || generation != _generation) return;
      _saved(current, saved);
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      await _failed(current, failure, generation);
    }
  }

  /// After the user checked the product's discounts: drops an earlier
  /// create that can no longer be confirmed automatically, so this draft
  /// can be created. Only for [DiscountFormProblem.pendingExpired] and
  /// [DiscountFormProblem.pendingCommitted] (the user's explicit decision).
  void discardExpiredPendingCreate() {
    final current = _editable;
    if (current == null ||
        (current.problem != DiscountFormProblem.pendingExpired &&
            current.problem != DiscountFormProblem.pendingCommitted)) {
      return;
    }
    ref
        .read(discountRepositoryProvider)
        .discardPendingCreate(args.scope.productId);
    state = AsyncData(current.copy(recoverable: false));
    _pendingChanged();
  }

  /// The session's pending create of this product may have changed
  /// (settled, refused or discarded): entry points that offer its recovery,
  /// such as a list still mounted under this form, read it again.
  void _pendingChanged() =>
      ref.invalidate(pendingDiscountCreateProvider(args.scope.productId));

  /// The form problem that describes [pending], if any.
  static DiscountFormProblem? _pendingProblem(PendingDiscountCreate? pending) =>
      pending == null
      ? null
      : pending.committed
      ? DiscountFormProblem.pendingCommitted
      : pending.replayable
      ? DiscountFormProblem.pendingCreate
      : DiscountFormProblem.pendingExpired;

  /// Whether this product's unresolved create can still be replayed.
  bool get _recoverable =>
      args.discountId == null &&
      (ref
              .read(discountRepositoryProvider)
              .pendingCreate(args.scope.productId)
              ?.replayable ??
          false);

  void _saved(DiscountFormState current, Discount saved) {
    state = AsyncData(
      current.copy(phase: DiscountFormPhase.saved, saved: saved),
    );
    ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    _pendingChanged();
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

  /// Pauses or resumes the stored discount once (`POST
  /// /discounts/{id}/pause|resume` with its version). Save, Archive and
  /// leaving the form are blocked until it is answered. On success the form
  /// stays open on the server's reply (its version guards the next save)
  /// and keeps the entered values; on failure the draft stays.
  Future<void> toggle() async {
    final current = _editable;
    if (current == null) return;
    if (!current.canToggle || !_writable) {
      state = AsyncData(current.copy(problem: DiscountFormProblem.notAllowed));
      return;
    }
    final generation = ++_generation;
    final original = current.original!;
    final action = original.paused
        ? DiscountAction.resume
        : DiscountAction.pause;
    state = AsyncData(current.copy(phase: DiscountFormPhase.toggling));
    try {
      final repository = ref.read(discountRepositoryProvider);
      final updated = action == DiscountAction.pause
          ? await repository.pause(original)
          : await repository.resume(original);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        current.copy(
          phase: DiscountFormPhase.editing,
          original: updated,
          toggled: action,
        ),
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
    // A refused create or replay settles it; an open outcome keeps it.
    _pendingChanged();
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
    if (failure.code == DiscountRefusal.pendingCreate ||
        failure.code == DiscountRefusal.pendingCreateExpired ||
        failure.code == DiscountRefusal.pendingCreateCommitted) {
      state = AsyncData(
        current.copy(
          phase: DiscountFormPhase.editing,
          problem: switch (failure.code) {
            DiscountRefusal.pendingCreate => DiscountFormProblem.pendingCreate,
            DiscountRefusal.pendingCreateCommitted =>
              DiscountFormProblem.pendingCommitted,
            _ => DiscountFormProblem.pendingExpired,
          },
          recoverable: _recoverable,
        ),
      );
      // The list shows a create the server accepted.
      if (failure.code == DiscountRefusal.pendingCreateCommitted) {
        ref.invalidate(
          productDiscountsControllerProvider(args.scope.productId),
        );
      }
      return;
    }
    final uncertain =
        _outcomeOpen(failure) &&
        failure.kind != FailureKind.unauthenticated &&
        failure.kind != FailureKind.cancelled;
    final limit = failure.fieldErrors.any(
      (error) => error.code == 'DISCOUNT_LIMIT_REACHED',
    );
    state = AsyncData(
      DiscountFormState(
        regularPrice: current.regularPrice,
        draft: current.draft,
        original: current.original,
        limitReached: current.limitReached || limit,
        recoverable: _recoverable,
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
    // The server may have committed it: lists and counts read again (a
    // committed create can take the last slot; the list then offers only
    // the recovery of the pending create).
    if (uncertain) {
      ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    }
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
