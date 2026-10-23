import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class App extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: MediaQuery(
          data: _standardInsets(MediaQuery.of(context)),
          child: child!,
        ),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
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
