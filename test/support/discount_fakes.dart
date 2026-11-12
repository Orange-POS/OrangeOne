import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/features/discounts/data/models/discount_model.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/repositories/discount_repository.dart';

/// A `Discount` payload of the Mobile API 1.1 contract (product 10, CHF 100).
Map<String, dynamic> discountPayload({
  int id = 1,
  int productId = 10,
  String type = 'percentage',
  String? percent = '20',
  String? fixedPrice,
  String? bundleQuantity,
  String? bundlePrice,
  String status = 'active',
  bool paused = false,
  bool active = true,
  String version = 'v1',
  Map<String, dynamic>? schedule,
  Map<String, dynamic>? repeat,
  String? minimumQuantity,
}) => {
  'id': id,
  'product_id': productId,
  'type': type,
  'label': '20% off',
  'fixed_price': fixedPrice == null
      ? null
      : {'amount': fixedPrice, 'currency': 'CHF'},
  'percent': type == 'percentage' ? percent : null,
  'bundle_quantity': bundleQuantity,
  'bundle_price': bundlePrice == null
      ? null
      : {'amount': bundlePrice, 'currency': 'CHF'},
  'regular_price': {'amount': '100.00', 'currency': 'CHF'},
  'preview': {
    'unit_price': type == 'collective'
        ? null
        : {'amount': '80.00', 'currency': 'CHF'},
    'bundle_regular_price': type == 'collective'
        ? {'amount': '500.00', 'currency': 'CHF'}
        : null,
    'savings': {'amount': '20.00', 'currency': 'CHF'},
    'savings_percent': '20.00',
  },
  'schedule': schedule,
  'repeat':
      repeat ?? {'type': 'none', 'weekdays': <String>[], 'annual_date': null},
  'minimum_quantity': minimumQuantity,
  'status': status,
  'applies_now': status == 'active',
  'paused': paused,
  'warnings': <Object>[],
  'active': active,
  'version': version,
  'created_at': '2026-10-13T08:00:00Z',
  'updated_at': '2026-10-13T08:00:00Z',
};

Map<String, dynamic> discountListPayload(
  List<Map<String, dynamic>> discounts, {
  int productId = 10,
  int limit = 20,
}) => {
  'product_id': productId,
  'regular_price': {'amount': '100.00', 'currency': 'CHF'},
  'counts': {
    'total': discounts.where((d) => d['active'] == true).length,
    'active': discounts.where((d) => d['status'] == 'active').length,
    'scheduled': 0,
    'expired': 0,
    'paused': discounts.where((d) => d['status'] == 'paused').length,
  },
  'limit': limit,
  'discounts': discounts,
};

/// A shop whose `GET /meta` lists product discounts.
final Override discountBackend = backendFeaturesProvider.overrideWith(
  (ref) async => BackendFeatures({
    ...BackendFeatures.baseline.names,
    BackendFeatures.productDiscounts,
  }, confirmed: true),
);

Discount discountOf({
  int id = 1,
  DiscountType type = DiscountType.percentage,
  String version = 'v1',
  bool paused = false,
  bool active = true,
  DiscountStatus status = DiscountStatus.active,
  String percent = '20',
  DiscountSchedule? schedule,
}) => Discount(
  id: id,
  productId: 10,
  type: type,
  label: '20% off',
  percent: type == DiscountType.percentage ? percent : null,
  fixedPrice: type == DiscountType.fixedPrice
      ? const DiscountMoney(8000, 'CHF')
      : null,
  bundleQuantity: type == DiscountType.collective ? 5 : null,
  bundlePrice: type == DiscountType.collective
      ? const DiscountMoney(40000, 'CHF')
      : null,
  regularPrice: const DiscountMoney(10000, 'CHF'),
  preview: const DiscountPreview(
    unitPrice: DiscountMoney(8000, 'CHF'),
    savings: DiscountMoney(2000, 'CHF'),
    savingsPercent: '20.00',
  ),
  schedule: schedule,
  repeat: DiscountRepeat.none,
  status: paused ? DiscountStatus.paused : status,
  appliesNow: !paused && status == DiscountStatus.active,
  paused: paused,
  active: active,
  version: version,
);

/// In-memory discounts of product 10 (regular price CHF 100.00).
class FakeDiscountRepository implements DiscountRepository {
  new([List<Discount>? discounts]) : discounts = discounts ?? [discountOf()];

  List<Discount> discounts;
  int limit = 20;
  AppFailure? readError;
  AppFailure? writeError;
  Completer<void>? pendingWrite;
  final writes = <String>[];
  final versions = <String>[];
  DiscountDraft? lastDraft;
  int _next = 100;

  /// The next create is committed but its answer is lost (a network
  /// failure after the server saved it). Only a retry with the exact same
  /// serialized payload is replayed, as the real repository reuses the
  /// `Idempotency-Key` only for that; any other payload creates again.
  bool loseCreateAnswer = false;
  final _replay = <String, Discount>{};

  /// Updates and archives with a stale version fail with
  /// `VERSION_CONFLICT`, like the server's `If-Match` check.
  bool checkVersions = false;

  static String _payload(DiscountDraft draft) =>
      jsonEncode(DiscountInputModel.toJson(draft));

  void _checkVersion(Discount current) {
    if (!checkVersions) return;
    final stored = discounts.firstWhere((d) => d.id == current.id);
    if (stored.version != current.version) {
      throw const AppFailure(
        FailureKind.conflict,
        'Changed',
        code: 'VERSION_CONFLICT',
      );
    }
  }

  int lists = 0;

  /// The product's regular price in list reads.
  DiscountMoney regularPrice = const DiscountMoney(10000, 'CHF');

  ProductDiscounts _list() => ProductDiscounts(
    productId: 10,
    regularPrice: regularPrice,
    counts: DiscountCounts(
      total: discounts.where((d) => d.active).length,
      active: discounts.where((d) => d.status == DiscountStatus.active).length,
      scheduled: 0,
      expired: 0,
      paused: discounts.where((d) => d.paused).length,
    ),
    limit: limit,
    discounts: [...discounts.where((d) => d.active)],
  );

  @override
  Future<ProductDiscounts> list(int productId) async {
    lists++;
    if (readError != null) throw readError!;
    return _list();
  }

  @override
  Future<Discount> get(int discountId) async {
    if (readError != null) throw readError!;
    return discounts.firstWhere(
      (d) => d.id == discountId,
      orElse: () => throw const AppFailure(FailureKind.notFound, 'Not found'),
    );
  }

  Future<void> _write(String name, Discount? current) async {
    writes.add(name);
    if (current != null) versions.add(current.version);
    await pendingWrite?.future;
    if (writeError != null) throw writeError!;
  }

  Discount _replace(Discount old, Discount updated) {
    discounts = [
      for (final d in discounts)
        if (d.id == old.id) updated else d,
    ];
    return updated;
  }

  Discount _from(int id, DiscountDraft draft, String version) => Discount(
    id: id,
    productId: 10,
    type: draft.type!,
    label: 'saved',
    percent: draft.type == DiscountType.percentage ? draft.percent : null,
    fixedPrice: draft.type == DiscountType.fixedPrice
        ? DiscountMoney(DiscountMoney.parseCents(draft.fixedPrice)!, 'CHF')
        : null,
    bundleQuantity: draft.type == DiscountType.collective
        ? int.parse(draft.bundleQuantity)
        : null,
    bundlePrice: draft.type == DiscountType.collective
        ? DiscountMoney(DiscountMoney.parseCents(draft.bundlePrice)!, 'CHF')
        : null,
    regularPrice: const DiscountMoney(10000, 'CHF'),
    preview: const DiscountPreview(
      savings: DiscountMoney(2000, 'CHF'),
      savingsPercent: '20.00',
    ),
    schedule: draft.schedule,
    repeat: draft.repeat,
    minimumQuantity: draft.minimumQuantity.isEmpty
        ? null
        : draft.minimumQuantity,
    status: DiscountStatus.active,
    appliesNow: true,
    paused: false,
    active: true,
    version: version,
  );

  @override
  Future<Discount> create(int productId, DiscountDraft draft) async {
    lastDraft = draft;
    await _write('create', null);
    final replayed = _replay[_payload(draft)];
    if (replayed != null) return replayed;
    final created = _from(_next++, draft, 'v1');
    discounts = [created, ...discounts];
    if (loseCreateAnswer) {
      loseCreateAnswer = false;
      _replay[_payload(draft)] = created;
      throw const AppFailure(FailureKind.network, 'Connection lost');
    }
    return created;
  }

  @override
  Future<Discount> update(Discount current, DiscountDraft draft) async {
    lastDraft = draft;
    await _write('update', current);
    _checkVersion(current);
    return _replace(current, _from(current.id, draft, '${current.version}+'));
  }

  Discount _state(Discount d, {bool? paused, bool? active}) => Discount(
    id: d.id,
    productId: d.productId,
    type: d.type,
    label: d.label,
    percent: d.percent,
    fixedPrice: d.fixedPrice,
    bundleQuantity: d.bundleQuantity,
    bundlePrice: d.bundlePrice,
    regularPrice: d.regularPrice,
    preview: d.preview,
    schedule: d.schedule,
    repeat: d.repeat,
    minimumQuantity: d.minimumQuantity,
    status: active == false
        ? DiscountStatus.archived
        : (paused ?? d.paused)
        ? DiscountStatus.paused
        : DiscountStatus.active,
    appliesNow: active != false && !(paused ?? d.paused),
    paused: paused ?? d.paused,
    active: active ?? d.active,
    version: '${d.version}+',
  );

  @override
  Future<Discount> archive(Discount current) async {
    await _write('archive', current);
    _checkVersion(current);
    return _replace(current, _state(current, active: false));
  }

  @override
  Future<Discount> pause(Discount current) async {
    await _write('pause', current);
    return _replace(current, _state(current, paused: true));
  }

  @override
  Future<Discount> resume(Discount current) async {
    await _write('resume', current);
    return _replace(current, _state(current, paused: false));
  }
}
