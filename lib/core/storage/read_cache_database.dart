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

  @override
  int get schemaVersion => 1;
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
  );
}
