import 'package:flutter/material.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// The Update, Add and Remove choice of the stock screen.
class StockOperationSelector extends StatelessWidget {
  const new({
    required this.selected,
    required this.onChanged,
    required this.enabled,
    super.key,
  });
  final StockOperation selected;
  final ValueChanged<StockOperation> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      StockOperation.update: l10n.stockOperationUpdate,
      StockOperation.add: l10n.stockOperationAdd,
      StockOperation.remove: l10n.stockOperationRemove,
    };
    const icons = {
      StockOperation.update: Icons.tune,
      StockOperation.add: Icons.add,
      StockOperation.remove: Icons.remove,
    };
    return Semantics(
      container: true,
      label: l10n.stockOperationsLabel,
      child: Row(
        spacing: 8,
        children: [
          for (final operation in StockOperation.values)
            Expanded(
              child: _OperationTile(
                key: Key('stock-operation-${operation.name}'),
                icon: icons[operation]!,
                label: labels[operation]!,
                selected: operation == selected,
                onPressed: enabled ? () => onChanged(operation) : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _OperationTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = selected ? OrangeTheme.action : Colors.black87;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: selected ? OrangeTheme.pale : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? OrangeTheme.action : OrangeTheme.actionDisabled,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: OrangeTheme.action, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
