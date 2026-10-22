import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';

/// Pause owner resolution after encryption, before INSERT dispatch.
class PausingOwnerCache extends EncryptedReadCache {
  new(super.database) : super(sessionSecret: 'test-session');
  bool pauseNextOwner = false;
  final preparing = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<String> get owner async {
    final identity = await super.owner;
    if (pauseNextOwner) {
      pauseNextOwner = false;
      preparing.complete();
      await resume.future;
    }
    return identity;
  }
}

/// Model an executor that yields after receiving INSERT but before running SQL.
class PausingInsertDatabase extends ReadCacheDatabase {
  new() : super(NativeDatabase.memory());
  bool pauseNextInsert = false;
  final inserting = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) async {
    if (pauseNextInsert && statement.startsWith('INSERT')) {
      pauseNextInsert = false;
      inserting.complete();
      await resume.future;
    }
    await super.customStatement(statement, args);
  }
}

void main() {
  const code = '00123';
  const old = <String, dynamic>{
    'id': 1,
    'name': 'Before mutation',
    'barcode': code,
  };
  for (final closing in [false, true]) {
    test(
      'purge follows an already dispatched INSERT, close=$closing',
      () async {
        final database = PausingInsertDatabase();
        final cache = EncryptedReadCache(
          database,
          sessionSecret: 'test-session',
        );
        addTearDown(() async {
          if (!database.resume.isCompleted) database.resume.complete();
          await cache.close();
          await database.close();
        });
        await cache.load(code, () async => old);
        database.pauseNextInsert = true;
        final pending = cache.load(code, () async => old);
        final cancelled = expectLater(
          pending,
          throwsA(same(cancelledOperation)),
        );
        await database.inserting.future;
        var writes = 0;
        final purge = closing
            ? cache.close()
            : cache.write(() async {
                writes++;
              });
        expect(writes, 0);
        database.resume.complete();
        await purge;
        await cancelled;
        expect(
          await database.customSelect('SELECT * FROM product_reads').get(),
          isEmpty,
        );
        expect(await cache.read(code), isNull);
        expect(writes, closing ? 0 : 1);
      },
    );
  }

  for (final outcome in ['success', 'uncertain', 'close']) {
    test('late persistence cannot undo $outcome purge', () async {
      final database = ReadCacheDatabase(NativeDatabase.memory());
      final cache = PausingOwnerCache(database);
      addTearDown(() async {
        if (!cache.resume.isCompleted) cache.resume.complete();
        await cache.close();
        await database.close();
      });
      await cache.load(code, () async => old);
      cache.pauseNextOwner = true;
      final pending = cache.load(code, () async => old);
      final cancelled = expectLater(pending, throwsA(same(cancelledOperation)));
      await cache.preparing.future;
      var writes = 0;
      if (outcome == 'close') {
        await cache.close();
      } else {
        final mutation = cache.write(() async {
          writes++;
          if (outcome == 'uncertain') {
            throw const AppFailure(FailureKind.timeout, 'Uncertain write');
          }
        });
        if (outcome == 'uncertain') {
          await expectLater(mutation, throwsA(isA<AppFailure>()));
        } else {
          await mutation;
        }
      }
      expect(
        await database.customSelect('SELECT * FROM product_reads').get(),
        isEmpty,
      );
      cache.resume.complete();
      await cancelled;
      expect(
        await database.customSelect('SELECT * FROM product_reads').get(),
        isEmpty,
      );
      expect(await cache.read(code), isNull);
      expect(writes, outcome == 'close' ? 0 : 1);
      if (outcome != 'close') {
        cache.connectionChanged(connected: false);
        var probes = 0;
        await expectLater(
          cache.load(code, () async {
            probes++;
            return old;
          }),
          throwsA(isA<AppFailure>()),
        );
        expect(probes, 0);
        expect(writes, 1);
      }
    });
  }
}
