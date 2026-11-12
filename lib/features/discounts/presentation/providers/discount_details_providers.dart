import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';

/// State changes offered on Discount Details. Pause is not archive: a
/// paused discount keeps all its values and stays editable.
enum DiscountAction { pause, resume, archive }

/// Why an action did not complete; the page shows a localised text.
enum DiscountActionProblem {
  /// Offline, missing permission or not offered by the shop.
  notAllowed,

  /// Someone changed the discount meanwhile (`VERSION_CONFLICT`): the latest
  /// values are shown and nothing was written.
  changed,

  /// Sent, but no confirmed answer (network, timeout, unreadable reply).
  /// Repeating the same action sends the identical request again.
  uncertain,

  /// The server refused it; [DiscountDetailsState.serverMessage] says why.
  refused,
}

class DiscountDetailsState {
  const new({
    required this.discount,
    this.busy,
    this.problem,
    this.serverMessage,
    this.completed,
  });

  final Discount discount;

  /// The action in progress; every action is blocked meanwhile.
  final DiscountAction? busy;
  final DiscountActionProblem? problem;
  final String? serverMessage;

  /// The last action the server confirmed.
  final DiscountAction? completed;
}

typedef DiscountDetailsArgs = ({DiscountScope scope, int discountId});

final AsyncNotifierProviderFamily<
  DiscountDetailsController,
  DiscountDetailsState,
  DiscountDetailsArgs
>
discountDetailsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<
      DiscountDetailsController,
      DiscountDetailsState,
      DiscountDetailsArgs
    >(
      DiscountDetailsController.new,
      name: 'discountDetailsControllerProvider',
      retry: (count, error) => null,
    );

class DiscountDetailsController extends AsyncNotifier<DiscountDetailsState> {
  new(this.args);
  final DiscountDetailsArgs args;
  int _generation = 0;

  @override
  Future<DiscountDetailsState> build() async {
    _generation++;
    if (!ref.read(discountAccessProvider(args.scope.manageAllowed)).read) {
      throw discountUnavailable;
    }
    final discount = await ref
        .watch(discountRepositoryProvider)
        .get(args.discountId);
    if (discount.productId != args.scope.productId) throw invalidResponse;
    return DiscountDetailsState(discount: discount);
  }

  bool _allowed(Discount discount, DiscountAction action) {
    if (!ref.read(discountAccessProvider(args.scope.manageAllowed)).canWrite) {
      return false;
    }
    return switch (action) {
      DiscountAction.pause => discount.canPause,
      DiscountAction.resume => discount.canResume,
      DiscountAction.archive => !discount.archived,
    };
  }

  /// Whether [action] can be confirmed now.
  bool canRun(DiscountAction action) {
    final current = state.value;
    return !state.isLoading &&
        current != null &&
        current.busy == null &&
        _allowed(current.discount, action);
  }

  /// Runs a confirmed [action] once. Never retried automatically and never
  /// overwrites a newer version.
  Future<void> run(DiscountAction action) async {
    final current = state.value;
    if (!canRun(action) || current == null) {
      if (current != null && current.busy == null) {
        state = AsyncData(
          DiscountDetailsState(
            discount: current.discount,
            problem: DiscountActionProblem.notAllowed,
          ),
        );
      }
      return;
    }
    final generation = ++_generation;
    final repository = ref.read(discountRepositoryProvider);
    state = AsyncData(
      DiscountDetailsState(discount: current.discount, busy: action),
    );
    try {
      final updated = await switch (action) {
        DiscountAction.pause => repository.pause(current.discount),
        DiscountAction.resume => repository.resume(current.discount),
        DiscountAction.archive => repository.archive(current.discount),
      };
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        DiscountDetailsState(discount: updated, completed: action),
      );
      ref.invalidate(productDiscountsControllerProvider(args.scope.productId));
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      await _failed(current.discount, failure, generation);
    }
  }

  Future<void> _failed(
    Discount discount,
    AppFailure failure,
    int generation,
  ) async {
    if (failure.code == 'VERSION_CONFLICT') {
      // Show the latest values; the user decides again.
      try {
        final latest = await ref
            .read(discountRepositoryProvider)
            .get(discount.id);
        if (!ref.mounted || generation != _generation) return;
        state = AsyncData(
          DiscountDetailsState(
            discount: latest,
            problem: DiscountActionProblem.changed,
          ),
        );
        ref.invalidate(
          productDiscountsControllerProvider(args.scope.productId),
        );
        return;
      } on AppFailure {
        if (!ref.mounted || generation != _generation) return;
      }
    }
    final uncertain =
        failure.code == null && failure.kind != FailureKind.cancelled;
    state = AsyncData(
      DiscountDetailsState(
        discount: discount,
        problem: uncertain
            ? DiscountActionProblem.uncertain
            : failure.code == 'VERSION_CONFLICT'
            ? DiscountActionProblem.changed
            : DiscountActionProblem.refused,
        serverMessage: uncertain ? null : failure.message,
      ),
    );
  }

  /// Reads the discount again (pull to refresh, after an unsure outcome).
  Future<void> refresh() async {
    final current = state.value;
    if (current?.busy != null) return;
    ref.read(readCacheProvider)?.retryRead();
    ref.invalidateSelf();
    await future.then<void>((_) {}, onError: (Object _) {});
  }
}
