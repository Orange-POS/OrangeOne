import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/models/product_changes_model.dart';

/// Refreshes this session's cached products from `GET /products/changes`.
///
/// Best effort and read-only: a failed or interrupted sync leaves valid
/// snapshots and the last applied position untouched, so the next run
/// resumes. Only an expired position (`SYNC_TOKEN_EXPIRED`) or lost read
/// access drops the session's snapshots, because they can no longer be
/// verified or must not be shown.
class ProductCacheSynchronizer {
  new(this._catalog, this._cache, {this.maxPages = 10});
  final ProductCatalogRemoteDataSource _catalog;
  final EncryptedReadCache _cache;

  /// Bounds one run; the saved position lets the next run continue.
  final int maxPages;
  Future<void>? _running;

  /// Concurrent requests share one run.
  Future<void> sync() =>
      _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    try {
      var state = await _cache.syncState();
      for (var page = 0; state != null && page < maxPages; page++) {
        final ProductChangesPage changes;
        try {
          changes = ProductChangesModel.parse(
            (await _catalog.changes(state.since)).data,
          );
        } on AppFailure catch (failure) {
          if (failure.code == 'SYNC_TOKEN_EXPIRED' ||
              failure.kind == FailureKind.forbidden) {
            await _cache.resetSync();
          }
          return;
        }
        await _cache.applyChanges(
          changed: changes.changed,
          removedIds: changes.removedIds,
          nextSince: changes.nextSince,
        );
        if (!changes.hasMore) return;
        state = (since: changes.nextSince);
      }
    } on Exception {
      // Cancelled by a mutation/logout, or storage trouble: keep the cache.
    }
  }
}
