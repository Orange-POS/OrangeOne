import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/features/authentication/presentation/widgets/scan_frame.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class QrLoginPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends ConsumerState<QrLoginPage> {
  String _cameraStatus = 'Opening camera…';
  var _cameraGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    final failure = session.error;
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
                        tooltip: 'Back to login',
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
                      const Expanded(
                        child: Text(
                          'Scan QR Code',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 64 || constraints.maxHeight <= 0) {
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
                                : KeyedSubtree(
                                    key: ValueKey(_cameraGeneration),
                                    child: ref.watch(qrCameraBuilderProvider)(
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
                                            () => _cameraStatus = status,
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
                                const Text(
                                  'Scan to sign in',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  session.isLoading
                                      ? 'Signing in securely…'
                                      : failure is AppFailure
                                      ? failure.message
                                      : session.hasError
                                      ? 'Unable to sign in. '
                                            'Generate a new POS QR code.'
                                      : 'Point your camera at the QR code on '
                                            'the POS machine.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.5,
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
                                          _cameraStatus = 'Opening camera…';
                                        });
                                      },
                                      child: const Text('Scan a new QR code'),
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
                                  ? 'Verifying POS login…'
                                  : session.hasError
                                  ? 'Scan paused · Check the message above'
                                  : _cameraStatus,
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Powered By OrangeONE',
                        style: TextStyle(
                          color: OrangeTheme.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
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
