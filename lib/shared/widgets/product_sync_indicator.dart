import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';

/// Texts of a [ProductSyncIndicator]. The defaults are English.
class ProductSyncLabels {
  const new({
    this.pending = 'Syncing product',
    this.online = 'Online: server verified',
    this.offline = 'Offline: cached data may be outdated',
    this.failed = 'Product synchronization failed',
    this.lastVerified = _lastVerified,
  });
  final String pending;
  final String online;
  final String offline;
  final String failed;

  /// Joins a status text and the time of the last verification.
  final String Function(String status, DateTime time) lastVerified;

  static String _lastVerified(String status, DateTime time) =>
      '$status. Last verified ${time.toLocal()}';
}

/// The status describes server verification, not merely Wi-Fi availability.
class ProductSyncIndicator extends ConsumerWidget {
  const new({
    required this.barcode,
    this.onlineIcon,
    this.labels = const ProductSyncLabels(),
    super.key,
  });
  final String? barcode;
  final Widget? onlineIcon;
  final ProductSyncLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(readCacheChangesProvider);
    final cache = ref.watch(readCacheProvider);
    final status = cache?.status(barcode ?? '');
    final phase = status?.phase ?? ReadSyncPhase.online;
    final (icon, label) = switch (phase) {
      ReadSyncPhase.pending => (Icons.sync, labels.pending),
      ReadSyncPhase.online => (Icons.cloud_done_outlined, labels.online),
      ReadSyncPhase.offline => (Icons.cloud_off_outlined, labels.offline),
      ReadSyncPhase.failed => (Icons.sync_problem_outlined, labels.failed),
    };
    final time = status?.verifiedAt;
    final message = time == null ? label : labels.lastVerified(label, time);
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        child: phase == ReadSyncPhase.online && onlineIcon != null
            ? KeyedSubtree(
                key: const Key('product-sync-status'),
                child: onlineIcon!,
              )
            : Icon(
                icon,
                key: const Key('product-sync-status'),
                color: Colors.white,
                size: 24,
              ),
      ),
    );
  }
}
