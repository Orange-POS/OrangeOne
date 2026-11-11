import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/discounts/data/data_sources/discount_remote_data_source.dart';
import 'package:orange_one/features/discounts/data/models/discount_model.dart';
import 'package:orange_one/features/discounts/data/repositories/odoo_discount_repository.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';

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
      await repository.create(10, percentage);
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
}
