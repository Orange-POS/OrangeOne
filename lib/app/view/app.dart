import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/app/providers/crash_identity.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/features/demo/presentation/widgets/demo_banner.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/l10n/locale_controller.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class App extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the session cache alive so that logout closes it, and deletes its
    // snapshots and recent scans, at once instead of at the next read.
    ref
      ..listen(readCacheProvider, (previous, next) {})
      ..watch(crashIdentityProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'OrangeONE',
      theme: OrangeTheme.light,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: _withDemoBanner(
          context,
          ref,
          MediaQuery(
            data: _standardInsets(MediaQuery.of(context)),
            child: child!,
          ),
        ),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The user's saved language; null follows the device language.
      locale: ref.watch(localeControllerProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }

  /// While Demo Mode runs, a banner owns the status bar area above the app.
  Widget _withDemoBanner(BuildContext context, WidgetRef ref, Widget app) {
    if (ref.watch(demoModeProvider) == null) return app;
    return Column(
      children: [
        DemoBanner(
          onSettings: () => ref.read(routerProvider).pushNamed('settings'),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: app,
          ),
        ),
      ],
    );
  }

  MediaQueryData _standardInsets(MediaQueryData data) => data.copyWith(
    padding: data.padding.copyWith(
      top: data.padding.top.clamp(OrangeTheme.topSafeArea, double.infinity),
    ),
    viewPadding: data.viewPadding.copyWith(
      top: data.viewPadding.top.clamp(OrangeTheme.topSafeArea, double.infinity),
    ),
  );
}
