import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/product_payload.dart';

typedef ProductChangesPage = ({
  List<Map<String, dynamic>> changed,
  List<int> removedIds,
  String nextSince,
  bool hasMore,
});

/// Validates one `GET /products/changes` page before it touches the cache.
abstract final class ProductChangesModel {
  static ProductChangesPage parse(Object? data) {
    if (data is! Map<String, dynamic>) throw invalidResponse;
    final changed = data['changed'];
    final removed = data['removed_ids'];
    final nextSince = data['next_since'];
    final hasMore = data['has_more'];
    if (changed is! List ||
        removed is! List ||
        removed.any((id) => id is! int || id <= 0) ||
        nextSince is! String ||
        nextSince.isEmpty ||
        nextSince.length > 128 ||
        hasMore is! bool) {
      throw invalidResponse;
    }
    return (
      changed: [for (final item in changed) ProductPayload.productRecord(item)],
      removedIds: List<int>.from(removed),
      nextSince: nextSince,
      hasMore: hasMore,
    );
  }
}
