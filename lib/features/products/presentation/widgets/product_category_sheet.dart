import 'package:flutter/material.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductCategoryChoice {
  const new(this.id);
  final int? id;
}

/// Mirrors the tax sheet: selection is explicit, dismissing changes nothing.
/// With [onCreate] a new category can be added from the sheet; the created
/// category is returned as the choice.
class ProductCategorySheet extends StatefulWidget {
  const new({
    required this.categories,
    required this.selectedId,
    this.onCreate,
    this.allowNone = true,
    super.key,
  });
  final List<ProductCategory> categories;
  final int? selectedId;

  /// Null hides the add row (no `category_create` permission).
  final Future<ProductCategory> Function(String name)? onCreate;

  /// A new product needs a category; an existing one may drop its category.
  final bool allowNone;
  @override
  State<ProductCategorySheet> createState() => _ProductCategorySheetState();
}

class _ProductCategorySheetState extends State<ProductCategorySheet> {
  final _name = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final create = widget.onCreate;
    final name = _name.text.trim();
    if (create == null || _creating || name.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final created = await create(name);
      if (mounted) Navigator.pop(context, ProductCategoryChoice(created.id));
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.categorySelect,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.categoryCloseTooltip,
                  onPressed: _creating ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.cancel_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.onCreate != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('category-new-input'),
                      controller: _name,
                      enabled: !_creating,
                      maxLength: 64,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _create(),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: l10n.categoryNewHint,
                        errorText: _error,
                        errorMaxLines: 3,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('category-add-button'),
                    tooltip: l10n.categoryAddTooltip,
                    style: IconButton.styleFrom(
                      backgroundColor: OrangeTheme.action,
                      foregroundColor: Colors.white,
                      fixedSize: const Size(56, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _creating ? null : _create,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (widget.allowNone)
              _option(
                context,
                null,
                l10n.categoryNone,
                widget.selectedId == null,
              ),
            for (final category in widget.categories)
              _option(
                context,
                category.id,
                category.name,
                widget.selectedId == category.id,
              ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, int? id, String label, bool selected) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF202124),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: Color(0xFFDADCE0)),
          ),
          onPressed: _creating
              ? null
              : () => Navigator.pop(context, ProductCategoryChoice(id)),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? OrangeTheme.scannerAccent
                    : const Color(0xFFDADCE0),
              ),
            ],
          ),
        ),
      );
}
