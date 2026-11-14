import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_success_toast.dart';
import 'package:orange_one/features/products/presentation/widgets/product_sync_nav_button.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/info_row_card.dart';
import 'package:orange_one/shared/widgets/product_navbar.dart';
import 'package:orange_one/shared/widgets/product_scaffold.dart';
import 'package:orange_one/shared/widgets/scan_dock_bar.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

class ProductDetailsPage extends ConsumerStatefulWidget {
  const new({required this.barcode, this.discountsBuilder, super.key});
  final String barcode;

  /// The discount section under the price, composed by the app (the
  /// discounts feature); null shows none.
  final Widget Function(ProductDetailsState details)? discountsBuilder;
  @override
  ConsumerState<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends ConsumerState<ProductDetailsPage> {
  /// Heights of the product card fully expanded and fully collapsed, as
  /// laid out at the current width; null until both are measured.
  double? _expanded;
  double? _collapsed;

  /// The same way back to the scanner the screen always had.
  void _openScanner() =>
      context.canPop() ? context.pop() : context.goNamed('productScanner');

  String _taxLabel(AppLocalizations l10n, ProductDetails product) =>
      product.taxes.isNotEmpty
      ? product.taxes.join(', ')
      : product.taxIds?.isEmpty == true
      ? l10n.detailsTaxNone
      : l10n.detailsTaxUnavailable;

  void _measured({double? expanded, double? collapsed}) {
    if (!mounted) return;
    if ((expanded == null || expanded == _expanded) &&
        (collapsed == null || collapsed == _collapsed)) {
      return;
    }
    setState(() {
      _expanded = expanded ?? _expanded;
      _collapsed = collapsed ?? _collapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = productDetailsControllerProvider(widget.barcode);
    final state = ref.watch(provider);
    final product = state.hasError ? null : state.value?.product;

    /// The product card folded by [collapse]; only built with a product.
    Widget card(double collapse) {
      final current = product!;
      return ProductNameCard(
        product: current,
        detailsLayout: true,
        collapse: collapse,
        taxText: _taxLabel(l10n, current),
        onEdit: !offline && state.value!.access.editName
            ? () => context.pushNamed<bool>(
                'productEdit',
                queryParameters: {'barcode': widget.barcode},
              )
            : null,
        // Only permitted, backend-adjustable stock can be counted.
        onAdjustStock:
            !offline &&
                state.value!.access.adjustStock &&
                current.stockAdjustable &&
                current.stock != null
            ? () => context.pushNamed<bool>(
                'productStock',
                queryParameters: {'barcode': widget.barcode},
              )
            : null,
      );
    }

    final expanded = _expanded;
    final collapsed = _collapsed;
    // Pinned once both heights are known (the first frame shows the same
    // card unpinned) and only while the collapsed card leaves most of the
    // [visible] height to the content: on short screens, in landscape or
    // with large text it scrolls away instead of covering the content.
    ({double max, double min})? extentsFor(double visible) =>
        product != null &&
            expanded != null &&
            collapsed != null &&
            expanded > collapsed &&
            collapsed <= visible * .45
        ? (max: expanded, min: collapsed)
        : null;
    return ProductScaffold(
      // The success of a finished form, above the scan dock.
      floatingActionButton: SizedBox(
        width: MediaQuery.sizeOf(context).width - 32,
        child: ProductSuccessToast(barcode: widget.barcode),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // The dock floats: content stays visible through its notch.
      floatingBottomBar: true,
      bottomNavigationBar: ScanDockBar(
        buttonKey: const Key('open-scanner-button'),
        label: l10n.detailsOpenScanner,
        onPressed: _openScanner,
      ),
      appBar: ProductNavbar(
        title: l10n.detailsTitle,
        // Open Scanner replaces the back arrow; system back still works.
        showBack: false,
        onBack: null,
        trailing: ProductSyncNavButton(barcode: widget.barcode),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The body runs behind the floating dock; its inset is the dock.
          final extents = extentsFor(
            constraints.maxHeight - MediaQuery.paddingOf(context).bottom,
          );
          return Stack(
            children: [
              // Measures the card at both ends of its collapse, at this width,
              // so the pinned header knows its extents. Never shown.
              if (product != null)
                Offstage(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MeasureHeight(
                        onHeight: (height) => _measured(expanded: height),
                        child: card(0),
                      ),
                      _MeasureHeight(
                        onHeight: (height) => _measured(collapsed: height),
                        child: card(1),
                      ),
                    ],
                  ),
                ),
              // White behind the lower page: overscrolling past the content at
              // the bottom shows white, never the orange page background. It
              // starts below the panel's rounded corners, which keep the
              // gradient behind them.
              if (product == null || expanded != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: product == null ? 24 : expanded! + 24,
                  child: const ColoredBox(color: Colors.white),
                ),
              RefreshIndicator(
                onRefresh: () => ref.read(provider.notifier).refresh(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (extents != null)
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _PinnedProductCard(
                          maxHeight: extents.max,
                          minHeight: extents.min,
                          card: card,
                        ),
                      )
                    else if (product != null)
                      SliverToBoxAdapter(child: card(0)),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        // The bottom inset includes the floating dock's height,
                        // so the last card ends just above it.
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          MediaQuery.paddingOf(context).bottom + 16,
                        ),
                        child: _content(context, state, offline),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AsyncValue<ProductDetailsState> state,
    bool offline,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        state.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => Skeleton(
            label: l10n.detailsLoading,
            child: const Column(
              children: [
                SkeletonInfoRow(),
                SizedBox(height: 16),
                SkeletonCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 140),
                      SizedBox(height: 16),
                      SkeletonTiles(count: 2, height: 72),
                    ],
                  ),
                ),
              ],
            ),
          ),
          error: (error, stack) => Column(
            children: [
              Text(
                error is AppFailure
                    ? error.message
                    : error is FormatException
                    ? error.message
                    : l10n.detailsLoadFailed,
              ),
              Text(l10n.detailsPullToRefresh),
            ],
          ),
          data: (details) => details.product == null
              ? Column(
                  children: [
                    Text(l10n.productNotFound),
                    FilledButton(
                      onPressed: () => context.pushReplacementNamed(
                        'addProduct',
                        queryParameters: {'barcode': widget.barcode},
                      ),
                      child: Text(l10n.addProduct),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRowCard.price(
                      label: l10n.detailsPrice,
                      value: _priceLabel(details.product!.price),
                      action: EditPencilButton(
                        tooltip: l10n.detailsUpdatePrice,
                        onPressed: !offline && details.access.updatePrice
                            ? () => context.pushNamed<bool>(
                                'productPrice',
                                queryParameters: {'barcode': widget.barcode},
                              )
                            : null,
                      ),
                    ),
                    ?widget.discountsBuilder?.call(details),
                  ],
                ),
        ),
      ],
    );
  }

  String _priceLabel(double price) => 'CHF ${price.toStringAsFixed(2)}';
}

/// The product card pinned at the top of Product Details. It folds from
/// [maxHeight] to [minHeight] as the content scrolls up and unfolds as it
/// scrolls back; the card's own height follows the header's exactly. The
/// scaffold's gradient is painted behind it, so the content scrolling
/// underneath never shows through the glass.
class _PinnedProductCard extends SliverPersistentHeaderDelegate {
  new({required this.maxHeight, required this.minHeight, required this.card});

  final double maxHeight;
  final double minHeight;
  final Widget Function(double collapse) card;

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final collapse = (shrinkOffset / (maxHeight - minHeight)).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ProductGradientBackdrop(),
        // Rounding may differ by a fraction of a pixel from the header.
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: card(collapse),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_PinnedProductCard oldDelegate) => true;
}

/// Reports its child's laid-out height after each layout that changed it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const new({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  new(this.onHeight);
  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // Reported after the frame: layout must not change state.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
