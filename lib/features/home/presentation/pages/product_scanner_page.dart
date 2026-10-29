import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/providers/recent_scans_providers.dart';
import 'package:orange_one/features/home/presentation/widgets/product_camera.dart';
import 'package:orange_one/features/home/presentation/widgets/product_result_panel.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/scan_frame.dart';

class ProductScannerPage extends ConsumerStatefulWidget {
  const new({required this.onLookup, super.key});
  final Future<void> Function(String barcode, {required bool found}) onLookup;

  @override
  ConsumerState<ProductScannerPage> createState() => _ProductScannerPageState();
}

class _ProductScannerPageState extends ConsumerState<ProductScannerPage> {
  final _scroll = ScrollController();
  var _cameraGeneration = 0;
  // Null until the camera reports; the localized default is shown meanwhile.
  String? _status;
  bool _navigating = false;
  bool _routeCurrent = true;
  bool _resuming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_routeCurrent) {
      _resuming = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        _navigating = false;
        _resuming = false;
        _scanAgain();
      });
    }
    _routeCurrent = current;
  }

  Future<void> _openResult(ProductLookup result) async {
    if (_navigating || !mounted) return;
    _navigating = true;
    try {
      await widget.onLookup(result.barcode, found: result.product != null);
    } finally {
      if (mounted) {
        _navigating = false;
        if (_routeCurrent && !_resuming) _scanAgain();
      }
    }
  }

  void _scanAgain() {
    ref.read(productLookupControllerProvider.notifier).scanAgain();
    setState(() {
      _cameraGeneration++;
      _status = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(productLookupControllerProvider);
    final recents = ref.watch(recentScansControllerProvider).value ?? const [];
    ref.listen(productLookupControllerProvider, (previous, next) {
      if (!next.isLoading && !next.hasError && next.value != null) {
        unawaited(_openResult(next.value!));
      }
    });
    final controller = ref.read(productLookupControllerProvider.notifier);
    final cameraGeneration = _cameraGeneration;
    final scanning =
        !state.isLoading &&
        !state.hasError &&
        state.value == null &&
        !_navigating &&
        _routeCurrent &&
        !_resuming;
    return Scaffold(
      backgroundColor: OrangeTheme.camera,
      body: LayoutBuilder(
        builder: (context, viewport) {
          if (viewport.maxWidth < 64 || viewport.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final frameWidth = math.min<double>(400, viewport.maxWidth - 64);
          return CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: OrangeTheme.scannerGradient,
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: l10n.scannerBackTooltip,
                            onPressed: () => context.canPop()
                                ? context.pop(false)
                                : context.goNamed('home'),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: .2,
                              ),
                              fixedSize: const Size(48, 48),
                            ),
                            icon: SvgPicture.asset(
                              'assets/icons/arrow_left.svg',
                              width: 20,
                              height: 20,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              l10n.scannerTitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: frameWidth,
                            height: frameWidth * 190 / 326,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (scanning)
                                  KeyedSubtree(
                                    key: ValueKey(_cameraGeneration),
                                    child:
                                        ref.watch(productCameraBuilderProvider)(
                                          context,
                                          (code) =>
                                              unawaited(controller.scan(code)),
                                          (status) {
                                            if (mounted &&
                                                _routeCurrent &&
                                                cameraGeneration ==
                                                    _cameraGeneration) {
                                              setState(() => _status = status);
                                            }
                                          },
                                        ),
                                  ),
                                const IgnorePointer(
                                  child: ScanFrame(
                                    color: OrangeTheme.scannerAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              state.isLoading
                                  ? l10n.scannerLookingUp
                                  : scanning
                                  ? _status ?? l10n.scanOpeningCamera
                                  : l10n.scannerPaused,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    ProductResultPanel(
                      state: state,
                      recents: recents,
                      onOpenRecent: (barcode) =>
                          unawaited(controller.scan(barcode)),
                      onScanAgain: _scanAgain,
                      onRetry: () => unawaited(controller.retry()),
                      onAddProduct: (barcode) => unawaited(
                        _openResult(ProductLookup(barcode: barcode)),
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
}
