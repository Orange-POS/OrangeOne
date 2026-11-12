import 'package:flutter/material.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_merge.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Confirms the replay of an unresolved earlier create before it is sent.
///
/// The replay sends the earlier request unchanged and may create it now, so
/// every term of that offer is shown (value, start and end, repeat, minimum
/// quantity), not only its amount. Terms the edited draft changed are marked
/// with the edited value; the edit itself is never sent by this dialog.
class DiscountReplayDialog extends StatelessWidget {
  const new({
    required this.original,
    required this.edited,
    required this.currency,
    super.key,
  });

  /// The earlier request, exactly as it will be sent again.
  final DiscountDraft original;

  /// The form's current draft, kept for its own confirmation.
  final DiscountDraft edited;
  final String currency;

  static Future<bool> show(
    BuildContext context, {
    required DiscountDraft original,
    required DiscountDraft edited,
    required String currency,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => DiscountReplayDialog(
          original: original,
          edited: edited,
          currency: currency,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return AlertDialog(
      title: Text(l10n.discountReplayTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.discountReplayIntro),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                l10n.discountReplayOriginal,
                style: const TextStyle(
                  color: OrangeTheme.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final part in DiscountPart.values)
              _Term(
                key: Key('discount-replay-${part.name}'),
                label: DiscountText.partName(l10n, part),
                value: DiscountText.partValue(
                  l10n,
                  locale,
                  original,
                  part,
                  currency,
                ),
                edited: original.partKey(part) == edited.partKey(part)
                    ? null
                    : DiscountText.partValue(
                        l10n,
                        locale,
                        edited,
                        part,
                        currency,
                      ),
              ),
            const SizedBox(height: 8),
            Text(l10n.discountReplayKept),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('discount-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.discountReplayRetry),
        ),
      ],
    );
  }
}

/// One term of the earlier offer; [edited] is the draft's differing value.
class _Term extends StatelessWidget {
  const new({required this.label, required this.value, this.edited, super.key});

  final String label;
  final String value;
  final String? edited;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final changed = edited;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: changed == null ? const Color(0xFFF1F3F4) : OrangeTheme.pale,
        borderRadius: BorderRadius.circular(12),
        border: changed == null
            ? null
            : Border.all(color: OrangeTheme.dark, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: OrangeTheme.secondary, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: OrangeTheme.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (changed != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.discountReplayYourEdit(changed),
              style: const TextStyle(
                color: OrangeTheme.dark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
