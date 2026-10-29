import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

/// Versioned schema with encrypted product payloads.
class ReadCacheDatabase extends GeneratedDatabase {
  new(super.executor);

  factory platform() => ReadCacheDatabase(
    LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      return NativeDatabase.createInBackground(
        File('${directory.path}/product_reads.sqlite'),
      );
    }),
  );

  /// 2: Mobile API v2 product snapshots (`EncryptedReadCache.schema`).
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => customStatement('''
      CREATE TABLE product_reads (
        owner TEXT NOT NULL, code TEXT NOT NULL, payload TEXT NOT NULL,
        PRIMARY KEY(owner, code)
      )
      '''),
    // v1 snapshots use the v1 API shape and key; they expire within a day
    // and cannot be verified, so they are discarded rather than converted.
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await customStatement('DELETE FROM product_reads');
    },
  );
}
