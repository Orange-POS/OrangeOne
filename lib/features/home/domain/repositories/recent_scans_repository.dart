import 'package:orange_one/features/home/domain/entities/product.dart';

/// Products the user scanned recently in the current session.
abstract interface class RecentScansRepository {
  /// Newest first. Empty when nothing was scanned or the history is
  /// unavailable; it never fails a scan.
  Future<List<Product>> load();

  /// Moves [product] to the front. Failures are not reported: the history is
  /// a convenience and must not interrupt scanning.
  Future<void> record(Product product);
}
