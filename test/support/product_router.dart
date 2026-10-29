import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Hosts a product form page the way the app does: finished forms navigate to
/// Product Details, which is a placeholder here.
Widget productFormApp(
  Widget page, {
  Locale locale = const Locale('en'),
  double scale = 1,
  List<Override> overrides = const [],
  GoRouter? router,
}) {
  final host =
      router ??
      GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => page),
          GoRoute(
            name: 'productDetails',
            path: '/details',
            builder: (context, state) =>
                Text('details ${state.uri.queryParameters['barcode']}'),
          ),
          GoRoute(
            name: 'productScanner',
            path: '/scan',
            builder: (context, state) => const Text('scanner'),
          ),
        ],
      );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: OrangeTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: host,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
}

/// The pending success toast message of the app under test.
ProductSuccess? pendingSuccess(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(productSuccessProvider);
