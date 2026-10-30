import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/authentication/presentation/pages/splash_page.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/brand_mark.dart';
import 'package:orange_one/features/authentication/presentation/widgets/language_selector.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class LoginPage extends ConsumerWidget {
  const new({this.sessionExpired = false, super.key});
  final bool sessionExpired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session.isLoading) return const SplashPage();
    final l10n = context.l10n;
    final failure = session.error;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                return const SizedBox.shrink();
              }
              final circle = math.min<double>(240, constraints.maxWidth * .67);
              return SingleChildScrollView(
                child: SizedBox(
                  height: math.max(
                    constraints.maxHeight,
                    700 * MediaQuery.textScalerOf(context).scale(1),
                  ),
                  width: constraints.maxWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            const BrandMark(),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: IconButton(
                                key: const Key('settings-button'),
                                tooltip: l10n.settingsOpenTooltip,
                                icon: const Icon(
                                  Icons.settings,
                                  color: Colors.white,
                                ),
                                onPressed: () =>
                                    context.pushNamed<void>('settings'),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Semantics(
                          button: true,
                          label: l10n.loginScanSemantics,
                          child: InkWell(
                            key: const Key('scan-login-button'),
                            onTap: session.isLoading
                                ? null
                                : () => context.pushNamed<bool>('qrLogin'),
                            borderRadius: BorderRadius.circular(circle),
                            child: Container(
                              width: circle,
                              height: circle,
                              padding: EdgeInsets.all(circle * .3),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: SvgPicture.asset(
                                'assets/icons/qr_code.svg',
                                colorFilter: const ColorFilter.mode(
                                  OrangeTheme.action,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          l10n.loginScanTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.loginSubtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const LanguageSelector(),
                        if (sessionExpired)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              l10n.loginSessionExpired,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        if (session.isLoading)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              semanticsLabel: l10n.loginRestoringSemantics,
                            ),
                          ),
                        if (session.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Column(
                              children: [
                                Text(
                                  failure is AppFailure
                                      ? failure.message
                                      : l10n.loginRestoreFailed,
                                  style: const TextStyle(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: () => ref
                                      .read(sessionControllerProvider.notifier)
                                      .retryRestore(),
                                  child: Text(
                                    l10n.loginRetryRestore,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Spacer(),
                        Text(
                          l10n.poweredBy,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
