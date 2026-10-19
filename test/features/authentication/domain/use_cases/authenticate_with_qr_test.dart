import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/authentication/domain/repositories/auth_repository.dart';
import 'package:orange_one/features/authentication/domain/use_cases/authenticate_with_qr.dart';

import '../../../../support/auth_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository;

void main() {
  late MockAuthRepository repository;
  late AuthenticateWithQr authenticate;
  setUp(() {
    repository = MockAuthRepository();
    authenticate = AuthenticateWithQr(repository);
  });
  test('passes an accepted QR payload unchanged to the repository', () async {
    const payload = ' fixture QR ';
    when(() => repository.signIn(payload)).thenAnswer((_) async => testSession);
    expect(await authenticate(payload), testSession);
    verify(() => repository.signIn(payload)).called(1);
  });
  test('empty and oversized input never reaches authentication', () {
    for (final value in ['', '  ', List.filled(8193, 'a').join()]) {
      expect(() => authenticate(value), throwsFormatException);
    }
    verifyZeroInteractions(repository);
  });
  test('repository auth failure remains typed', () async {
    const failure = AppFailure(FailureKind.expiredQr, 'QR expired');
    when(() => repository.signIn('fixture')).thenThrow(failure);
    expect(() => authenticate('fixture'), throwsA(same(failure)));
  });
}

