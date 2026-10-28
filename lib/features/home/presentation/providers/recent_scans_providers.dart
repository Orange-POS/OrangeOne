import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/home/data/repositories/recent_scans_repositories.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/recent_scans_repository.dart';

/// App composition binds this to the current session's cache. Without it the
/// history only lives in memory.
final Provider<RecentScansRepository> recentScansRepositoryProvider =
    Provider<RecentScansRepository>(
      (ref) => MemoryRecentScansRepository(),
      name: 'recentScansRepositoryProvider',
    );

/// The products shown in the scanner's "Last scanned" card, newest first.
final AsyncNotifierProvider<RecentScansController, List<Product>>
recentScansControllerProvider =
    AsyncNotifierProvider.autoDispose<RecentScansController, List<Product>>(
      RecentScansController.new,
      name: 'recentScansControllerProvider',
      retry: (count, error) => null,
    );

class RecentScansController extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() =>
      ref.watch(recentScansRepositoryProvider).load();

  /// Stores a product the server (or the offline cache) just returned, then
  /// reloads the list. Failures never reach the scan that triggered this.
  Future<void> record(Product product) async {
    final repository = ref.read(recentScansRepositoryProvider);
    try {
      await repository.record(product);
    } on Exception {
      return;
    }
    if (ref.mounted) ref.invalidateSelf();
  }
}
