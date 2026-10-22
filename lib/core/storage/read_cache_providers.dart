import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';

final readCacheDatabaseProvider = Provider<ReadCacheDatabase>((ref) {
  final database = ReadCacheDatabase.platform();
  ref.onDispose(database.close);
  return database;
}, name: 'readCacheDatabaseProvider');

/// App composition injects the authorized session cache. Tests may override it.
final readCacheProvider = Provider<EncryptedReadCache?>(
  (ref) => null,
  name: 'readCacheProvider',
);

final readCacheChangesProvider = StreamProvider<int>(
  (ref) => ref.watch(readCacheProvider)?.changes ?? const Stream.empty(),
  name: 'readCacheChangesProvider',
);

final readCacheRecoveryProvider = StreamProvider<int>(
  (ref) => ref.watch(readCacheProvider)?.recovery ?? const Stream.empty(),
  name: 'readCacheRecoveryProvider',
);
