import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/pending_writes.dart';
import 'package:orange_one/features/discounts/data/data_sources/discount_remote_data_source.dart';
import 'package:orange_one/features/discounts/data/models/discount_model.dart';
import 'package:orange_one/features/discounts/data/repositories/odoo_discount_repository.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/repositories/discount_repository.dart';

import '../../../support/discount_fakes.dart';
import '../../../support/mobile_api_fakes.dart';
import '../../../support/product_api_fakes.dart';

Map<String, Object?> _ok(Object? data) => {
  'data': data,
  'meta': {'request_id': 'r1', 'server_time': '2026-10-13T08:00:00Z'},
};

Map<String, Object?> _error(
  String code, {
  List<Map<String, Object?>> details = const [],
}) => {
  'error': {
    'code': code,
    'message': 'Server says no.',
    'retryable': false,
    'details': details,
  },
  'meta': {'request_id': 'r2'},
};

void main() {
  late FakeMobileApiServer server;
  late OdooDiscountRepository repository;
  var rejected = 0;

  setUp(() {
    server = FakeMobileApiServer();
    rejected = 0;
    repository = OdooDiscountRepository(
      DiscountRemoteDataSource(fakeProductApi(server)),
      onSessionRejected: () async => rejected++,
    );
  });

  const percentage = DiscountDraft(
    type: DiscountType.percentage,
    percent: '20',
  );

  group('mapping', () {
    test('a contract Discount maps every member', () {
      final discount = DiscountModel.parse(
        discountPayload(
          schedule: {
            'start_date': '2026-10-14',
            'start_time': '09:00',
            'end_date': null,
            'end_time': null,
            'start_at': '2026-10-14T07:00:00Z',
            'end_at': null,
            'timezone': 'Europe/Zurich',
          },
          repeat: {
            'type': 'weekly',
            'weekdays': ['sun'],
            'annual_date': null,
          },
          minimumQuantity: '5',
        ),
      );
      expect(discount.type, DiscountType.percentage);
      expect(discount.percent, '20');
      expect(discount.regularPrice.display, 'CHF 100.00');
      expect(discount.preview.unitPrice?.cents, 8000);
      expect(discount.schedule?.hasEnd, isFalse);
      expect(discount.schedule?.timezone, 'Europe/Zurich');
      expect(discount.repeat.weekdays, {Weekday.sun});
      expect(discount.minimumQuantity, '5');
      expect(discount.canPause, isTrue);
      expect(discount.canResume, isFalse);
    });

    test('anything off-contract is a protocol failure', () {
      for (final broken in [
        {...discountPayload(), 'type': 'bogo'},
        {...discountPayload(), 'version': ''},
        {
          ...discountPayload(),
          'regular_price': {'amount': 'x', 'currency': 'CHF'},
        },
        {...discountPayload(), 'paused': 'no'},
        {
          ...discountPayload(),
          'schedule': {'start_date': '2026-02-30', 'start_time': '09:00'},
        },
      ]) {
        expect(
          () => DiscountModel.parse(broken),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.protocol,
            ),
          ),
        );
      }
    });

    test('the body is the whole form, unused members null', () {
      final body = DiscountInputModel.toJson(
        const DiscountDraft(
          type: DiscountType.collective,
          bundleQuantity: '5',
          bundlePrice: '400',
          percent: '20',
          schedule: DiscountSchedule(
            startDate: LocalDate(2026, 10, 14),
            startTime: TimeOfDayValue(9, 0),
            endDate: LocalDate(2026, 10, 21),
            endTime: TimeOfDayValue(9, 0),
          ),
          repeat: DiscountRepeat(RepeatType.weekly, weekdays: {Weekday.sun}),
          minimumQuantity: '2,5',
        ),
      );
      expect(body, {
        'type': 'collective',
        'fixed_price': null,
        'percent': null,
        'bundle_quantity': '5',
        'bundle_price': '400.00',
        'schedule': {
          'start_date': '2026-10-14',
          'start_time': '09:00',
          'end_date': '2026-10-21',
          'end_time': '09:00',
        },
        'repeat': {
          'type': 'weekly',
          'weekdays': ['sun'],
          'annual_date': null,
        },
        'minimum_quantity': '2.5',
      });
      expect(DiscountInputModel.toJson(percentage)['repeat'], {
        'type': 'none',
        'weekdays': null,
        'annual_date': null,
      });
    });
  });

  group('requests', () {
    test('list reads the product discounts without write headers', () async {
      server.on(
        'GET /products/10/discounts',
        (_) => FakeReply(200, _ok(discountListPayload([discountPayload()]))),
      );
      final list = await repository.list(10);
      expect(list.counts.total, 1);
      expect(list.limitReached, isFalse);
      final request = server.called('GET /products/10/discounts').single;
      expect(request.headers['Idempotency-Key'], isNull);
      expect(request.headers['If-Match'], isNull);
    });

    test('a list of another product is rejected', () async {
      server.on(
        'GET /products/10/discounts',
        (_) => FakeReply(
          200,
          _ok(discountListPayload([discountPayload(productId: 11)])),
        ),
      );
      await expectLater(repository.list(10), throwsA(isA<AppFailure>()));
    });

    test(
      'create sends an Idempotency-Key and the body, never If-Match',
      () async {
        server.on(
          'POST /products/10/discounts',
          (_) => FakeReply(201, _ok(discountPayload(id: 7))),
        );
        final created = await repository.create(10, percentage);
        expect(created.id, 7);
        final request = server.called('POST /products/10/discounts').single;
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        expect(request.headers['If-Match'], isNull);
        expect((request.data as Map)['percent'], '20');
      },
    );

    test(
      'update, archive, pause and resume send If-Match with the version',
      () async {
        final current = discountOf(id: 3, version: 'abc');
        server
          ..on(
            'PUT /discounts/3',
            (_) => FakeReply(200, _ok(discountPayload(id: 3))),
          )
          ..on(
            'DELETE /discounts/3',
            (_) => FakeReply(200, _ok(discountPayload(id: 3, active: false))),
          )
          ..on(
            'POST /discounts/3/pause',
            (_) => FakeReply(200, _ok(discountPayload(id: 3, paused: true))),
          )
          ..on(
            'POST /discounts/3/resume',
            (_) => FakeReply(200, _ok(discountPayload(id: 3))),
          );
        await repository.update(current, percentage);
        await repository.archive(current);
        await repository.pause(current);
        await repository.resume(current);
        for (final route in [
          'PUT /discounts/3',
          'DELETE /discounts/3',
          'POST /discounts/3/pause',
          'POST /discounts/3/resume',
        ]) {
          final request = server.called(route).single;
          expect(request.headers['If-Match'], '"abc"', reason: route);
          expect(request.headers['Idempotency-Key'], isNotEmpty, reason: route);
        }
        expect(server.called('POST /discounts/3/pause').single.data, isEmpty);
      },
    );

    test('a new intent gets a new key; an uncertain one reuses it', () async {
      var attempt = 0;
      server.on('POST /products/10/discounts', (request) {
        attempt++;
        if (attempt == 1) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          );
        }
        return FakeReply(201, _ok(discountPayload(id: 7)));
      });
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      // The open create is settled by replaying it; then a new intent.
      await repository.resolvePendingCreate(10);
      await repository.create(10, percentage);
      final keys = [
        for (final request in server.called('POST /products/10/discounts'))
          request.headers['Idempotency-Key'],
      ];
      expect(keys[0], keys[1], reason: 'the identical retry replays');
      expect(keys[2], isNot(keys[1]), reason: 'a confirmed write settles it');
    });

    test('VERSION_CONFLICT is reported once and never retried', () async {
      server.on(
        'PUT /discounts/3',
        (_) => FakeReply(412, _error('VERSION_CONFLICT')),
      );
      await expectLater(
        repository.update(discountOf(id: 3), percentage),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
        ),
      );
      expect(server.called('PUT /discounts/3'), hasLength(1));
    });

    test('field errors and whole-discount rules keep their codes', () async {
      server.on(
        'POST /products/10/discounts',
        (_) => FakeReply(
          422,
          _error(
            'BUSINESS_RULE_VIOLATION',
            details: [
              {'code': 'PRODUCT_NOT_DISCOUNTABLE', 'message': 'Weighed.'},
              {'field': 'schedule.end_date', 'code': 'END_IN_PAST'},
            ],
          ),
        ),
      );
      final failure = await repository
          .create(10, percentage)
          .then<AppFailure?>(
            (_) => null,
            onError: (Object e) => e as AppFailure,
          );
      expect(failure!.fieldErrors.map((e) => (e.field, e.code)), [
        ('', 'PRODUCT_NOT_DISCOUNTABLE'),
        ('schedule.end_date', 'END_IN_PAST'),
      ]);
      expect(failure.fieldErrors.first.message, 'Weighed.');
    });

    test('a revoked session is signed out', () async {
      server.on(
        'GET /discounts/3',
        (_) => FakeReply(401, _error('TOKEN_REVOKED')),
      );
      await expectLater(repository.get(3), throwsA(isA<AppFailure>()));
      expect(rejected, 1);
    });

    test('a shop without the discount addon answers 404', () async {
      server.on(
        'GET /products/10/discounts',
        (_) => FakeReply(404, _error('NOT_FOUND')),
      );
      await expectLater(
        repository.list(10),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.notFound),
        ),
      );
    });
  });

  test('the payload fixtures are JSON', () {
    expect(
      () => jsonEncode(discountListPayload([discountPayload()])),
      returnsNormally,
    );
  });

  group('pending creates', () {
    late PendingWrites pending;
    late DateTime now;
    OdooDiscountRepository repositoryOver(PendingWrites writes) =>
        OdooDiscountRepository(
          DiscountRemoteDataSource(fakeProductApi(server)),
          pendingWrites: writes,
        );
    List<RequestOptions> posts([int productId = 10]) =>
        server.called('POST /products/$productId/discounts');
    String? keyOf(RequestOptions request) =>
        request.headers['Idempotency-Key'] as String?;

    /// A server that commits every new key once, loses the first answer
    /// (when [lose]), and replays a known key, like the real one.
    void committingServer({bool lose = true, int productId = 10}) {
      final byKey = <String, Map<String, dynamic>>{};
      var next = 7;
      var loseAnswer = lose;
      server.on('POST /products/$productId/discounts', (request) {
        final key = keyOf(request)!;
        final known = byKey[key];
        if (known != null) return FakeReply(201, _ok(known));
        final created = byKey[key] = discountPayload(
          id: next++,
          productId: productId,
        );
        if (loseAnswer) {
          loseAnswer = false;
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return FakeReply(201, _ok(created));
      });
    }

    setUp(() {
      now = DateTime.utc(2026, 11, 12, 8);
      pending = PendingWrites(now: () => now);
      repository = repositoryOver(pending);
    });

    // AUD-12 / CodeRabbit: a create the server accepted with an unreadable
    // result keeps blocking new creates until the user resolves it.
    for (final (name, data) in [
      ('unreadable data', <String, Object?>{'id': 'not-a-discount'}),
      ('another product', discountPayload(id: 7, productId: 11)),
    ]) {
      test('a success reply with $name blocks new creates', () async {
        server.on(
          'POST /products/10/discounts',
          (request) => FakeReply(201, _ok(data)),
        );
        await expectLater(
          repository.create(10, percentage),
          throwsA(
            isA<AppFailure>().having(
              (failure) => failure.code,
              'code',
              DiscountRefusal.pendingCreateCommitted,
            ),
          ),
        );
        final open = repository.pendingCreate(10)!;
        expect(open.committed, isTrue);
        expect(open.replayable, isFalse);
        expect(open.draft.percent, '20');
        // No fresh create and no replay of the unreadable reply is sent.
        await expectLater(
          repository.create(10, percentage),
          throwsA(
            isA<AppFailure>().having(
              (failure) => failure.code,
              'code',
              DiscountRefusal.pendingCreate,
            ),
          ),
        );
        await expectLater(
          repository.resolvePendingCreate(10),
          throwsA(
            isA<AppFailure>().having(
              (failure) => failure.code,
              'code',
              DiscountRefusal.pendingCreateCommitted,
            ),
          ),
        );
        expect(posts(), hasLength(1));
        // Only the user's explicit decision releases it.
        repository.discardPendingCreate(10);
        expect(repository.pendingCreate(10), isNull);
        expect(pending['discount-create:product:10'], isNull);
      });
    }

    test('an open create stays pending exactly as sent', () async {
      committingServer();
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      final open = repository.pendingCreate(10)!;
      expect(open.draft.percent, '20');
      expect(open.replayable, isTrue);
      // Another create for the product is refused before anything is sent,
      // also with a formatting-only change.
      await expectLater(
        repository.create(
          10,
          const DiscountDraft(type: DiscountType.percentage, percent: '20.00'),
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            DiscountRefusal.pendingCreate,
          ),
        ),
      );
      expect(posts(), hasLength(1));
      final created = await repository.resolvePendingCreate(10);
      expect(created.id, 7);
      expect(posts(), hasLength(2));
      expect(keyOf(posts()[1]), keyOf(posts()[0]));
      expect(jsonEncode(posts()[1].data), jsonEncode(posts()[0].data));
      expect(repository.pendingCreate(10), isNull);
    });

    test('a rebuilt repository of the session replays the same key', () async {
      committingServer();
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      // The form closed and the repository was rebuilt; the session store
      // stays.
      final rebuilt = repositoryOver(pending);
      expect(rebuilt.pendingCreate(10)?.draft.percent, '20');
      await rebuilt.resolvePendingCreate(10);
      expect(keyOf(posts()[1]), keyOf(posts()[0]));
      expect(jsonEncode(posts()[1].data), jsonEncode(posts()[0].data));
    });

    test('repeated failures, 401 and 429 keep the original request', () async {
      var attempt = 0;
      server.on('POST /products/10/discounts', (request) {
        attempt++;
        return switch (attempt) {
          1 || 2 => throw DioException(
            requestOptions: request,
            type: attempt == 1
                ? DioExceptionType.receiveTimeout
                : DioExceptionType.connectionError,
          ),
          3 => FakeReply(429, _error('RATE_LIMITED')),
          _ => FakeReply(201, _ok(discountPayload(id: 7))),
        };
      });
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          repository.resolvePendingCreate(10),
          throwsA(isA<AppFailure>()),
        );
        expect(repository.pendingCreate(10), isNotNull);
      }
      await repository.resolvePendingCreate(10);
      final keys = posts().map(keyOf).toSet();
      expect(keys, hasLength(1), reason: 'never regenerated');
      expect(posts().map((r) => jsonEncode(r.data)).toSet(), hasLength(1));
      expect(repository.pendingCreate(10), isNull);
    });

    test('a 401 leaves it pending for the same session', () async {
      var attempt = 0;
      server.on('POST /products/10/discounts', (request) {
        attempt++;
        if (attempt == 1) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return FakeReply(401, _error('TOKEN_EXPIRED'));
      });
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        repository.resolvePendingCreate(10),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.unauthenticated,
          ),
        ),
      );
      expect(repository.pendingCreate(10), isNotNull);
    });

    test('a definitive refusal settles it', () async {
      var attempt = 0;
      server.on('POST /products/10/discounts', (request) {
        attempt++;
        if (attempt == 1) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return FakeReply(
          422,
          _error(
            'BUSINESS_RULE_VIOLATION',
            details: [
              {'field': '', 'code': 'DISCOUNT_LIMIT_REACHED'},
            ],
          ),
        );
      });
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        repository.resolvePendingCreate(10),
        throwsA(isA<AppFailure>()),
      );
      expect(repository.pendingCreate(10), isNull);
    });

    test('overlapping creates for a product never both go out', () async {
      final answer = Completer<FakeReply>();
      server.on('POST /products/10/discounts', (request) => answer.future);
      final first = repository.create(10, percentage);
      await expectLater(
        repository.create(10, percentage),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            DiscountRefusal.pendingCreate,
          ),
        ),
      );
      answer.complete(FakeReply(201, _ok(discountPayload(id: 7))));
      expect((await first).id, 7);
      expect(posts(), hasLength(1));
      expect(repository.pendingCreate(10), isNull);
    });

    test('pending creates are per product', () async {
      committingServer();
      committingServer(lose: false, productId: 11);
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      expect(repository.pendingCreate(11), isNull);
      final other = await repository.create(11, percentage);
      expect(other.productId, 11);
      expect(repository.pendingCreate(10), isNotNull);
    });

    test('another session store has nothing pending', () async {
      committingServer();
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      final otherSession = repositoryOver(PendingWrites(now: () => now));
      expect(otherSession.pendingCreate(10), isNull);
    });

    test('past the replay window it is never replayed blindly', () async {
      committingServer();
      await expectLater(
        repository.create(10, percentage),
        throwsA(isA<AppFailure>()),
      );
      // A replayable one cannot be discarded.
      repository.discardPendingCreate(10);
      expect(repository.pendingCreate(10), isNotNull);
      now = now.add(PendingWrites.replayWindow);
      expect(repository.pendingCreate(10)!.replayable, isFalse);
      await expectLater(
        repository.resolvePendingCreate(10),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            DiscountRefusal.pendingCreateExpired,
          ),
        ),
      );
      expect(posts(), hasLength(1), reason: 'nothing replayed');
      // Only the user's explicit decision drops it.
      repository.discardPendingCreate(10);
      expect(repository.pendingCreate(10), isNull);
    });
  });
}
