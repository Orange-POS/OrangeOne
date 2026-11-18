import 'package:flutter/material.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_merge.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Shown after `VERSION_CONFLICT`: what the server has now, part by part.
/// Parts only the server changed are taken over; for parts both sides
/// changed the user picks Keep mine or Use saved. [onApply] is enabled once
/// every such part is decided; nothing is sent from here.
class DiscountConflictPanel extends StatelessWidget {
  const new({
    required this.merge,
    required this.keepMine,
    required this.currency,
    required this.onChoose,
    required this.onApply,
    super.key,
  });

  final DiscountMerge merge;
  final Map<DiscountPart, bool> keepMine;
  final String currency;
  final void Function(DiscountPart part, {required bool keepMine})? onChoose;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final conflicting = merge.conflicting;
    String value(DiscountPart part, {required bool mine}) =>
        DiscountText.partValue(
          l10n,
          locale,
          mine ? merge.mine : merge.theirs,
          part,
          currency,
        );
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('discount-conflict'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: OrangeTheme.pale,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OrangeTheme.action),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.discountConflictTitle,
                style: const TextStyle(
                  color: OrangeTheme.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.discountConflictBody,
              style: const TextStyle(color: OrangeTheme.ink, height: 1.4),
            ),
            for (final part in DiscountPart.values)
              if (merge.theirsChanged.contains(part))
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        DiscountText.partName(l10n, part),
                        style: const TextStyle(
                          color: OrangeTheme.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.discountConflictSaved(value(part, mine: false)),
                        key: Key('discount-conflict-saved-${part.name}'),
                      ),
                      if (conflicting.contains(part)) ...[
                        Text(
                          l10n.discountConflictYours(value(part, mine: true)),
                          key: Key('discount-conflict-yours-${part.name}'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _Choice(
                                key: Key('discount-conflict-mine-${part.name}'),
                                label: l10n.discountConflictKeepMine,
                                selected: keepMine[part] == true,
                                onTap: onChoose == null
                                    ? null
                                    : () => onChoose!(part, keepMine: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _Choice(
                                key: Key(
                                  'discount-conflict-saved-choice-${part.name}',
                                ),
                                label: l10n.discountConflictUseSaved,
                                selected: keepMine[part] == false,
                                onTap: onChoose == null
                                    ? null
                                    : () => onChoose!(part, keepMine: false),
                              ),
                            ),
                          ],
                        ),
                      ] else
                        Text(
                          l10n.discountConflictTakenOver,
                          style: const TextStyle(
                            color: OrangeTheme.secondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('discount-conflict-apply'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onApply,
              child: Text(l10n.discountConflictApply),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: selected ? OrangeTheme.action : Colors.white,
        foregroundColor: selected ? Colors.white : OrangeTheme.action,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}
