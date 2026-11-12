import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_details_providers.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';

/// The pause/resume switch of the discount list cards.
class DiscountToggleState {
  const new({this.busyId, this.problem, this.serverMessage, this.completed});

  /// The discount being paused or resumed; every switch is blocked
  /// meanwhile, so only one write is in flight.
  final int? busyId;
  final DiscountActionProblem? problem;
  final String? serverMessage;

  /// The last action the server confirmed.
  final DiscountAction? completed;
}

final NotifierProviderFamily<
  DiscountToggleController,
  DiscountToggleState,
  DiscountScope
>
discountToggleControllerProvider = NotifierProvider.autoDispose
    .family<DiscountToggleController, DiscountToggleState, DiscountScope>(
      DiscountToggleController.new,
      name: 'discountToggleControllerProvider',
    );

class DiscountToggleController extends Notifier<DiscountToggleState> {
  new(this.scope);
  final DiscountScope scope;
  int _generation = 0;

  @override
  DiscountToggleState build() => const DiscountToggleState();

  /// What the switch of [discount] does: resume a paused one, otherwise
  /// pause it.
  static DiscountAction actionFor(Discount discount) =>
      discount.paused ? DiscountAction.resume : DiscountAction.pause;

  /// Whether the switch of [discount] can be confirmed now.
  bool canToggle(Discount discount) {
    if (state.busyId != null) return false;
    if (!ref.read(discountAccessProvider(scope.manageAllowed)).canWrite) {
      return false;
    }
    return discount.paused ? discount.canResume : discount.canPause;
  }

  /// Pauses or resumes a confirmed [discount] once (`POST
  /// /discounts/{id}/pause|resume`). Never retried automatically and never
  /// overwrites a newer version; the list shows the server's reply.
  Future<void> toggle(Discount discount) async {
    final action = actionFor(discount);
    if (!canToggle(discount)) {
      if (state.busyId == null) {
        state = const DiscountToggleState(
          problem: DiscountActionProblem.notAllowed,
        );
      }
      return;
    }
    final generation = ++_generation;
    final repository = ref.read(discountRepositoryProvider);
    final list = productDiscountsControllerProvider(scope.productId);
    state = DiscountToggleState(busyId: discount.id);
    try {
      final updated = action == DiscountAction.pause
          ? await repository.pause(discount)
          : await repository.resume(discount);
      if (!ref.mounted || generation != _generation) return;
      state = DiscountToggleState(completed: action);
      ref.read(list.notifier).replace(updated);
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      if (failure.code == 'VERSION_CONFLICT') {
        // Show the latest values; the user decides again.
        state = const DiscountToggleState(
          problem: DiscountActionProblem.changed,
        );
        ref.invalidate(list);
        return;
      }
      // No server decision (no answer, or the request was cancelled while
      // in flight): the server may have paused or resumed it already.
      final uncertain = failure.code == null;
      state = DiscountToggleState(
        problem: uncertain
            ? DiscountActionProblem.uncertain
            : DiscountActionProblem.refused,
        serverMessage: uncertain ? null : failure.message,
      );
      // Show what the server holds now instead of the state before the write.
      if (uncertain) ref.invalidate(list);
    }
  }
}
