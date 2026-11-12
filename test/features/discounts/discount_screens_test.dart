import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/capabilities/session_permissions.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/discounts/data/data_sources/discount_remote_data_source.dart';
import 'package:orange_one/features/discounts/data/repositories/odoo_discount_repository.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/repositories/discount_repository.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_form_inputs.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/orange_switch.dart';
import 'package:orange_one/shared/widgets/product_action_surface.dart';

import '../../support/auth_fakes.dart';
import '../../support/discount_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';
import '../../support/product_details_fakes.dart';

const _barcode = '0010101010';
const _manage = ProductAccess(
  updatePrice: true,
  adjustStock: true,
  manageDiscounts: true,
);
const _readOnly = ProductAccess(updatePrice: true);

void main() {
  late FakeDiscountRepository discounts;
  late ProviderContainer container;

  Future<void> open(
    WidgetTester tester, {
    Override? backend,
    Map<String, bool>? permissions = const {
      'product_read': true,
      'discount_read': true,
      'discount_manage': true,
    },
    ProductAccess access = _manage,
    List<Override> more = const [],
    DiscountRepository? repository,
  }) async {
    tester.view
      ..physicalSize = const Size(900, 2600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..restored = testSession,
          ),
          utcNowProvider.overrideWithValue(() => testNow),
          productDetailsRepositoryProvider.overrideWithValue(
            FakeDetailsRepository()..access = access,
          ),
          discountRepositoryProvider.overrideWithValue(repository ?? discounts),
          backend ?? discountBackend,
          if (permissions != null)
            sessionPermissionsProvider.overrideWithValue(
              SessionPermissions(permissions),
            ),
          ...more,
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(App)));
    container
        .read(routerProvider)
        .goNamed('productDetails', queryParameters: {'barcode': _barcode});
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) =>
      tapKey(tester, 'discount-confirm');

  setUp(() => discounts = FakeDiscountRepository());

  group('capability and permissions', () {
    testWidgets('an older shop without product_discounts shows nothing', (
      tester,
    ) async {
      await open(
        tester,
        backend: backendFeaturesProvider.overrideWith(
          (ref) async =>
              BackendFeatures(BackendFeatures.baseline.names, confirmed: true),
        ),
      );
      expect(find.text('Aachi Fish Fry Masala'), findsWidgets);
      expect(find.byKey(const Key('discount-summary')), findsNothing);
      expect(discounts.lists, 0, reason: 'no discount endpoint is called');
      // Existing product actions are unchanged.
      expect(find.byTooltip('Update stock'), findsOneWidget);
    });

    testWidgets('the shop lists discounts but the user may not read them', (
      tester,
    ) async {
      await open(
        tester,
        permissions: const {'product_read': true, 'discount_read': false},
      );
      expect(find.byKey(const Key('discount-summary')), findsNothing);
      expect(discounts.lists, 0);
    });

    testWidgets('read only: overview and list without any write action', (
      tester,
    ) async {
      await open(
        tester,
        permissions: const {'discount_read': true, 'discount_manage': false},
        access: _readOnly,
      );
      expect(find.text('Discount Overview'), findsOneWidget);
      expect(find.byKey(const Key('discount-total')), findsOneWidget);
      await tapKey(tester, 'discount-open');
      expect(find.text('Discount Details'), findsOneWidget);
      expect(
        find.text(
          'You can view discounts but not change them for this product.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('discount-list-create')), findsNothing);
      final edit = tester.widget<EditPencilButton>(
        find.byKey(const Key('discount-edit-1')),
      );
      expect(edit.onPressed, isNull);
      expect(find.byKey(const Key('discount-toggle-1')), findsNothing);
      await tapKey(tester, 'discount-1');
      expect(find.byKey(const Key('discount-pause')), findsNothing);
      expect(discounts.writes, isEmpty);
    });

    testWidgets('manage: session allowed but the product is not discountable', (
      tester,
    ) async {
      await open(tester, access: _readOnly);
      await tapKey(tester, 'discount-open');
      expect(find.byKey(const Key('discount-list-create')), findsNothing);
    });
  });

  group('overview', () {
    testWidgets('no discounts: Create New Discounts opens the form', (
      tester,
    ) async {
      discounts.discounts = [];
      await open(tester);
      expect(find.text('Create New Discounts'), findsOneWidget);
      await tapKey(tester, 'discount-create-new');
      expect(
        find.text('Choose a type to enter its discount value.'),
        findsOneWidget,
      );
    });

    testWidgets('count and cards of the product discounts', (tester) async {
      discounts.discounts = [
        discountOf(),
        discountOf(id: 2, type: DiscountType.collective),
        discountOf(id: 3, type: DiscountType.fixedPrice, paused: true),
      ];
      await open(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('discount-total'))).data,
        '3',
      );
      expect(find.text('20% off'), findsOneWidget);
      expect(find.text('5 for CHF 400.00'), findsOneWidget);
      expect(find.text('CHF 80.00'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
    });

    testWidgets('a read failure offers a retry, other details stay', (
      tester,
    ) async {
      discounts.readError = const AppFailure(FailureKind.network, 'offline');
      await open(tester);
      expect(find.text('Discounts could not be loaded.'), findsOneWidget);
      discounts.readError = null;
      await tapKey(tester, 'discount-summary-retry');
      expect(find.text('Discount Overview'), findsOneWidget);
      expect(find.text('20% off'), findsOneWidget);
    });
  });

  group('details actions', () {
    Future<void> openDiscount(WidgetTester tester) async {
      await open(tester);
      await tapKey(tester, 'discount-open');
      await tapKey(tester, 'discount-1');
    }

    testWidgets('details show price, value, preview and status', (
      tester,
    ) async {
      await openDiscount(tester);
      expect(find.text('CHF 100.00'), findsWidgets);
      expect(find.text('20% off'), findsWidgets);
      expect(find.text('CHF 80.00'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Applies now'), findsOneWidget);
      expect(find.text('Does Not Repeat'), findsOneWidget);
      expect(find.text('No Minimum'), findsOneWidget);
    });

    testWidgets('pause, then resume: confirmed, with the fresh version', (
      tester,
    ) async {
      await openDiscount(tester);
      await tapKey(tester, 'discount-pause');
      expect(find.text('Pause this discount?'), findsOneWidget);
      await confirm(tester);
      expect(discounts.writes, ['pause']);
      expect(find.text('Paused'), findsWidgets);
      expect(find.text('Discount paused.'), findsOneWidget);
      // Paused is not archived: still editable and resumable.
      final edit = tester.widget<FilledButton>(
        find.byKey(const Key('discount-edit')),
      );
      expect(edit.onPressed, isNotNull);
      await tapKey(tester, 'discount-resume');
      await confirm(tester);
      expect(discounts.writes, ['pause', 'resume']);
      expect(discounts.versions, ['v1', 'v1+']);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      await openDiscount(tester);
      await tapKey(tester, 'discount-archive');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(discounts.writes, isEmpty);
    });

    testWidgets('archive returns to the list without the discount', (
      tester,
    ) async {
      await openDiscount(tester);
      await tapKey(tester, 'discount-archive');
      await confirm(tester);
      expect(discounts.writes, ['archive']);
      expect(find.text('Discount archived.'), findsOneWidget);
      expect(find.byKey(const Key('discount-1')), findsNothing);
    });

    testWidgets('a version conflict shows the latest values, writes once', (
      tester,
    ) async {
      discounts.writeError = const AppFailure(
        FailureKind.conflict,
        'Changed',
        code: 'VERSION_CONFLICT',
      );
      await openDiscount(tester);
      await tapKey(tester, 'discount-pause');
      await confirm(tester);
      expect(discounts.writes, ['pause']);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(find.text('Discount paused.'), findsNothing);
    });

    testWidgets('an unconfirmed outcome never shows success', (tester) async {
      discounts.writeError = const AppFailure(FailureKind.network, 'offline');
      await openDiscount(tester);
      await tapKey(tester, 'discount-pause');
      await confirm(tester);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(find.text('Discount paused.'), findsNothing);
    });
  });

  group('list pause switch', () {
    OrangeSwitch toggleOf(WidgetTester tester, int id) =>
        tester.widget<OrangeSwitch>(find.byKey(Key('discount-toggle-$id')));

    Future<void> openList(WidgetTester tester) async {
      await open(tester);
      await tapKey(tester, 'discount-open');
    }

    testWidgets('pause, then resume: confirmed, status pill kept', (
      tester,
    ) async {
      await openList(tester);
      expect(toggleOf(tester, 1).value, isTrue);
      expect(find.text('Active'), findsOneWidget);
      await tapKey(tester, 'discount-toggle-1');
      expect(find.text('Pause this discount?'), findsOneWidget);
      await confirm(tester);
      expect(discounts.writes, ['pause']);
      expect(toggleOf(tester, 1).value, isFalse);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Discount paused.'), findsOneWidget);
      await tapKey(tester, 'discount-toggle-1');
      expect(find.text('Resume this discount?'), findsOneWidget);
      await confirm(tester);
      expect(discounts.writes, ['pause', 'resume']);
      expect(discounts.versions, ['v1', 'v1+']);
      expect(toggleOf(tester, 1).value, isTrue);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      await openList(tester);
      await tapKey(tester, 'discount-toggle-1');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(discounts.writes, isEmpty);
      expect(toggleOf(tester, 1).value, isTrue);
    });

    testWidgets('a version conflict writes once and never shows success', (
      tester,
    ) async {
      discounts.writeError = const AppFailure(
        FailureKind.conflict,
        'Changed',
        code: 'VERSION_CONFLICT',
      );
      await openList(tester);
      await tapKey(tester, 'discount-toggle-1');
      await confirm(tester);
      expect(discounts.writes, ['pause']);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(find.text('Discount paused.'), findsNothing);
    });

    testWidgets('an unconfirmed outcome keeps the switch unchanged', (
      tester,
    ) async {
      discounts.writeError = const AppFailure(FailureKind.network, 'offline');
      await openList(tester);
      await tapKey(tester, 'discount-toggle-1');
      await confirm(tester);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(find.text('Discount paused.'), findsNothing);
      expect(toggleOf(tester, 1).value, isTrue);
    });
  });

  group('form', () {
    Future<void> openCreate(WidgetTester tester) async {
      discounts.discounts = [];
      await open(tester);
      await tapKey(tester, 'discount-create-new');
    }

    FilledButton save(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('discount-save')));

    testWidgets('fixed price: preview, validation, confirm, one create', (
      tester,
    ) async {
      await openCreate(tester);
      expect(save(tester).onPressed, isNull);
      await tapKey(tester, 'discount-type-fixed_price');
      await tester.enterText(
        find.byKey(const Key('discount-fixed-price')),
        '120',
      );
      await tester.pumpAndSettle();
      expect(find.text('Must be below the regular price.'), findsOneWidget);
      expect(save(tester).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('discount-fixed-price')),
        '80',
      );
      await tester.pumpAndSettle();
      expect(find.text('Final selling price · CHF 80.00'), findsOneWidget);
      await tapKey(tester, 'discount-save');
      expect(find.text('Create this discount?'), findsOneWidget);
      await confirm(tester);
      expect(discounts.writes, ['create']);
      expect(discounts.lastDraft?.fixedPrice, '80');
      expect(find.text('Discount created.'), findsOneWidget);
      expect(find.text('Discount Overview'), findsOneWidget);
    });

    testWidgets('the Price card pencil opens the price screen', (tester) async {
      await openCreate(tester);
      await tapKey(tester, 'discount-type-fixed_price');
      await tester.enterText(
        find.byKey(const Key('discount-fixed-price')),
        '120',
      );
      await tester.pumpAndSettle();
      expect(find.text('Must be below the regular price.'), findsOneWidget);
      await tapKey(tester, 'discount-edit-price');
      expect(find.byType(ProductPriceUpdatePage), findsOneWidget);
      // A saved price returns true; the form reads the new regular price.
      discounts.regularPrice = const DiscountMoney(15000, 'CHF');
      container.read(routerProvider).pop(true);
      await tester.pumpAndSettle();
      expect(find.byType(ProductPriceUpdatePage), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('discount-regular-price')))
            .data,
        'CHF 150.00',
      );
      // The typed value stays and is valid against the new price.
      expect(find.text('Must be below the regular price.'), findsNothing);
      expect(discounts.writes, isEmpty);
    });

    testWidgets('no price permission: the Price card has no pencil', (
      tester,
    ) async {
      discounts.discounts = [];
      await open(
        tester,
        access: const ProductAccess(adjustStock: true, manageDiscounts: true),
      );
      await tapKey(tester, 'discount-create-new');
      await tapKey(tester, 'discount-type-percentage');
      expect(find.byKey(const Key('discount-regular-price')), findsOneWidget);
      expect(find.byKey(const Key('discount-edit-price')), findsNothing);
    });

    testWidgets('percentage shows the calculated price', (tester) async {
      await openCreate(tester);
      await tapKey(tester, 'discount-type-percentage');
      await tester.enterText(find.byKey(const Key('discount-percent')), '150');
      await tester.pumpAndSettle();
      expect(find.textContaining('percentage above 0'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('discount-percent')), '20');
      await tester.pumpAndSettle();
      expect(find.text('Final selling price · CHF 80.00'), findsOneWidget);
      expect(save(tester).onPressed, isNotNull);
    });

    testWidgets('collective: bundle validation and regular bundle total', (
      tester,
    ) async {
      await openCreate(tester);
      await tapKey(tester, 'discount-type-collective');
      await tester.enterText(
        find.byKey(const Key('discount-bundle-quantity')),
        '1',
      );
      await tester.enterText(
        find.byKey(const Key('discount-bundle-price')),
        '80',
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number of at least 2.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('discount-bundle-quantity')),
        '5',
      );
      await tester.enterText(
        find.byKey(const Key('discount-bundle-price')),
        '400',
      );
      await tester.pumpAndSettle();
      expect(find.text('Regular bundle total · CHF 500.00'), findsOneWidget);
      expect(
        find.text('Final selling price · CHF 400.00 / bundle'),
        findsOneWidget,
      );
    });

    testWidgets('repeat weekly needs a day; minimum quantity is sent', (
      tester,
    ) async {
      await openCreate(tester);
      await tapKey(tester, 'discount-type-percentage');
      await tester.enterText(find.byKey(const Key('discount-percent')), '20');
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-section-repeat');
      await tapKey(tester, 'discount-repeat-weekly');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('discount-repeat-apply')),
            )
            .onPressed,
        isNull,
      );
      await tapKey(tester, 'discount-weekday-sun');
      await tapKey(tester, 'discount-repeat-apply');
      expect(find.textContaining('Every Sun'), findsWidgets);
      await tapKey(tester, 'discount-section-minimum');
      await tester.enterText(find.byKey(const Key('discount-minimum')), '5');
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-section-schedule');
      // The start date card slides up; Confirm sets the schedule.
      await tapKey(tester, 'discount-start-date');
      expect(find.text('Editing Start Date'), findsOneWidget);
      await tapKey(tester, 'discount-date-confirm');
      expect(find.byKey(const Key('discount-no-end')), findsOneWidget);
      await tapKey(tester, 'discount-save');
      await confirm(tester);
      final draft = discounts.lastDraft!;
      expect(draft.repeat.weekdays, {Weekday.sun});
      expect(draft.minimumQuantity, '5');
      expect(draft.schedule?.hasEnd, isFalse);
    });

    testWidgets('server field errors land on the field; values are kept', (
      tester,
    ) async {
      discounts.writeError = const AppFailure(
        FailureKind.validation,
        'Some fields are invalid.',
        code: 'VALIDATION_FAILED',
        fieldErrors: [AppFieldError('percent', 'INVALID_PERCENT')],
      );
      await openCreate(tester);
      await tapKey(tester, 'discount-type-percentage');
      await tester.enterText(find.byKey(const Key('discount-percent')), '20');
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-save');
      await confirm(tester);
      expect(find.textContaining('percentage above 0'), findsOneWidget);
      expect(find.text('Discount created.'), findsNothing);
      expect(find.text('20'), findsWidgets);
    });

    testWidgets('a whole-discount rule is translated', (tester) async {
      discounts.writeError = const AppFailure(
        FailureKind.validation,
        'Not allowed.',
        code: 'BUSINESS_RULE_VIOLATION',
        fieldErrors: [AppFieldError('', 'PRODUCT_NOT_DISCOUNTABLE')],
      );
      await openCreate(tester);
      await tapKey(tester, 'discount-type-percentage');
      await tester.enterText(find.byKey(const Key('discount-percent')), '20');
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-save');
      await confirm(tester);
      expect(
        find.text('The POS cannot discount this product.'),
        findsOneWidget,
      );
    });

    testWidgets('date card: pick a day; time wheels: 24-hour values', (
      tester,
    ) async {
      await openCreate(tester);
      await tapKey(tester, 'discount-type-percentage');
      await tapKey(tester, 'discount-section-schedule');
      await tapKey(tester, 'discount-start-date');
      final month = DateTime.now();
      await tapKey(tester, 'discount-day-15');
      await tapKey(tester, 'discount-date-confirm');
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('discount-start-date')),
                matching: find.byType(Text),
              ),
            )
            .data,
        DateFormat.yMMMd('en').format(DateTime(month.year, month.month, 15)),
      );
      await tapKey(tester, 'discount-start-time');
      expect(find.text('Editing Start Time · 24-hour time'), findsOneWidget);
      expect(find.text('Select Time'), findsOneWidget);
      // 09:00 → two hours up, one minute down (wraps to 59).
      await tapKey(tester, 'discount-time-hour-up');
      await tapKey(tester, 'discount-time-hour-up');
      await tapKey(tester, 'discount-time-minute-down');
      expect(find.text('Selected · 11:59'), findsOneWidget);
      // Scrolling the hour wheel turns it too.
      await tester.drag(
        find.byKey(const Key('discount-time-hour')),
        const Offset(0, -64),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected · 12:59'), findsOneWidget);
      await tapKey(tester, 'discount-time-confirm');
      expect(
        find.descendant(
          of: find.byKey(const Key('discount-start-time')),
          matching: find.text('12:59'),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'discount-start-time');
      await tapKey(tester, 'discount-sheet-cancel');
      expect(find.text('12:59'), findsOneWidget);
      expect(discounts.writes, isEmpty);
    });

    testWidgets('cards open and close without overflow on a phone', (
      tester,
    ) async {
      await open(tester);
      // A phone-sized screen where the open cards need scrolling.
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-open');
      await tapKey(tester, 'discount-edit-1');
      for (final key in [
        'discount-section-schedule',
        'discount-section-minimum',
        'discount-section-schedule',
        'discount-section-minimum',
      ]) {
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        // Every animation frame: an overflow would fail the test here.
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: '$key $frame');
        }
        await tester.pumpAndSettle();
      }
    });

    testWidgets('an opened card scrolls above the bottom bar', (tester) async {
      await open(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-open');
      await tapKey(tester, 'discount-edit-1');
      // Minimum Quantity just visible at the bottom, above the save bar.
      final header = find.byKey(const Key('discount-section-minimum'));
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(ProductActionSurface));
      final field = tester.getRect(find.byKey(const Key('discount-minimum')));
      expect(field.bottom, lessThanOrEqualTo(bar.top));
      expect(tester.getRect(header).top, greaterThanOrEqualTo(0));
    });

    testWidgets('time card: the 12-hour choice stays the default', (
      tester,
    ) async {
      final store = MemorySecretStore();
      discounts.discounts = [];
      await open(tester, more: [secretStoreProvider.overrideWithValue(store)]);
      await tapKey(tester, 'discount-create-new');
      await tapKey(tester, 'discount-type-percentage');
      await tester.enterText(find.byKey(const Key('discount-percent')), '20');
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-section-schedule');
      await tapKey(tester, 'discount-start-time');
      expect(find.byKey(const Key('discount-time-meridiem')), findsNothing);
      // Switch to 12-hour: 09:00 is shown as 09 AM; one step makes it PM.
      await tapKey(tester, 'discount-time-format');
      expect(find.text('Editing Start Time · 12-hour time'), findsOneWidget);
      expect(find.byKey(const Key('discount-time-meridiem')), findsOneWidget);
      await tapKey(tester, 'discount-time-meridiem-up');
      expect(find.textContaining('9:00'), findsWidgets);
      expect(find.textContaining('PM'), findsWidgets);
      await tapKey(tester, 'discount-time-confirm');
      expect(
        find.descendant(
          of: find.byKey(const Key('discount-start-time')),
          matching: find.textContaining('PM'),
        ),
        findsOneWidget,
      );
      expect(store.values['orangeone.time_format'], '12h');
      // Opening the card again: no need to switch again.
      await tapKey(tester, 'discount-start-time');
      expect(find.byKey(const Key('discount-time-meridiem')), findsOneWidget);
      await tapKey(tester, 'discount-sheet-cancel');
      // Stored as 24-hour time.
      await tapKey(tester, 'discount-save');
      await confirm(tester);
      final start = discounts.lastDraft!.schedule!.startTime;
      expect((start.hour, start.minute), (21, 0));
    });

    testWidgets('the type input shows the type icon', (tester) async {
      await openCreate(tester);
      String? iconOf(String key) {
        final field = tester.widget<TextField>(find.byKey(Key(key)));
        final prefix = field.decoration?.prefixIcon;
        if (prefix is! Padding) return null;
        return (prefix.child! as DiscountSvgIcon).asset;
      }

      await tapKey(tester, 'discount-type-fixed_price');
      expect(iconOf('discount-fixed-price'), contains('discount_fixed'));
      await tapKey(tester, 'discount-type-percentage');
      expect(iconOf('discount-percent'), contains('discount_percent'));
      await tapKey(tester, 'discount-type-collective');
      expect(
        iconOf('discount-bundle-quantity'),
        contains('discount_collective'),
      );
    });

    testWidgets('edit: the archive icon archives with DELETE once', (
      tester,
    ) async {
      await open(tester);
      await tapKey(tester, 'discount-open');
      await tapKey(tester, 'discount-edit-1');
      await tapKey(tester, 'discount-form-archive');
      expect(find.text('Archive this discount?'), findsOneWidget);
      await confirm(tester);
      expect(discounts.writes, ['archive']);
      expect(find.text('Discount archived.'), findsOneWidget);
    });

    group('review of #63', () {
      FilledButton saveButton(WidgetTester tester) =>
          tester.widget<FilledButton>(find.byKey(const Key('discount-save')));

      Future<void> openEdit(WidgetTester tester) async {
        await open(tester);
        await tapKey(tester, 'discount-open');
        await tapKey(tester, 'discount-edit-1');
      }

      Future<void> typePercent(WidgetTester tester, String value) async {
        final field = find.byKey(const Key('discount-percent'));
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pumpAndSettle();
      }

      String percentText(WidgetTester tester) => tester
          .widget<TextField>(find.byKey(const Key('discount-percent')))
          .controller!
          .text;

      // P2: Save, Archive and back are blocked while a confirmed archive is
      // pending; a failed archive restores them with the draft intact.
      testWidgets('a pending archive blocks Save and back; failure restores', (
        tester,
      ) async {
        await openEdit(tester);
        await typePercent(tester, '25');
        final gate = Completer<void>();
        discounts
          ..pendingWrite = gate
          ..writeError = const AppFailure(FailureKind.network, 'offline');
        await tapKey(tester, 'discount-form-archive');
        await tester.tap(find.byKey(const Key('discount-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(discounts.writes, ['archive']);
        // Pending: nothing else can start, and the form cannot be left.
        expect(saveButton(tester).onPressed, isNull);
        expect(find.text('Archiving…'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('discount-form-archive')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester.widget<PopScope<Object?>>(find.byType(PopScope).last).canPop,
          isFalse,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('discount-percent')))
              .enabled,
          isFalse,
        );
        await tester.tap(find.byKey(const Key('discount-save')));
        await tester.pump();
        expect(discounts.writes, ['archive']);
        // The delayed answer is a failure: controls return, draft stays.
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.textContaining('could not be confirmed'), findsOneWidget);
        expect(percentText(tester), '25');
        expect(saveButton(tester).onPressed, isNotNull);
        expect(
          tester.widget<PopScope<Object?>>(find.byType(PopScope).last).canPop,
          isTrue,
        );
        expect(find.text('Edit Discount'), findsOneWidget);
      });

      testWidgets('a delayed archive that succeeds closes the form', (
        tester,
      ) async {
        await openEdit(tester);
        final gate = Completer<void>();
        discounts.pendingWrite = gate;
        await tapKey(tester, 'discount-form-archive');
        await tester.tap(find.byKey(const Key('discount-confirm')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Edit Discount'), findsOneWidget);
        gate.complete();
        await tester.pumpAndSettle();
        expect(discounts.writes, ['archive']);
        expect(find.text('Discount archived.'), findsOneWidget);
        expect(find.text('Edit Discount'), findsNothing);
      });

      // P1: a committed create whose answer is lost, then an edited retry.
      testWidgets('a lost create and an edited retry make one discount', (
        tester,
      ) async {
        discounts.discounts = [];
        await open(tester);
        await tapKey(tester, 'discount-create-new');
        await tapKey(tester, 'discount-type-percentage');
        await typePercent(tester, '20');
        discounts.loseCreateAnswer = true;
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.writes, ['create']);
        expect(discounts.discounts, hasLength(1), reason: 'committed');
        expect(find.textContaining('could not be confirmed'), findsOneWidget);
        // The user changes the value and saves again: the form checks the
        // server first and finds the committed discount; nothing is sent.
        await typePercent(tester, '25');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.writes, ['create']);
        expect(discounts.discounts, hasLength(1));
        expect(find.textContaining('did create this discount'), findsOneWidget);
        expect(find.text('Edit Discount'), findsOneWidget);
        expect(percentText(tester), '25');
        // Saving now updates that discount with the user's change.
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.writes, ['create', 'update']);
        expect(discounts.lastDraft?.percent, '25');
        expect(discounts.discounts, hasLength(1));
      });

      testWidgets('an identical retry after a lost create replays it', (
        tester,
      ) async {
        discounts.discounts = [];
        await open(tester);
        await tapKey(tester, 'discount-create-new');
        await tapKey(tester, 'discount-type-percentage');
        await typePercent(tester, '20');
        discounts.loseCreateAnswer = true;
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        // The same request again (same Idempotency-Key in the real
        // repository): the server replays it, no second discount.
        expect(discounts.writes, ['create', 'create']);
        expect(discounts.discounts, hasLength(1));
        expect(find.text('Discount created.'), findsOneWidget);
      });

      testWidgets('an edited retry creates when the lost create did not land', (
        tester,
      ) async {
        discounts.discounts = [];
        await open(tester);
        await tapKey(tester, 'discount-create-new');
        await tapKey(tester, 'discount-type-percentage');
        await typePercent(tester, '20');
        discounts.writeError = const AppFailure(FailureKind.timeout, 'slow');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.discounts, isEmpty);
        discounts.writeError = null;
        await typePercent(tester, '25');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.writes, ['create', 'create']);
        expect(discounts.discounts.single.percent, '25');
        expect(find.text('Discount created.'), findsOneWidget);
      });

      // P1 follow-up: a formatting-only change after a lost create.
      testWidgets('20 to 20.00 after a lost create makes no second one', (
        tester,
      ) async {
        discounts.discounts = [];
        await open(tester);
        await tapKey(tester, 'discount-create-new');
        await tapKey(tester, 'discount-type-percentage');
        await typePercent(tester, '20');
        discounts.loseCreateAnswer = true;
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.discounts, hasLength(1), reason: 'committed');
        await typePercent(tester, '20.00');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        // The original request is replayed, not a new "20.00" one.
        expect(discounts.lastDraft?.percent, '20');
        expect(discounts.writes, ['create', 'create']);
        expect(discounts.discounts, hasLength(1));
        expect(find.text('Discount created.'), findsOneWidget);
      });

      testWidgets('the retry sends the original payload with its key', (
        tester,
      ) async {
        // A server that commits the first create, loses the answer, and
        // replays a known Idempotency-Key (like the real one).
        final server = FakeMobileApiServer();
        final stored = <Map<String, dynamic>>[];
        final byKey = <String, Map<String, dynamic>>{};
        var loseAnswer = true;
        Map<String, Object?> ok(Object? data) => {
          'data': data,
          'meta': {'request_id': 'r', 'server_time': '2026-10-13T08:00:00Z'},
        };
        server
          ..on(
            'GET /products/10/discounts',
            (request) => FakeReply(200, ok(discountListPayload(stored))),
          )
          ..on('POST /products/10/discounts', (request) {
            final key = request.headers['Idempotency-Key'] as String;
            final replay = byKey[key];
            if (replay != null) return FakeReply(201, ok(replay));
            final body = request.data is String
                ? jsonDecode(request.data as String) as Map<String, dynamic>
                : request.data as Map<String, dynamic>;
            final created = discountPayload(
              id: 100 + stored.length,
              percent: body['percent'] as String?,
            );
            stored.add(created);
            byKey[key] = created;
            if (loseAnswer) {
              loseAnswer = false;
              throw DioException(
                requestOptions: request,
                type: DioExceptionType.receiveTimeout,
              );
            }
            return FakeReply(201, ok(created));
          });
        await open(
          tester,
          repository: OdooDiscountRepository(
            DiscountRemoteDataSource(fakeProductApi(server)),
          ),
        );
        await tapKey(tester, 'discount-create-new');
        await tapKey(tester, 'discount-type-percentage');
        await typePercent(tester, '20');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(find.textContaining('could not be confirmed'), findsOneWidget);
        expect(stored, hasLength(1), reason: 'the first POST committed');
        await typePercent(tester, '20.00');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        final posts = server.called('POST /products/10/discounts');
        expect(posts, hasLength(2));
        expect(
          posts[1].headers['Idempotency-Key'],
          posts[0].headers['Idempotency-Key'],
        );
        expect(jsonEncode(posts[1].data), jsonEncode(posts[0].data));
        expect(stored, hasLength(1), reason: 'no second discount');
        expect(find.text('Discount created.'), findsOneWidget);
      });

      // P1: concurrent changes to different parts both survive.
      testWidgets('a conflict shows the saved values; both changes survive', (
        tester,
      ) async {
        discounts.checkVersions = true;
        await openEdit(tester);
        await typePercent(tester, '25');
        // Meanwhile someone else adds a schedule (new version).
        discounts.discounts = [
          discountOf(
            version: 'v2',
            schedule: const DiscountSchedule(
              startDate: LocalDate(2026, 12, 1),
              startTime: TimeOfDayValue(9, 0),
            ),
          ),
        ];
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.writes, ['update']);
        expect(discounts.versions, ['v1']);
        expect(find.byKey(const Key('discount-conflict')), findsOneWidget);
        expect(
          find.byKey(const Key('discount-conflict-saved-schedule')),
          findsOneWidget,
        );
        expect(find.textContaining('Dec 1, 2026'), findsWidgets);
        // The draft is kept and nothing more can be sent yet.
        expect(percentText(tester), '25');
        expect(saveButton(tester).onPressed, isNull);
        await tapKey(tester, 'discount-conflict-apply');
        expect(find.byKey(const Key('discount-conflict')), findsNothing);
        expect(percentText(tester), '25');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.writes, ['update', 'update']);
        expect(discounts.versions, ['v1', 'v2']);
        expect(discounts.lastDraft?.percent, '25');
        expect(discounts.lastDraft?.schedule?.startDate.iso, '2026-12-01');
        expect(find.text('Discount saved.'), findsOneWidget);
      });

      testWidgets('the same part changed on both sides needs a choice', (
        tester,
      ) async {
        discounts.checkVersions = true;
        await openEdit(tester);
        await typePercent(tester, '25');
        discounts.discounts = [discountOf(version: 'v2', percent: '30')];
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(
          find.byKey(const Key('discount-conflict-yours-value')),
          findsOneWidget,
        );
        final apply = find.byKey(const Key('discount-conflict-apply'));
        expect(tester.widget<FilledButton>(apply).onPressed, isNull);
        await tapKey(tester, 'discount-conflict-saved-choice-value');
        expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
        await tapKey(tester, 'discount-conflict-apply');
        expect(percentText(tester), '30');
        await tapKey(tester, 'discount-save');
        await confirm(tester);
        expect(discounts.versions, ['v1', 'v2']);
        expect(discounts.lastDraft?.percent, '30');
      });
    });

    testWidgets('edit loads the stored values and updates once', (
      tester,
    ) async {
      await open(tester);
      await tapKey(tester, 'discount-open');
      await tapKey(tester, 'discount-edit-1');
      expect(find.text('Edit Discount'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('discount-percent')))
            .controller
            ?.text,
        '20',
      );
      await tester.enterText(find.byKey(const Key('discount-percent')), '25');
      await tester.pumpAndSettle();
      await tapKey(tester, 'discount-save');
      expect(find.text('Save these changes?'), findsOneWidget);
      await confirm(tester);
      expect(discounts.writes, ['update']);
      expect(discounts.versions, ['v1']);
      expect(find.text('Discount saved.'), findsOneWidget);
    });

    testWidgets('a limit reached product cannot create more', (tester) async {
      discounts.limit = 1;
      await open(tester);
      await tapKey(tester, 'discount-open');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('discount-list-create')))
            .onPressed,
        isNull,
      );
      expect(
        find.text('This product already has the maximum number of discounts.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('offline: discount writes are disabled, nothing is queued', (
    tester,
  ) async {
    final database = ReadCacheDatabase(NativeDatabase.memory());
    final cache = EncryptedReadCache(database, sessionSecret: 'discounts');
    addTearDown(() async {
      await cache.close();
      await database.close();
    });
    cache.connectionChanged(connected: false);
    await open(tester, more: [readCacheProvider.overrideWithValue(cache)]);
    await tapKey(tester, 'discount-open');
    expect(find.textContaining('You are offline'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('discount-list-create')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<EditPencilButton>(find.byKey(const Key('discount-edit-1')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OrangeSwitch>(find.byKey(const Key('discount-toggle-1')))
          .onChanged,
      isNull,
    );
    await tapKey(tester, 'discount-1');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('discount-pause')))
          .onPressed,
      isNull,
    );
    expect(discounts.writes, isEmpty);
  });
}
