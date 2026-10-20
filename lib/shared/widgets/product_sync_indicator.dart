import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';

/// The status describes server verification, not merely Wi-Fi availability.
class ProductSyncIndicator extends ConsumerWidget {
  const new({required this.barcode, super.key});
  final String? barcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(readCacheChangesProvider);
    final cache = ref.watch(readCacheProvider);
    final status = cache?.status(barcode ?? '');
    final phase = status?.phase ?? ReadSyncPhase.online;
    final (icon, label) = switch (phase) {
      ReadSyncPhase.pending => (Icons.sync, 'Syncing product'),
      ReadSyncPhase.online => (
        Icons.cloud_done_outlined,
        'Online: server verified',
      ),
      ReadSyncPhase.offline => (
        Icons.cloud_off_outlined,
        'Offline: cached data may be outdated',
      ),
      ReadSyncPhase.failed => (
        Icons.sync_problem_outlined,
        'Product synchronization failed',
      ),
    };
    final time = status?.verifiedAt;
    final message = time == null
        ? label
        : '$label. Last verified ${time.toLocal()}';
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        child: Icon(
          icon,
          key: const Key('product-sync-status'),
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
