import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/logging/app_logger.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';
import 'package:orange_one/core/monitoring/error_reference.dart';
import 'package:orange_one/core/monitoring/firebase_crash_reporter.dart';
import 'package:orange_one/core/monitoring/reportable_failure.dart';

class _MockCrashlytics extends Mock implements FirebaseCrashlytics;

const _secret = 'oa_SECRET_TOKEN_1234 https://pos.example/qr?nonce=abc';

void main() {
  setUpAll(() => registerFallbackValue(StackTrace.empty));

  late _MockCrashlytics crashlytics;
  late Map<String, String> keys;
  late List<String> logs;
  late List<({Object error, String? reason, bool fatal})> recorded;
  var now = DateTime.utc(2030);
  var references = 0;

  FirebaseCrashReporter reporter() => FirebaseCrashReporter(
    crashlytics,
    environment: AppEnvironment.development,
    clock: () => now,
    newReference: () => 'OO-TEST${references++}',
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    crashlytics = _MockCrashlytics();
    keys = {};
    logs = [];
    recorded = [];
    now = DateTime.utc(2030);
    references = 0;
    when(() => crashlytics.setCustomKey(any(), any())).thenAnswer((call) async {
      keys[call.positionalArguments[0] as String] =
          '${call.positionalArguments[1]}';
    });
    when(() => crashlytics.log(any())).thenAnswer((call) async {
      logs.add(call.positionalArguments[0] as String);
    });
    when(
      () => crashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any<String?>(named: 'reason'),
        fatal: any<bool>(named: 'fatal'),
      ),
    ).thenAnswer((call) async {
      recorded.add((
        error: call.positionalArguments[0] as Object,
        reason: call.namedArguments[#reason] as String?,
        fatal: (call.namedArguments[#fatal] as bool?) ?? false,
      ));
    });
    when(() => crashlytics.setCrashlyticsCollectionEnabled(any()))
        .thenAnswer((_) async {});
    when(() => crashlytics.crash()).thenReturn(null);
  });

  group('ErrorReference', () {
    test('is short, readable, valid and not repeated', () {
      final values = {for (var i = 0; i < 200; i++) ErrorReference.generate()};
      expect(values.length, 200);
      for (final value in values) {
        expect(ErrorReference.isValid(value), isTrue, reason: value);
        expect(value.length, 9);
        expect(value.substring(3), isNot(matches('[01OIL]')));
      }
      expect(ErrorReference.isValid('OO-ABC'), isFalse);
      expect(ErrorReference.isValid('xx-ABCDEF'), isFalse);
    });
  });

  group('report policy', () {
    test('expected business outcomes are never reported', () {
      for (final kind in [
        FailureKind.validation,
        FailureKind.conflict,
        FailureKind.expiredQr,
        FailureKind.usedQr,
        FailureKind.unsupportedQr,
        FailureKind.unauthenticated,
        FailureKind.forbidden,
        FailureKind.cancelled,
        FailureKind.notFound,
        FailureKind.rateLimited,
        FailureKind.upgradeRequired,
      ]) {
        expect(reportPolicyFor(kind), ReportPolicy.never, reason: kind.name);
      }
    });

    test('technical faults are reported, unreachable servers throttled', () {
      for (final kind in [
        FailureKind.protocol,
        FailureKind.backend,
        FailureKind.storage,
        FailureKind.configuration,
      ]) {
        expect(reportPolicyFor(kind), ReportPolicy.always, reason: kind.name);
      }
      expect(reportPolicyFor(FailureKind.network), ReportPolicy.throttled);
      expect(reportPolicyFor(FailureKind.timeout), ReportPolicy.throttled);
    });

    test('operation labels keep only fixed endpoint words', () {
      expect(
        operationLabel('post', '/products/42/stock-adjustments'),
        'POST /products/{id}/stock-adjustments',
      );
      expect(
        operationLabel('get', '/products/by-barcode/7612345678900?x=1'),
        'GET /products/by-barcode/{id}',
      );
      expect(
        operationLabel('get', '/products/oa_secret_token_9'),
        'GET /products/{id}',
      );
      expect(
        operationLabel('post', '/auth/qr-exchange'),
        'POST /auth/qr-exchange',
      );
      expect(operationLabel('get', '/oa_SECRET_TOKEN'), 'GET /{id}');
    });
  });

  group('FirebaseCrashReporter', () {
    test('expected failures send nothing and return no reference', () {
      final result = reporter().recordFailure(
        const AppFailure(FailureKind.validation, 'Name is required'),
        operation: 'POST /products',
      );
      expect(result, isNull);
      verifyNever(() => crashlytics.recordError(any<Object>(), any()));
    });

    test(
      'technical failures send a sanitized report with a reference',
      () async {
        final reference = reporter().recordFailure(
          const AppFailure(
            FailureKind.backend,
            'Server said: $_secret',
            code: 'INTERNAL_ERROR',
            requestId: 'req-123',
          ),
          operation: 'POST /products/{id}/stock-adjustments',
        );
        await settle();
        expect(reference, 'OO-TEST0');
        expect(keys['error_id'], 'OO-TEST0');
        expect(keys['failure_kind'], 'backend');
        expect(keys['api_code'], 'INTERNAL_ERROR');
        expect(keys['request_id'], 'req-123');
        expect(keys['operation'], 'POST /products/{id}/stock-adjustments');
        expect(logs, ['error_id=OO-TEST0']);
        expect(recorded.single.fatal, isFalse);
        final everything = [
          ...keys.values,
          ...logs,
          recorded.single.error.toString(),
          recorded.single.reason,
        ].join(' ');
        expect(everything, isNot(contains('SECRET')));
        expect(everything, isNot(contains('pos.example')));
      },
    );

    test('unreachable-server failures are throttled per operation', () {
      final r = reporter();
      const failure = AppFailure(FailureKind.network, 'Offline');
      expect(r.recordFailure(failure, operation: 'GET /products'), isNotNull);
      expect(r.recordFailure(failure, operation: 'GET /products'), isNull);
      expect(r.recordFailure(failure, operation: 'POST /products'), isNotNull);
      now = now.add(const Duration(minutes: 6));
      expect(r.recordFailure(failure, operation: 'GET /products'), isNotNull);
    });

    test(
      'framework and async errors are fatal and carry only their type',
      () async {
        reporter().recordFatal(
          StateError('token $_secret leaked'),
          StackTrace.current,
        );
        await settle();
        expect(recorded.single.fatal, isTrue);
        expect(recorded.single.error.toString(), 'Unhandled StateError');
      },
    );

    test(
      'identity holds numeric POS ids only and clears on sign-out',
      () async {
        final r = reporter()
          ..setIdentity(const CrashIdentity(companyId: 7, posConfigId: 3));
        await settle();
        expect(keys['company_id'], '7');
        expect(keys['pos_config_id'], '3');
        expect(keys['environment'], 'development');
        expect(keys.keys, isNot(contains('user_id')));
        r.setIdentity(null);
        await settle();
        expect(keys['company_id'], isEmpty);
        expect(keys['pos_config_id'], isEmpty);
      },
    );

    test('plugin failures never reach the application', () {
      when(() => crashlytics.setCustomKey(any(), any()))
          .thenThrow(StateError('plugin down'));
      when(() => crashlytics.crash()).thenThrow(StateError('plugin down'));
      final r = reporter();
      expect(
        () => r.recordFailure(
          const AppFailure(FailureKind.backend, 'x'),
          operation: 'GET /products',
        ),
        returnsNormally,
      );
      expect(
        () => r.recordFatal(Object(), StackTrace.current),
        returnsNormally,
      );
      expect(() => r.setIdentity(null), returnsNormally);
      expect(r.recordTestNonFatal, returnsNormally);
      expect(r.triggerTestCrash, returnsNormally);
    });

    test('test controls call Crashlytics', () async {
      reporter()
        ..recordTestNonFatal()
        ..triggerTestCrash();
      await settle();
      verify(() => crashlytics.crash()).called(1);
      expect(recorded.single.error.toString(), contains('non-fatal'));
    });
  });

  group('initializeCrashReporting', () {
    final events = <String>[];
    late AppLogger logger;
    setUp(() {
      events.clear();
      logger = AppLogger(
        environment: AppEnvironment.development,
        enabled: true,
        debugBuild: true,
        sink: (record) =>
            events.add(RegExp(r'"event":"(\w+)"').firstMatch(record)![1]!),
      );
    });

    test('uses Firebase when it initializes', () async {
      final result = await initializeCrashReporting(
        environment: AppEnvironment.development,
        logger: logger,
        initialize: () async => null,
        crashlytics: () => crashlytics,
      );
      expect(result, isA<FirebaseCrashReporter>());
      verify(() => crashlytics.setCrashlyticsCollectionEnabled(false))
          .called(1);
      expect(events, isEmpty);
    });

    test('a missing configuration falls back to the no-op reporter', () async {
      final result = await initializeCrashReporting(
        environment: AppEnvironment.production,
        logger: logger,
        initialize: () async => throw StateError('no GoogleService file'),
        crashlytics: () => crashlytics,
      );
      expect(result, isA<NoopCrashReporter>());
      expect(events, ['monitoringUnavailable']);
    });

    test('a hanging initialization does not block startup', () async {
      final result = await initializeCrashReporting(
        environment: AppEnvironment.staging,
        logger: logger,
        initialize: () => Completer<Object?>().future,
        crashlytics: () => crashlytics,
        timeout: const Duration(milliseconds: 20),
      );
      expect(result, isA<NoopCrashReporter>());
    });

    test('the no-op reporter accepts every call', () {
      const noop = NoopCrashReporter();
      noop
        ..recordFatal(Object(), StackTrace.current)
        ..setIdentity(null)
        ..recordTestNonFatal()
        ..triggerTestCrash();
      expect(
        noop.recordFailure(
          const AppFailure(FailureKind.backend, 'x'),
          operation: 'GET /products',
        ),
        isNull,
      );
    });
  });
}
