import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/bootstrap/bootstrap_resolver.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/startup/domain/entities/startup_workflow.dart';

import '../../support/auth_fakes.dart';

const AsyncValue<AuthSession?> _signedOut = AsyncData(null);
final AsyncValue<AuthSession?> _signedIn = AsyncData(testSession);

String? _resolve(
  String path, {
  AsyncValue<AuthSession?>? session,
  StartupConfiguration startup = StartupConfiguration.fallback,
  CompatibilityStatus compatibility = CompatibilityStatus.compatible,
  bool demo = false,
}) => bootstrapRedirect(
  session: session ?? _signedOut,
  path: path,
  startup: startup,
  compatibility: compatibility,
  demo: demo,
);

void main() {
  group('starting component', () {
    test('signed out: the saved workflow entry after the splash', () {
      expect(_resolve('/startup'), '/login');
      expect(_resolve('/home'), '/login');
      expect(_resolve('/login'), isNull);
      expect(_resolve('/login/scan'), isNull);
    });

    test('an unavailable saved workflow opens the fallback entry', () {
      const credentials = StartupConfiguration(
        workflow: StartupWorkflow.credentialsLogin,
      );
      expect(_resolve('/startup', startup: credentials), '/login');
      expect(_resolve('/login', startup: credentials), isNull);
    });

    test('authentication rules are unchanged', () {
      expect(_resolve('/startup', session: _signedIn), '/home');
      expect(_resolve('/login', session: _signedIn), '/home');
      expect(_resolve('/home', session: _signedIn), isNull);
      expect(
        _resolve('/home', session: const AsyncLoading<AuthSession?>()),
        '/startup',
      );
      expect(_resolve('/settings'), isNull);
      expect(_resolve('/login', demo: true), '/home');
    });
  });

  group('compatibility', () {
    for (final status in [
      CompatibilityStatus.appUpgradeRequired,
      CompatibilityStatus.backendUnsupported,
      CompatibilityStatus.maintenance,
    ]) {
      test('$status: signed-in screens show the compatibility screen', () {
        for (final path in ['/home', '/home/scan', '/home/products/stock']) {
          expect(
            _resolve(path, session: _signedIn, compatibility: status),
            compatibilityPath,
            reason: path,
          );
        }
        expect(
          _resolve(
            compatibilityPath,
            session: _signedIn,
            compatibility: status,
          ),
          isNull,
        );
      });
    }

    test('the compatibility screen leaves once compatible or signed out', () {
      expect(_resolve(compatibilityPath, session: _signedIn), '/home');
      expect(
        _resolve(
          compatibilityPath,
          compatibility: CompatibilityStatus.maintenance,
        ),
        '/login',
      );
    });

    test('Demo Mode is never blocked', () {
      expect(
        _resolve(
          '/home',
          demo: true,
          compatibility: CompatibilityStatus.maintenance,
        ),
        isNull,
      );
    });

    test('settings stay reachable while blocked', () {
      expect(
        _resolve(
          '/settings',
          session: _signedIn,
          compatibility: CompatibilityStatus.maintenance,
        ),
        isNull,
      );
    });
  });
}
