import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/wifi_connection.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/features/authentication/presentation/widgets/scan_frame.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class QrLoginPage extends ConsumerStatefulWidget {
  const new({this.demoSamples, super.key});

  /// Sample QR codes composed by the app while Demo Mode is on; they replace
  /// the camera, which is not needed (or available) in the demo.
  final Widget? demoSamples;

  @override
  ConsumerState<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends ConsumerState<QrLoginPage> {
  // Null until the camera reports; the localized default is shown meanwhile.
  String? _cameraStatus;
  var _cameraGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    final failure = session.error;
    // Scanning needs a Wi-Fi connection. This only reads the device's
    // network: it cannot confirm that the POS machine is on that network.
    // Reading failures count as "not connected".
    final wifi = ref.watch(wifiConnectionProvider);
    final checkingWifi = wifi.isLoading;
    // An error keeps the previous value in Riverpod 3; it still means off.
    final wifiOn = !wifi.hasError && (wifi.value ?? false);
    // A fresh camera starts whenever Wi-Fi returns.
    ref.listen(wifiConnectionProvider, (previous, next) {
      if (previous?.value != next.value && mounted) {
        setState(() {
          _cameraGeneration++;
          _cameraStatus = null;
        });
      }
    });
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && session.isLoading) {
          unawaited(controller.signOut());
        }
      },
      child: Scaffold(
        backgroundColor: OrangeTheme.camera,
        body: Column(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(false),
                        tooltip: l10n.scanBackTooltip,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .2),
                          fixedSize: const Size(48, 48),
                        ),
                        icon: SvgPicture.asset(
                          'assets/icons/arrow_left.svg',
                          width: 24,
                          height: 24,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          l10n.scanTitle,
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
            Expanded(
              child:
                  widget.demoSamples ??
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 64 ||
                          constraints.maxHeight <= 0) {
                        return const SizedBox.shrink();
                      }
                      final height = math.max<double>(
                        440 * MediaQuery.textScalerOf(context).scale(1),
                        constraints.maxHeight,
                      );
                      final frameSize = math.min<double>(
                        240,
                        constraints.maxWidth - 64,
                      );
                      final top = height * .45 - frameSize / 2;
                      return SingleChildScrollView(
                        child: SizedBox(
                          height: height,
                          child: Stack(
                            children: [
                              Positioned(
                                left: (constraints.maxWidth - frameSize) / 2,
                                top: top,
                                width: frameSize,
                                height: frameSize,
                                child: session.isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(
                                          color: OrangeTheme.brand,
                                        ),
                                      )
                                    : session.hasError
                                    ? const SizedBox.shrink()
                                    : !wifiOn
                                    ? _ScannerOff(checking: checkingWifi)
                                    : KeyedSubtree(
                                        key: ValueKey(_cameraGeneration),
                                        child:
                                            ref.watch(qrCameraBuilderProvider)(
                                              context,
                                              (code) => unawaited(
                                                ref
                                                    .read(
                                                      sessionControllerProvider
                                                          .notifier,
                                                    )
                                                    .signIn(code),
                                              ),
                                              (status) {
                                                if (mounted) {
                                                  setState(
                                                    () =>
                                                        _cameraStatus = status,
                                                  );
                                                }
                                              },
                                            ),
                                      ),
                              ),
                              Positioned(
                                left: (constraints.maxWidth - frameSize) / 2,
                                top: top,
                                width: frameSize,
                                height: frameSize,
                                child: const IgnorePointer(child: ScanFrame()),
                              ),
                              Positioned(
                                left: 24,
                                right: 24,
                                top: top + frameSize + 24,
                                child: Column(
                                  children: [
                                    Text(
                                      l10n.scanHeading,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        height: 1.3,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        session.isLoading
                                            ? l10n.scanSigningIn
                                            : failure is AppFailure
                                            ? failure.message
                                            : session.hasError
                                            ? l10n.scanFailure
                                            : !wifiOn && !checkingWifi
                                            ? l10n.scanWifiRequired
                                            : l10n.scanInstruction,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    if (session.hasError)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: FilledButton(
                                          onPressed: () {
                                            ref
                                                .read(
                                                  sessionControllerProvider
                                                      .notifier,
                                                )
                                                .clearLoginFailure();
                                            setState(() {
                                              _cameraGeneration++;
                                              _cameraStatus = null;
                                            });
                                          },
                                          child: Text(l10n.scanAgain),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: OrangeTheme.pale,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/camera_indicator.svg',
                            colorFilter: const ColorFilter.mode(
                              OrangeTheme.scannerAccent,
                              BlendMode.srcIn,
                            ),
                            width: 8,
                            height: 8,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              session.isLoading
                                  ? l10n.scanVerifying
                                  : session.hasError
                                  ? l10n.scanPausedError
                                  : checkingWifi
                                  ? l10n.scanCheckingWifi
                                  : !wifiOn
                                  ? l10n.scanWifiStatus
                                  : _cameraStatus ?? l10n.scanOpeningCamera,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: OrangeTheme.dark,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for the camera while the scanner is off: a progress indicator
/// while the Wi-Fi state is read, otherwise a Wi-Fi-off icon (the message
/// below the frame explains it).
class _ScannerOff extends StatelessWidget {
  const new({required this.checking});
  final bool checking;

  @override
  Widget build(BuildContext context) => Center(
    child: checking
        ? const CircularProgressIndicator(color: OrangeTheme.brand)
        : const ExcludeSemantics(
            child: Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: Colors.white54,
            ),
          ),
  );
}
