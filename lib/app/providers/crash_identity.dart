import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/core/monitoring/crash_reporter.dart';

/// Keeps the crash reporter's identity in step with the verified session:
/// numeric company and POS ids after sign-in, cleared on logout, expiry or an
/// authentication rejection. `companyId` and `posConfigId` are the session
/// fields; how they map to a customer or shop is a backend decision, so they
/// are reported under their own names.
final crashIdentityProvider = Provider<void>((ref) {
  final reporter = ref.watch(crashReporterProvider);
  ref.listen(activeSessionProvider, (previous, session) {
    reporter.setIdentity(
      session == null
          ? null
          : CrashIdentity(
              companyId: session.companyId,
              posConfigId: session.posConfigId,
            ),
    );
  }, fireImmediately: true);
}, name: 'crashIdentityProvider');
