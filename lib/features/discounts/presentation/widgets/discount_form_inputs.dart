import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_text.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_widgets.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/tag_icon.dart';

const _border = Color(0xFFDADCE0);

/// The SVG icon of each discount type (Lucide banknote, percent, package),
/// used on the type tabs and in the value inputs.
String discountTypeIcon(DiscountType type) => switch (type) {
  DiscountType.fixedPrice => 'assets/icons/discount_fixed.svg',
  DiscountType.percentage => 'assets/icons/discount_percent.svg',
  DiscountType.collective => 'assets/icons/discount_collective.svg',
};

/// A single-color SVG icon.
class DiscountSvgIcon extends StatelessWidget {
  const new(
    this.asset, {
    this.color = OrangeTheme.action,
    this.size = 20,
    super.key,
  });

  final String asset;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    asset,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

/// The live preview card. Only a preview: the server decides when saving.
class DiscountPreviewCard extends StatelessWidget {
  const new({
    required this.draft,
    required this.preview,
    required this.currency,
    super.key,
  });

  final DiscountDraft draft;
  final DraftPreview? preview;
  final String currency;

  static const _body = TextStyle(color: OrangeTheme.ink, fontSize: 17);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final current = preview;
    final header = Row(
      children: [
        const TagIcon(size: 20),
        const SizedBox(width: 8),
        Text(
          l10n.discountPreviewTitle,
          style: const TextStyle(color: OrangeTheme.secondary, fontSize: 15),
        ),
      ],
    );
    if (current == null) {
      return DiscountPanel(
        key: const Key('discount-preview'),
        padding: const EdgeInsets.all(12),
        radius: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            Text(
              l10n.discountPreviewHint,
              style: const TextStyle(
                color: OrangeTheme.secondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    final finalPrice = draft.type == DiscountType.collective
        ? l10n.discountPreviewBundlePrice(
            DiscountText.money(current.bundlePriceCents!, currency),
          )
        : l10n.discountPreviewFinalPrice(
            DiscountText.money(current.unitPriceCents!, currency),
          );
    final details = [
      if (draft.repeat.type != RepeatType.none)
        DiscountText.repeat(l10n, locale, draft.repeat),
      if (draft.minimumQuantity.trim().isNotEmpty)
        DiscountText.minimum(l10n, draft.minimumQuantity),
    ];
    return DiscountPanel(
      key: const Key('discount-preview'),
      padding: const EdgeInsets.all(12),
      radius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          Text(
            finalPrice,
            key: const Key('discount-preview-final'),
            style: const TextStyle(
              color: OrangeTheme.ink,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: OrangeTheme.pale,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              DiscountText.previewHeadline(l10n, draft, current, currency)!,
              style: const TextStyle(
                color: OrangeTheme.dark,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (draft.schedule != null || details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.discountSchedule,
                    style: const TextStyle(
                      color: OrangeTheme.secondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (draft.schedule != null)
                    Text(
                      DiscountText.schedule(l10n, locale, draft.schedule),
                      style: _body,
                    ),
                  if (details.isNotEmpty)
                    Text(details.join(' · '), style: _body),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fixed Price / Percentage / Collective tabs.
class DiscountTypeSelector extends StatelessWidget {
  const new({
    required this.selected,
    required this.onChanged,
    required this.enabled,
    super.key,
  });

  final DiscountType? selected;
  final ValueChanged<DiscountType> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        for (final type in DiscountType.values) ...[
          if (type != DiscountType.values.first) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              selected: type == selected,
              button: true,
              child: Material(
                color: type == selected ? OrangeTheme.pale : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: type == selected ? OrangeTheme.action : _border,
                  ),
                ),
                child: InkWell(
                  key: Key('discount-type-${type.wire}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: enabled ? () => onChanged(type) : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 62),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DiscountSvgIcon(
                            discountTypeIcon(type),
                            color: type == selected
                                ? OrangeTheme.action
                                : OrangeTheme.ink,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            DiscountText.typeName(l10n, type),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: type == selected
                                  ? OrangeTheme.action
                                  : OrangeTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

OutlineInputBorder _fieldBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );

/// A labelled text input with an optional error and helper, and the
/// discount type's icon in front of the value.
class DiscountTextField extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.enabled,
    this.error,
    this.helper,
    this.prefix,
    this.suffix,
    this.icon,
    this.integer = false,
    super.key,
  });

  final String fieldKey;
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? error;
  final String? helper;
  final String? prefix;
  final String? suffix;

  /// Leading SVG icon (the discount type's icon).
  final String? icon;
  final bool integer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: OrangeTheme.ink,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: Key(fieldKey),
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          keyboardType: TextInputType.numberWithOptions(decimal: !integer),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              integer ? RegExp(r'\d') : RegExp(r'[\d.,]'),
            ),
          ],
          style: const TextStyle(fontSize: 17, color: OrangeTheme.ink),
          decoration: InputDecoration(
            hintText: context.l10n.discountEnterValue,
            prefixIcon: icon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 16, right: 10),
                    child: DiscountSvgIcon(icon!),
                  ),
            prefixIconConstraints: const BoxConstraints(minHeight: 48),
            prefixText: prefix == null ? null : '$prefix ',
            suffixText: suffix,
            errorText: error,
            helperText: error == null ? helper : null,
            helperMaxLines: 3,
            errorMaxLines: 3,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: _fieldBorder(_border),
            enabledBorder: _fieldBorder(_border),
            disabledBorder: _fieldBorder(_border),
            focusedBorder: _fieldBorder(OrangeTheme.action, 2),
          ),
        ),
      ],
    ),
  );
}
